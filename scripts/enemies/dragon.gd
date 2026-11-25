class_name Dragon
extends Combatant

## The boss on the mountain, and the win condition: kill it and the run is over.
##
## The model is MattBas's dragon (art/models/dragon_mattbas.glb, CC BY-SA 4.0), which brings its
## own idle, walk, run and flying loops. Its attacks are posed on top of those by DragonPoser from
## DragonAnimator's tables, so the bone names there are the interface to the model.
##
## Between fights it does not sit still. Every minute or so it takes off from the summit and flies
## a loop round the map (DragonFlight), now and then pouring fire onto the ground below, and comes
## back to its perch. Its shadow sweeps over the ground under it, and every breath of fire comes
## with a roar heard from a long way off. Anyone climbing onto the summit while it is out calls it
## home, and the fight starts when it lands.
##
## The fight is a positioning puzzle rather than a damage race. The dragon barely moves; each
## of its four attacks owns a different band of ground around it, so there is no safe distance,
## only a distance that is safe *right now*. Every one of them knocks back hard, and the arena
## is a 28 m platform with a long drop off every edge -- being thrown off and having to climb
## back up is the intended failure state, not an accident.
##
## Host-authoritative like every other monster: clients see the poses and the fire, and the
## host alone decides what any of it hit.

signal phase_changed(enraged: bool)
signal defeated

const MODEL_PATH := "res://art/models/dragon_mattbas.glb"
## The model stands 2.7 units tall with a 12.4-unit wingspan; this makes it a 5 m dragon with
## wings 22 m across, which is a boss.
const MODEL_SCALE := 1.8
## Its own loops, by the start of their names (the importer may keep or drop a "-loop" suffix).
const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"
const ANIM_FLY := "Flying"

## Flights: how long it sits on the summit between them, and how often it breathes fire while out.
const FIRST_FLIGHT := 35.0
const FLIGHT_GAP := Vector2(55.0, 90.0)
const SPRAY_GAP := Vector2(5.0, 9.0)
## Fire poured from the air: patches this far apart, starting this far ahead along the route.
const SPRAY_PATCHES := 4
const SPRAY_AHEAD := 6.0
const SPRAY_SPACING := 4.0
const SPRAY_RADIUS := 2.4
## Its scales change with the season. The model is painted from a 16x16 palette whose body
## swatches are blue; those are turned to the season's hue (and lightness, for spring's pink)
## and everything else -- belly, mouth, eyes, horns -- is left alone. Winter keeps it blue.
## Each: [hue, saturation scale, value scale], or empty for the model's own colours.
const SEASON_SCALES: Array = [
	[0.93, 0.75, 1.15],  ## spring: pink
	[0.33, 1.0, 0.95],   ## summer: green
	[0.0, 1.05, 0.95],   ## fall: red
	[],                  ## winter: its own blue
]

## A roar carries: heard this many times further than an ordinary sound.
const ROAR_REACH := 3.0

enum State { DORMANT, ROARING, STALKING, ATTACKING, RECOVERING, DEAD }
## What a flight is doing: sat on the perch, out on a tour, or heading straight home.
enum Flight { PERCHED, TOUR, HOME }

## Halved from 240 when every player attack went to one point, so the fight still takes about
## as many hits as it did.
const MAX_HEALTH := 120
## Below this fraction the dragon speeds up and its breath leaves more fire. A second gear
## rather than a second moveset: the party has already learned the tells by then, and the fight
## should get harder without becoming a different fight.
const ENRAGE_AT := 0.5
const ENRAGE_SPEED := 0.68

## How far a player has to be from the arena centre before the dragon stops counting them as
## present. Generous, so someone hanging off the lip is still in the fight.
const ENGAGE_MARGIN := 6.0
## Seconds with nobody on the platform before the fight resets. Long enough that a player
## knocked off has a moment to scramble back, short enough that a wipe means a real reset.
const RESET_DELAY := 6.0
## Degrees per second the dragon can turn. Slow on purpose -- circling behind it is a real
## tactic, and the tail sweep is the answer to it.
const TURN_SPEED := 70.0
## It shuffles toward a target that stays out of reach rather than chasing properly. Nobody
## should be able to plink it from the lip forever.
const STALK_SPEED := 2.4

## Each attack owns a band of ground. The bands overlap so there is always something available,
## but never everything. `hit_at` is read against the clip's own timeline in DragonAnimator, so
## the damage lands on the frame the animation looks like it lands.
const ATTACKS := {
	"claw": {
		"clip": "claw", "hit_at": 0.68, "cooldown": 3.4,
		"min_range": 0.0, "max_range": 10.0, "arc": 55.0, "reach": 10.0,
		"damage": 2, "knockback": 15.0, "lift": 0.3, "behind": false,
	},
	"wing_flap": {
		"clip": "wing_flap", "hit_at": 0.68, "cooldown": 6.0,
		"min_range": 0.0, "max_range": 13.0, "radius": 14.0,
		"damage": 1, "knockback": 19.0, "lift": 0.55, "nova": true,
	},
	"tail_sweep": {
		"clip": "tail_sweep", "hit_at": 1.15, "cooldown": 8.5,
		"min_range": 0.0, "max_range": 18.0, "arc": 115.0, "reach": 18.0,
		"damage": 1, "knockback": 34.0, "lift": 0.45, "behind": true,
	},
	## Reaches past the far lip of the platform. On a 48 m arena a shorter cone would leave a
	## ring of ground where the dragon simply cannot answer, and the fight would become standing
	## on it and plinking.
	"breath": {
		"clip": "breath", "hit_at": 1.15, "cooldown": 7.5,
		"min_range": 7.0, "max_range": 46.0, "arc": 26.0, "reach": 44.0,
		"damage": 2, "knockback": 9.0, "lift": 0.2, "fire": true,
	},
}

var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var poser: DragonPoser
var flight_state: Flight = Flight.PERCHED
var flight: DragonFlight
## Metres along the current flight.
var flight_distance: float = 0.0
## Where it sits between flights, and the way it faces there.
var perch: Vector3 = Vector3.ZERO
var perch_yaw: float = 0.0

var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _shadow: MeshInstance3D
var _anims: Dictionary = {}
var _flight_wait: float = FIRST_FLIGHT
var _spray_wait: float = 0.0
var _air_clip_time: float = -1.0
var state: State = State.DORMANT
var enraged: bool = false
var arena_centre: Vector3 = Vector3.ZERO
var arena_radius: float = 14.0

var _clip: String = ""
var _clip_time: float = 0.0
var _clip_length: float = 0.0
var _pending_hit: String = ""
var _cooldowns: Dictionary = {}
var _target: Combatant
var _empty_for: float = 0.0
var _state_timer: float = 0.0
var _abilities: Dictionary = {}
## Engagement and the "is anyone looking at me" test both walk the player list, which allocates.
## Neither needs answering every physics frame.
var _presence_timer: float = 0.0
var _present_cache: Array = []
var _visible_cache: bool = true


func configure(centre: Vector3 = Vector3.ZERO, radius: float = 14.0) -> void:
	faction = Faction.MONSTER
	max_health = MAX_HEALTH
	health = max_health
	## Immovable: a boss that can be shield-bashed off its own mountain is not a boss.
	knockback_resistance = 0.0
	## Matches the collision capsule below. Without a hit volume this size, melee reach is
	## measured to a point between the dragon's feet, which sits inside its own capsule -- so no
	## player could ever stand close enough to land a swing.
	hit_radius = 2.0
	hit_height = 5.0
	name = "Dragon"
	arena_centre = centre if centre != Vector3.ZERO else global_position
	arena_radius = radius

	perch = global_position
	perch_yaw = rotation.y
	_build_model()
	_build_shadow()

	Combatant.setup_body(self, hit_radius, hit_height)

	for id: String in ATTACKS:
		_abilities[id] = _build_ability(id)
	add_to_group("dragon")
	died.connect(_on_died)


## Attacks are AbilityData like everything else in the game, so they resolve through the same
## CombatResolver as a Knight's swing and cannot quietly skip knockback.
func _build_ability(id: String) -> AbilityData:
	var spec: Dictionary = ATTACKS[id]
	var ability := AbilityData.new()
	ability.id = StringName("dragon_%s" % id)
	ability.display_name = id.capitalize()
	ability.shape = AbilityData.Shape.NOVA if spec.get("nova", false) \
			else AbilityData.Shape.MELEE_ARC
	ability.damage = spec["damage"]
	ability.knockback = spec["knockback"]
	ability.knockback_lift = spec["lift"]
	ability.range = spec.get("reach", 10.0)
	ability.arc_degrees = spec.get("arc", 60.0)
	ability.radius = spec.get("radius", 3.0)
	ability.wind_up = 0.0  ## The clip's own hit_at is the timing; see _advance_clip.
	ability.cooldown = spec["cooldown"]
	ability.vfx_color = Color(1.0, 0.5, 0.2)
	return ability


func ability_for(id: String) -> AbilityData:
	return _abilities.get(id)


func is_engaged() -> bool:
	return state != State.DORMANT and state != State.DEAD


func health_fraction() -> float:
	return float(health) / float(max_health)


func _physics_process(delta: float) -> void:
	if is_flying():
		_fly(delta)
	else:
		_tick_knockback(delta)
		if not is_on_floor():
			velocity.y -= gravity() * delta
		clamp_speed()
		move_and_slide()

	_refresh_presence(delta)
	_advance_clip(delta)
	if _worth_posing():
		_pose(delta)
	_place_shadow()

	if state == State.DEAD or not NetworkManager.is_host():
		return
	_tick_flights(delta)

	for id: String in _cooldowns.keys():
		var remaining: float = _cooldowns[id] - delta
		if remaining <= 0.0:
			_cooldowns.erase(id)
		else:
			_cooldowns[id] = remaining
	_state_timer = maxf(0.0, _state_timer - delta)

	_check_enrage()
	_update_engagement(delta)

	match state:
		State.DORMANT:
			if _target != null and not is_flying():
				_begin_clip("roar")
				state = State.ROARING
				_state_timer = DragonAnimator.duration("roar")
		State.ROARING, State.RECOVERING:
			if _state_timer <= 0.0:
				state = State.STALKING
		State.STALKING:
			_stalk(delta)
			_maybe_attack()
		State.ATTACKING:
			_face_target(delta * 0.35)  ## Tracks a little mid-swing, but can be side-stepped.
			if _state_timer <= 0.0:
				state = State.RECOVERING
				_state_timer = 0.35


func _build_model() -> void:
	var packed: PackedScene = load(MODEL_PATH)
	if packed == null:
		push_error("Dragon: %s missing" % MODEL_PATH)
		return
	_model = packed.instantiate() as Node3D
	add_child(_model)
	_model.scale = Vector3.ONE * MODEL_SCALE
	## The model's head points along +Z; everything else in the game takes -Z as forward.
	_model.rotation.y = PI
	skeleton = _find_skeleton(_model)
	if skeleton == null:
		push_error("Dragon: model has no Skeleton3D")
		return
	poser = DragonPoser.new()
	poser.name = "AttackPoser"
	skeleton.add_child(poser)
	_meshes = Culling.meshes_under(_model)
	paint_for_season(Season.current)
	animation_player = _find_animation_player(_model)
	if animation_player != null:
		for wanted: String in [ANIM_IDLE, ANIM_WALK, ANIM_FLY]:
			for clip: StringName in animation_player.get_animation_list():
				if String(clip).begins_with(wanted):
					_anims[wanted] = clip
					animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
					break
		_play(ANIM_IDLE)


## Turns the dragon's scales to `kind`'s colour (see SEASON_SCALES).
func paint_for_season(kind: Season.Kind) -> void:
	for mesh in _meshes:
		for surface in mesh.get_surface_override_material_count():
			mesh.set_surface_override_material(surface, null)
			var original := mesh.get_active_material(surface) as StandardMaterial3D
			if original == null or original.albedo_texture == null \
					or (SEASON_SCALES[kind] as Array).is_empty():
				continue
			var painted := original.duplicate() as StandardMaterial3D
			painted.albedo_texture = Dragon.season_texture(original.albedo_texture, kind)
			mesh.set_surface_override_material(surface, ComicLook.convert_material(painted))
		ComicLook.apply(mesh)


## The palette texture with its blue swatches turned to the season's colour. Not cached: there is
## one dragon a match, and a texture held in a static outlives the renderer at shutdown.
static func season_texture(texture: Texture2D, kind: Season.Kind) -> Texture2D:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	return ImageTexture.create_from_image(season_image(image, kind))


## The recolouring itself, on an image: blue scale swatches to the season's hue.
static func season_image(source: Image, kind: Season.Kind) -> Image:
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var scales: Array = SEASON_SCALES[kind]
	if scales.is_empty():
		return image
	for y in image.get_height():
		for x in image.get_width():
			var colour := image.get_pixel(x, y)
			## Blue, and coloured enough to be scales rather than the pale belly.
			if colour.h < 0.5 or colour.h > 0.75 or colour.s < 0.25:
				continue
			image.set_pixel(x, y, Color.from_hsv(scales[0], clampf(colour.s * scales[1], 0.0, 1.0),
					clampf(colour.v * scales[2], 0.0, 1.0), colour.a))
	return image


## A soft dark shape under it on the ground while it flies. Its own mesh shadow is switched off
## in the air: from that high the sun would throw it somewhere off to one side.
func _build_shadow() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.4, 9.4) * MODEL_SCALE
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/enemies/dragon_shadow.gdshader")
	plane.material = material
	_shadow = MeshInstance3D.new()
	_shadow.name = "FlightShadow"
	_shadow.mesh = plane
	_shadow.top_level = true
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.visible = false
	add_child(_shadow)


func _play(which: String, blend: float = 0.3) -> void:
	if animation_player == null or not _anims.has(which):
		return
	if animation_player.current_animation != _anims[which]:
		animation_player.play(_anims[which], blend)


# --- engagement and reset ------------------------------------------------------------------

## Recomputes who is nearby, a few times a second rather than every frame. The answer drives
## both the fight and whether the rig is posed at all, and at a walking pace it cannot change
## meaningfully between ticks.
func _refresh_presence(delta: float) -> void:
	_presence_timer -= delta
	if _presence_timer > 0.0:
		return
	_presence_timer = 0.2
	_present_cache = players_in_arena()
	_visible_cache = Culling.distance_to_nearest_player(global_position) \
			<= Culling.MONSTER_VISIBLE_RANGE


## The players standing on the platform. Anyone knocked off stops counting immediately, which
## is what lets the fight notice it has been abandoned.
func players_in_arena() -> Array:
	var out: Array = []
	for body in PlayerRegistry.living_bodies():
		var player := body as Combatant
		if player == null:
			continue
		var offset := player.global_position - arena_centre
		offset.y = 0.0
		if offset.length() <= arena_radius + ENGAGE_MARGIN \
				and player.global_position.y > arena_centre.y - 8.0:
			out.append(player)
	return out


func _update_engagement(delta: float) -> void:
	var present := _present_cache
	if present.is_empty():
		_target = null
		if state == State.DORMANT:
			return
		_empty_for += delta
		if _empty_for >= RESET_DELAY:
			_reset_fight()
		return

	_empty_for = 0.0
	## Someone is on the summit while it is out: it comes straight home, and the fight starts when
	## it lands.
	if flight_state == Flight.TOUR:
		_call_home()
	## Prefers whoever is closest, so the party can pull its attention by stepping in -- and so
	## the melee classes are the ones it swings at, which is the shape the archetypes imply.
	var best: Combatant = null
	var best_distance := INF
	for player: Combatant in present:
		var distance := global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	_target = best


## Everyone fell off. Heal up, go back to sleep, and let them climb back for another go -- the
## fight restarting from the top is the price of losing the platform.
func _reset_fight() -> void:
	_empty_for = 0.0
	state = State.DORMANT
	_cooldowns.clear()
	_clip = ""
	_pending_hit = ""
	enraged = false
	if NetworkManager.is_networked():
		_net_reset.rpc(max_health)
	else:
		_net_reset(max_health)


@rpc("authority", "call_local", "reliable")
func _net_reset(restored: int) -> void:
	health = restored
	is_dead = false
	state = State.DORMANT
	enraged = false
	health_changed.emit(health, max_health)
	phase_changed.emit(false)
	_land()
	global_position = perch
	rotation.y = perch_yaw
	reset_physics_interpolation()


func _check_enrage() -> void:
	if enraged or health_fraction() > ENRAGE_AT:
		return
	enraged = true
	phase_changed.emit(true)
	_begin_clip("roar")
	state = State.ROARING
	_state_timer = DragonAnimator.duration("roar")


# --- movement and attacking ------------------------------------------------------------------

func _stalk(delta: float) -> void:
	_face_target(delta)
	if _target == null:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		return

	var offset := _target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	## Only closes when the target is beyond everything it can reach, and never leaves the
	## platform: walking off its own arena to chase an archer would be a comedy, not a boss.
	## Scaled to the platform: on a 48 m arena a 15 m threshold left it shuffling constantly.
	var wants_closer := distance > 22.0
	var from_centre := global_position - arena_centre
	from_centre.y = 0.0
	if wants_closer and from_centre.length() < arena_radius * 0.55 and distance > 0.001:
		var direction := offset / distance
		velocity.x = move_toward(velocity.x, direction.x * STALK_SPEED, 10.0 * delta)
		velocity.z = move_toward(velocity.z, direction.z * STALK_SPEED, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)


func _face_target(delta: float) -> void:
	if _target == null:
		return
	var offset := _target.global_position - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.001:
		return
	## -Z is forward, so the angle that points -Z along the offset.
	var wanted := atan2(-offset.x, -offset.z)
	rotation.y = lerp_angle(rotation.y, wanted, minf(1.0, deg_to_rad(TURN_SPEED) * delta))


func _maybe_attack() -> void:
	if _target == null or _clip != "":
		return
	var distance := global_position.distance_to(_target.global_position)
	var choices: Array[String] = []
	for id: String in ATTACKS:
		var spec: Dictionary = ATTACKS[id]
		if _cooldowns.has(id):
			continue
		if distance < float(spec["min_range"]) or distance > float(spec["max_range"]):
			continue
		choices.append(id)
	if choices.is_empty():
		return

	## Whatever has been waiting longest would be predictable; a straight pick from what is
	## currently legal keeps the party reading the tells rather than the rotation.
	var pick: String = choices[randi() % choices.size()]
	_launch(pick)


func _launch(id: String) -> void:
	var spec: Dictionary = ATTACKS[id]
	var cooldown: float = spec["cooldown"] * (ENRAGE_SPEED if enraged else 1.0)
	_cooldowns[id] = cooldown
	state = State.ATTACKING
	_state_timer = DragonAnimator.duration(spec["clip"])
	if NetworkManager.is_networked():
		_net_play.rpc(id)
	else:
		_net_play(id)


@rpc("authority", "call_local", "reliable")
func _net_play(id: String) -> void:
	var spec: Dictionary = ATTACKS.get(id, {})
	if spec.is_empty():
		return
	_begin_clip(spec["clip"])
	## Only the host resolves; clients run the clip purely so the animation matches.
	_pending_hit = id if NetworkManager.is_host() else ""
	if spec.get("fire", false):
		_breathe_soon(float(spec["hit_at"]) / (ENRAGE_SPEED if enraged else 1.0))


func _begin_clip(clip_name: String) -> void:
	_clip = clip_name
	_clip_time = 0.0
	_clip_length = DragonAnimator.duration(clip_name)


func _advance_clip(delta: float) -> void:
	if _clip == "":
		return
	var previous := _clip_time
	_clip_time += delta * (ENRAGE_SPEED if enraged and _clip != "death" else 1.0)

	if _pending_hit != "":
		var spec: Dictionary = ATTACKS[_pending_hit]
		var hit_at: float = spec["hit_at"]
		## Fires on the frame the clip crosses its hit time, so damage and animation cannot
		## drift apart no matter what the frame rate is doing.
		if previous < hit_at and _clip_time >= hit_at:
			_resolve(_pending_hit)
			_pending_hit = ""

	if _clip_time >= _clip_length and _clip != "death":
		_clip = ""
		_pending_hit = ""


func _resolve(id: String) -> void:
	if not NetworkManager.is_host():
		return
	var spec: Dictionary = ATTACKS[id]
	var ability: AbilityData = _abilities[id]
	var forward := -global_transform.basis.z
	## The tail is behind it. Passing the reversed facing to the same arc test is what makes
	## "get behind the boss" a decision with a downside instead of a free win.
	var facing := -forward if spec.get("behind", false) else forward

	if spec.get("nova", false):
		var caught := CombatResolver.radius_targets(get_tree(), self, hit_centre(), ability.radius)
		CombatResolver.apply(ability, self, caught, global_position)
	else:
		var struck := CombatResolver.arc_targets(get_tree(), self, global_position, facing, ability)
		CombatResolver.apply(ability, self, struck, global_position)

	if spec.get("fire", false):
		_lay_fire(forward)


## Fire is laid down the middle of the cone the breath just swept, so the ground that was
## dangerous stays dangerous.
func _lay_fire(forward: Vector3) -> void:
	## More patches, because the cone is now long enough that three would leave big gaps between
	## them and the fire would stop denying ground.
	var patches := 8 if enraged else 5
	var spacing: float = float(ATTACKS["breath"]["reach"]) / float(patches + 1)
	for i in range(1, patches + 1):
		var at := global_position + forward * (spacing * i)
		if NetworkManager.is_networked():
			_net_fire.rpc(at)
		else:
			_net_fire(at)


@rpc("authority", "call_local", "reliable")
func _net_fire(at: Vector3) -> void:
	## Dropped onto the floor of the arena rather than wherever the dragon's origin happens to
	## be, so a patch never hovers over the lip.
	_ignite(Vector3(at.x, arena_centre.y, at.z), 2.6, false)


# --- flying ----------------------------------------------------------------------------------

func is_flying() -> bool:
	return flight_state != Flight.PERCHED and flight != null


## Host: counts down to the next flight while it sits on an empty summit, and to the next breath
## of fire while it is out.
func _tick_flights(delta: float) -> void:
	if flight_state == Flight.PERCHED:
		if state != State.DORMANT or _target != null:
			return
		_flight_wait -= delta
		if _flight_wait <= 0.0:
			_flight_wait = randf_range(FLIGHT_GAP.x, FLIGHT_GAP.y)
			var seed_value := randi()
			if NetworkManager.is_networked():
				_net_take_off.rpc(seed_value)
			else:
				_net_take_off(seed_value)
		return
	if flight_state != Flight.TOUR or not flight.is_cruising(flight_distance):
		return
	_spray_wait -= delta
	if _spray_wait <= 0.0:
		_spray_wait = randf_range(SPRAY_GAP.x, SPRAY_GAP.y)
		var points := _spray_points()
		if points.is_empty():
			return
		if NetworkManager.is_networked():
			_net_spray.rpc(points)
		else:
			_net_spray(points)


## Host: where the next breath lands -- the ground under the route a little way ahead.
func _spray_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var space := get_world_3d().direct_space_state
	for index in SPRAY_PATCHES:
		var along := flight_distance + SPRAY_AHEAD + index * SPRAY_SPACING
		var above := flight.position_at(along)
		var query := PhysicsRayQueryParameters3D.create(above, above + Vector3.DOWN * 80.0)
		query.collision_mask = Combatant.LAYER_WORLD
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			points.append(hit["position"])
	return points


@rpc("authority", "call_local", "reliable")
func _net_take_off(seed_value: int) -> void:
	flight = DragonFlight.tour(seed_value, perch, get_world_3d().direct_space_state)
	flight_distance = 0.0
	flight_state = Flight.TOUR
	_spray_wait = randf_range(SPRAY_GAP.x, SPRAY_GAP.y)
	_take_to_air(true)
	GameSfx.play_at(&"wings", global_position, ROAR_REACH)


## Host: someone is on the summit -- straight home from where it is now.
func _call_home() -> void:
	if NetworkManager.is_networked():
		_net_come_home.rpc(global_position)
	else:
		_net_come_home(global_position)


@rpc("authority", "call_local", "reliable")
func _net_come_home(from: Vector3) -> void:
	flight = DragonFlight.home(from, perch, get_world_3d().direct_space_state)
	flight_distance = 0.0
	flight_state = Flight.HOME
	_take_to_air(true)


## Every peer: on, or off, the wing. In the air it collides with nothing, takes no hits and casts
## its shadow by hand.
func _take_to_air(airborne: bool) -> void:
	collision_layer = 0 if airborne else Combatant.LAYER_COMBATANT
	collision_mask = 0 if airborne else (Combatant.LAYER_WORLD | Combatant.LAYER_COMBATANT
			| Combatant.LAYER_SCENERY)
	velocity = Vector3.ZERO
	for mesh in _meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if airborne \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not airborne:
		_shadow.visible = false


func _land() -> void:
	flight_state = Flight.PERCHED
	flight = null
	flight_distance = 0.0
	_air_clip_time = -1.0
	_take_to_air(false)


## Every peer moves it along the same route at the same speed.
func _fly(delta: float) -> void:
	flight_distance += DragonFlight.SPEED * delta
	if _air_clip_time >= 0.0:
		_air_clip_time += delta
		if _air_clip_time > DragonAnimator.duration("air_breath"):
			_air_clip_time = -1.0
	if flight.is_finished(flight_distance):
		_land()
		global_position = perch
		rotation.y = perch_yaw
		return
	global_position = flight.position_at(flight_distance)
	var heading := flight.heading_at(flight_distance)
	## Settling onto the perch, it turns to face the way it always faces there.
	var wanted := atan2(-heading.x, -heading.z)
	if flight.length - flight_distance < 12.0:
		wanted = perch_yaw
	rotation.y = lerp_angle(rotation.y, wanted, minf(1.0, 3.0 * delta))


## Every peer: a breath from the air. The head curls down, the fire pours, and the patches catch
## a moment later where it lands.
@rpc("authority", "call_local", "reliable")
func _net_spray(points: PackedVector3Array) -> void:
	_air_clip_time = 0.0
	_roar()
	var land_after := 0.7
	for index in points.size():
		var at := points[index]
		var stream := FlameStream.new()
		GameWorld.effects_root(get_tree()).add_child(stream)
		get_tree().create_timer(0.55 + index * 0.08).timeout.connect(func() -> void:
			if is_instance_valid(stream):
				stream.pour(mouth_position, at, 1.4))
		get_tree().create_timer(land_after + index * 0.12).timeout.connect(func() -> void:
			if is_inside_tree():
				_ignite(at, SPRAY_RADIUS, true))


## Where the fire comes from: between the jaws.
func mouth_position() -> Vector3:
	if skeleton != null:
		var jaw := skeleton.find_bone(DragonAnimator.JAW)
		if jaw >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(jaw).origin
	return global_position + Vector3.UP * 4.0 - global_transform.basis.z * 6.0


func _roar() -> void:
	GameSfx.play_at(&"roar", mouth_position(), ROAR_REACH)


## The arena breath: a roar as it rears, then flame from the jaws down the cone as it strikes.
func _breathe_soon(strike_at: float) -> void:
	_roar()
	await get_tree().create_timer(maxf(strike_at - 0.15, 0.0)).timeout
	if not is_inside_tree() or is_dead:
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var reach: float = ATTACKS["breath"]["reach"]
	for index in 3:
		var stream := FlameStream.new()
		GameWorld.effects_root(get_tree()).add_child(stream)
		var at := global_position + forward * reach * (0.3 + 0.3 * index)
		stream.pour(mouth_position, Vector3(at.x, arena_centre.y, at.z), 2.0)


func _ignite(at: Vector3, radius: float, scenery: bool) -> void:
	var patch := FirePatch.new()
	GameWorld.effects_root(get_tree()).add_child(patch)
	patch.ignite(at, radius, Combatant.Faction.PLAYER, scenery)


## The shadow follows it over the ground, larger and fainter the higher it is.
func _place_shadow() -> void:
	if _shadow == null:
		return
	if not is_flying():
		_shadow.visible = false
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP,
			global_position + Vector3.DOWN * 80.0)
	query.collision_mask = Combatant.LAYER_WORLD
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_shadow.visible = false
		return
	var ground: Vector3 = hit["position"]
	var height := global_position.y - ground.y
	_shadow.visible = height > 1.5
	var size := 1.0 + height * 0.015
	_shadow.global_transform = Transform3D(
			Basis(Vector3.UP, rotation.y).scaled(Vector3.ONE * size), ground + Vector3.UP * 0.08)
	(( _shadow.mesh as PlaneMesh).material as ShaderMaterial).set_shader_parameter("strength",
			clampf(0.6 - height * 0.01, 0.3, 0.6))


## Untouchable on the wing: nothing could reach it up there that a dragon should notice.
func take_damage(amount: int, from_position: Vector3, knockback: float,
		knockback_lift: float) -> void:
	if is_flying():
		return
	super.take_damage(amount, from_position, knockback, knockback_lift)


# --- posing -----------------------------------------------------------------------------------

## The model's own loop underneath -- flying, walking or idling -- and the clip's offsets on top.
func _pose(_delta: float) -> void:
	if skeleton == null or poser == null:
		return
	if state != State.DEAD:
		if is_flying():
			_play(ANIM_FLY)
		elif Vector2(velocity.x, velocity.z).length() > 0.6:
			_play(ANIM_WALK)
		else:
			_play(ANIM_IDLE)
	if _clip != "":
		poser.offsets = DragonAnimator.sample(_clip, _clip_time)
	elif _air_clip_time >= 0.0:
		poser.offsets = DragonAnimator.sample("air_breath", _air_clip_time)
	else:
		poser.offsets = {}


## Skips posing entirely when nobody can see it. The dragon is visible from most of the map, so
## this is a distance check rather than a frustum one -- and a dragon in the air is always posed,
## since it is heading somewhere someone will see it.
func _worth_posing() -> bool:
	var watched := _visible_cache or is_flying()
	if animation_player != null:
		animation_player.active = watched
	return watched


func _on_died() -> void:
	state = State.DEAD
	if animation_player != null:
		animation_player.speed_scale = 0.4
	_clip = "death"
	_clip_time = 0.0
	_clip_length = DragonAnimator.duration("death")
	_pending_hit = ""
	collision_layer = 0
	defeated.emit()


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

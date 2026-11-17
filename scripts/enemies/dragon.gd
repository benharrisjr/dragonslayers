class_name Dragon
extends Combatant

## The boss on the mountain, and the win condition: kill it and the run is over.
##
## Built on the rig that tools/convert_dragon.py generates from the supplied dragon.3ds, which
## is why the bone names in DragonAnimator.DRIVEN_BONES are treated as an interface. Poses are
## evaluated straight onto the skeleton rather than through an AnimationPlayer, because the
## model ships with no clips at all -- see DragonAnimator for why that is the simpler contract.
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

const MODEL_PATH := "res://art/models/dragon.glb"

## The rig the converter produces. Swapping in a differently-authored model means matching
## these names and nothing else.
const BONES := {
	"wing_l": ["wing_l_root", "wing_l_mid", "wing_l_tip"],
	"wing_r": ["wing_r_root", "wing_r_mid", "wing_r_tip"],
	"tail": ["tail_1", "tail_2", "tail_3", "tail_4"],
	"neck": ["neck", "head"],
	"body": ["root", "hips", "spine", "chest"],
	"legs": ["leg_fl", "leg_fr", "leg_bl", "leg_br"],
}

enum State { DORMANT, ROARING, STALKING, ATTACKING, RECOVERING, DEAD }

const MAX_HEALTH := 240
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
		"damage": 3, "knockback": 15.0, "lift": 0.3, "behind": false,
	},
	"wing_flap": {
		"clip": "wing_flap", "hit_at": 0.68, "cooldown": 6.0,
		"min_range": 0.0, "max_range": 13.0, "radius": 14.0,
		"damage": 2, "knockback": 19.0, "lift": 0.55, "nova": true,
	},
	"tail_sweep": {
		"clip": "tail_sweep", "hit_at": 1.15, "cooldown": 8.5,
		"min_range": 0.0, "max_range": 18.0, "arc": 115.0, "reach": 18.0,
		"damage": 2, "knockback": 34.0, "lift": 0.45, "behind": true,
	},
	## Reaches past the far lip of the platform. On a 48 m arena a shorter cone would leave a
	## ring of ground where the dragon simply cannot answer, and the fight would become standing
	## on it and plinking.
	"breath": {
		"clip": "breath", "hit_at": 1.15, "cooldown": 7.5,
		"min_range": 7.0, "max_range": 46.0, "arc": 26.0, "reach": 44.0,
		"damage": 3, "knockback": 9.0, "lift": 0.2, "fire": true,
	},
}

var skeleton: Skeleton3D
var state: State = State.DORMANT
var enraged: bool = false
var arena_centre: Vector3 = Vector3.ZERO
var arena_radius: float = 14.0

var _bone_ids: Dictionary = {}
var _idle_time: float = 0.0
var _clip: String = ""
var _clip_time: float = 0.0
var _clip_length: float = 0.0
var _pending_hit: String = ""
var _cooldowns: Dictionary = {}
var _target: Combatant
var _empty_for: float = 0.0
var _state_timer: float = 0.0
var _abilities: Dictionary = {}
## Reused every frame instead of being rebuilt. Posing runs at 60 Hz and used to allocate a
## dictionary of twenty quaternions each time, which is churn the frame budget notices long
## before the maths does.
var _pose_scratch: Dictionary = {}
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

	var packed: PackedScene = load(MODEL_PATH)
	if packed == null:
		push_error("Dragon: %s missing -- run tools/convert_dragon.py" % MODEL_PATH)
		return
	var model := packed.instantiate() as Node3D
	add_child(model)
	skeleton = _find_skeleton(model)
	if skeleton == null:
		push_error("Dragon: converted model has no Skeleton3D")
		return
	for group: String in BONES:
		for bone_name: String in BONES[group]:
			_bone_ids[bone_name] = skeleton.find_bone(bone_name)

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
	_tick_knockback(delta)
	if not is_on_floor():
		velocity.y -= gravity() * delta
	clamp_speed()
	move_and_slide()

	_refresh_presence(delta)
	_advance_clip(delta)
	if _worth_posing():
		_pose(delta)

	if state == State.DEAD or not NetworkManager.is_host():
		return

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
			if _target != null:
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
	global_position = Vector3(arena_centre.x, global_position.y, arena_centre.z)
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
	var wanted := atan2(offset.x, offset.z)
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
	var patch := FirePatch.new()
	GameWorld.effects_root(get_tree()).add_child(patch)
	## Dropped onto the floor of the arena rather than wherever the dragon's origin happens to
	## be, so a patch never hovers over the lip.
	patch.ignite(Vector3(at.x, arena_centre.y, at.z), 2.6)


# --- posing -----------------------------------------------------------------------------------

func _pose(delta: float) -> void:
	if skeleton == null:
		return
	_idle_time += delta
	var idle := _idle_pose()
	if _clip == "":
		_apply(idle)
		return

	var clip_pose := DragonAnimator.sample(_clip, _clip_time)
	## The clip wins on the bones it names and idle breathing shows through on the rest, so an
	## attack never makes the dragon look like it stopped being alive.
	for bone: String in clip_pose:
		idle[bone] = clip_pose[bone]
	_apply(idle)


## Skips posing entirely when nobody can see it. The dragon is visible from most of the map, so
## this is a distance check rather than a frustum one.
func _worth_posing() -> bool:
	return _visible_cache


## Slow breathing sway. Small amplitudes: at 5.6 m tall, a few degrees of wing is metres of
## travel at the tip.
func _idle_pose() -> Dictionary:
	var breath := sin(_idle_time * 0.9)
	var sway := sin(_idle_time * 0.55)
	_pose_scratch.clear()
	_pose_scratch["wing_l_root"] = DragonAnimator._rot(DragonAnimator.ROLL, -(6.0 + breath * 3.5))
	_pose_scratch["wing_r_root"] = DragonAnimator._rot(DragonAnimator.ROLL, 6.0 + breath * 3.5)
	_pose_scratch["wing_l_mid"] = DragonAnimator._rot(DragonAnimator.ROLL, -breath * 3.0)
	_pose_scratch["wing_r_mid"] = DragonAnimator._rot(DragonAnimator.ROLL, breath * 3.0)
	_pose_scratch["tail_1"] = DragonAnimator._rot(DragonAnimator.YAW, sway * 6.0)
	_pose_scratch["tail_2"] = DragonAnimator._rot(DragonAnimator.YAW, sway * 7.5)
	_pose_scratch["tail_3"] = DragonAnimator._rot(DragonAnimator.YAW, sway * 9.0)
	_pose_scratch["tail_4"] = DragonAnimator._rot(DragonAnimator.YAW, sway * 10.0)
	_pose_scratch["neck"] = DragonAnimator._rot(DragonAnimator.PITCH, breath * 3.0)
	_pose_scratch["chest"] = DragonAnimator._rot(DragonAnimator.PITCH, breath * 1.2)
	return _pose_scratch


func _apply(pose: Dictionary) -> void:
	for bone: String in pose:
		var id: int = _bone_ids.get(bone, -1)
		if id >= 0:
			skeleton.set_bone_pose_rotation(id, pose[bone])


func _on_died() -> void:
	state = State.DEAD
	_clip = "death"
	_clip_time = 0.0
	_clip_length = DragonAnimator.duration("death")
	_pending_hit = ""
	collision_layer = 0
	defeated.emit()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

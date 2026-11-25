class_name DayNight
extends Node3D

## The time of day. A day is twenty-four minutes: the sun goes round the world in a circle, twelve
## minutes above the horizon and twelve below, with the moon opposite it. The sky, the haze and the
## ambient light follow; at night it is dim and blue but never black, the torches along the paths
## burn, and a hero carrying a lantern lights the ground round them.
##
## The host keeps the time: it is saved with the world, sent to anyone joining, and sent round now
## and then so no machine drifts. Underground there is no day: each dungeon is lit by a light of its
## own that only it can see (DUNGEON_LAYER).

const DAY := 1440.0
## Where in the day a new world starts: a little after sunrise. 0 is sunrise, 0.25 noon, 0.5 sunset.
const MORNING := 0.06
## How high the sun stands at noon.
const NOON_HEIGHT := deg_to_rad(62.0)
## Which way the sun rises.
const EAST := Vector3(0.79, 0.0, 0.61)
const SYNC_EVERY := 20.0
## Lights kept for the torches nearest the players, and how far one throws.
const TORCH_LIGHTS := 12
const TORCH_REACH := 11.0
const TORCH_COLOR := Color(1.0, 0.66, 0.32)
const LANTERN_REACH := 13.0
## The render layer everything underground is on: dungeon light sees only it, the sun never does.
const DUNGEON_LAYER := 1 << 17

## `--time=0.75`: every match starts then; `--freeze-time` keeps it there.
static var forced := -1.0
static var frozen := false

var time := MORNING
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment

var _sky: ProceduralSkyMaterial
var _dungeon_light: DirectionalLight3D
var _lights: Array[OmniLight3D] = []
var _lanterns := {}
var _underground := {}
var _slow := 0.0
var _sync := SYNC_EVERY
var _sky_at := -1.0
var _flicker := 0.0
var _torches_lit := -1


## The way to the sun at a time of day: a circle round the world, rising in the east, tipped so that
## noon is NOON_HEIGHT up. Above the horizon for exactly half of it.
static func sun_direction(at: float) -> Vector3:
	var south := Vector3.UP.cross(EAST).normalized()
	var top := Vector3.UP * sin(NOON_HEIGHT) + south * cos(NOON_HEIGHT)
	return (EAST.normalized() * cos(at * TAU) + top * sin(at * TAU)).normalized()


## 1 in full day, 0 at night, easing through dawn and dusk.
static func daylight(at: float) -> float:
	return smoothstep(-0.1, 0.22, sin(at * TAU))


func setup(world_environment: Environment, sky: ProceduralSkyMaterial) -> void:
	name = "DayNight"
	environment = world_environment
	_sky = sky
	if forced >= 0.0:
		time = fposmod(forced, 1.0)
	elif NetworkManager.is_host() and GameState.world != null:
		time = GameState.world.time_of_day
	sun = _directional("Sun", Color(1.0, 0.96, 0.88))
	moon = _directional("Moon", Color(0.62, 0.74, 1.0))
	_dungeon_light = _directional("DungeonLight", Color(1.0, 0.96, 0.88))
	_dungeon_light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	_dungeon_light.light_energy = 1.15
	_dungeon_light.light_cull_mask = DUNGEON_LAYER
	_dungeon_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_dungeon_light.visible = false
	for i in TORCH_LIGHTS:
		var light := OmniLight3D.new()
		light.light_color = TORCH_COLOR
		light.omni_range = TORCH_REACH
		light.omni_attenuation = 1.2
		light.visible = false
		light.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(light)
		_lights.append(light)


## Once the world is built: what is underground is moved to the layer only its light sees.
func settle() -> void:
	for dungeon in Dungeon.all(get_tree()):
		_put_underground(dungeon, true)
	get_tree().node_added.connect(_on_node_added)
	_apply(true)


func _on_node_added(node: Node) -> void:
	if not node is VisualInstance3D:
		return
	var at := node.get_parent()
	while at != null:
		if at is Dungeon or (at is Combatant and _underground.get(at.get_instance_id(), false)):
			(node as VisualInstance3D).layers = DUNGEON_LAYER
			return
		at = at.get_parent()


func _put_underground(node: Node, on: bool) -> void:
	if node is VisualInstance3D and not node is Light3D:
		var visual := node as VisualInstance3D
		if visual.layers == 1 or visual.layers == DUNGEON_LAYER:
			visual.layers = DUNGEON_LAYER if on else 1
	for child in node.get_children():
		_put_underground(child, on)


func _directional(light_name: String, color: Color) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = light_name
	light.light_color = color
	light.light_cull_mask = 0xFFFFF & ~DUNGEON_LAYER
	light.shadow_enabled = true
	## Shadows only near the action. The default 100 m covers most of the visible map from a
	## hilltop, and rendering the whole thing into the shadow atlas costs far more than the
	## distant shadows are worth at this art scale.
	light.directional_shadow_max_distance = 70.0
	## Two cascades: the near one, where the players are, gets half the shadow map to itself,
	## so shadows under feet and trees are crisp instead of blocky.
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.directional_shadow_split_1 = 0.25
	light.directional_shadow_blend_splits = true
	## Pushed off the surfaces casting them. At the defaults the trees' cones shadowed
	## themselves in fine stripes ("acne") across their lit sides.
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 2.5
	light.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(light)
	return light


func _process(delta: float) -> void:
	if not frozen and GameState.phase == GameState.Phase.PLAYING:
		time = fposmod(time + delta / DAY, 1.0)
	_flicker += delta
	_slow -= delta
	var slow := _slow <= 0.0
	if slow:
		_slow = 0.25
	_apply(slow)
	if NetworkManager.is_networked() and NetworkManager.is_host():
		_sync -= delta
		if _sync <= 0.0:
			_sync = SYNC_EVERY
			_net_time.rpc(time)


@rpc("authority", "call_remote", "reliable")
func _net_time(at: float) -> void:
	time = at


func _apply(slow: bool) -> void:
	var day := daylight(time)
	var direction := sun_direction(time)
	_aim(sun, direction)
	_aim(moon, -direction)
	var height := direction.y
	## Each fades out on the way to the horizon, so neither snaps off or drags shadows for miles.
	sun.light_energy = 1.15 * smoothstep(0.0, 0.2, height)
	var low := 1.0 - smoothstep(0.05, 0.45, height)
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.62, 0.34), low)
	moon.light_energy = 0.3 * smoothstep(0.0, 0.2, -height)
	sun.visible = height > 0.0
	moon.visible = height < 0.0
	var dusk := clampf(1.0 - absf(height - 0.06) / 0.24, 0.0, 1.0)
	environment.ambient_light_color = Color(0.3, 0.38, 0.66).lerp(Color(0.64, 0.74, 0.86), day)
	environment.ambient_light_energy = lerpf(0.36, 0.52, day)
	var haze := Color(0.07, 0.1, 0.2).lerp(Color(0.72, 0.8, 0.88), day)
	environment.fog_light_color = haze.lerp(Color(0.95, 0.6, 0.42), dusk * 0.5)
	## The sky is drawn again only as it visibly changes.
	if absf(time - _sky_at) > 0.0007:
		_sky_at = time
		_sky.sky_top_color = Color(0.03, 0.05, 0.14).lerp(Color(0.35, 0.55, 0.85), day)
		var horizon := Color(0.1, 0.14, 0.27).lerp(Color(0.72, 0.82, 0.9), day)
		_sky.sky_horizon_color = horizon.lerp(Color(1.0, 0.56, 0.32), dusk * 0.75)
		_sky.ground_bottom_color = Color(0.03, 0.04, 0.08).lerp(Color(0.28, 0.3, 0.28), day)
		_sky.ground_horizon_color = Color(0.08, 0.11, 0.2).lerp(Color(0.6, 0.62, 0.55), day)
	_light_torches(1.0 - day, slow)
	_light_lanterns(1.0 - day, slow)
	if slow:
		_watch_the_depths()


func _aim(light: DirectionalLight3D, towards: Vector3) -> void:
	light.basis = Basis.looking_at(-towards, Vector3.UP if absf(towards.y) < 0.99 else Vector3.RIGHT)


func _light_torches(night: float, slow: bool) -> void:
	var burning := night > 0.3
	if int(burning) != _torches_lit:
		_torches_lit = int(burning)
		for torch in get_tree().get_nodes_in_group(Torch.GROUP):
			(torch as Torch).set_lit(burning)
	if slow:
		_place_torch_lights(burning)
	for i in _lights.size():
		var waver := 1.0 + 0.1 * sin(_flicker * 9.0 + i * 2.4) + 0.06 * sin(_flicker * 23.0 + i)
		_lights[i].light_energy = 2.2 * smoothstep(0.3, 0.8, night) * waver


## The torches nearest any player on this machine, each with one of the lights.
func _place_torch_lights(burning: bool) -> void:
	var near: Array = []
	if burning:
		for torch: Node3D in get_tree().get_nodes_in_group(Torch.GROUP):
			var gap := INF
			for pid in PlayerRegistry.local_pids():
				var body := PlayerRegistry.body_of(pid) as Node3D
				if body != null:
					gap = minf(gap, body.global_position.distance_squared_to(torch.global_position))
			if gap < 70.0 * 70.0:
				near.append([gap, torch])
		near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	## A light stays with its torch while that is still among the nearest, so none jump about.
	var wanted: Array = []
	for entry: Array in near.slice(0, TORCH_LIGHTS):
		wanted.append((entry[1] as Torch).flame_position())
	var free: Array[OmniLight3D] = []
	for light in _lights:
		var kept := -1
		for i in wanted.size():
			if light.visible and light.global_position.distance_squared_to(wanted[i]) < 0.01:
				kept = i
		if kept >= 0:
			wanted.remove_at(kept)
		else:
			light.visible = false
			free.append(light)
	for at: Vector3 in wanted:
		var light: OmniLight3D = free.pop_back()
		light.global_position = at
		light.visible = true


## A hero with a lantern carries its light: after dark, and always underground.
func _light_lanterns(night: float, slow: bool) -> void:
	if slow:
		var carrying := {}
		for body in PlayerRegistry.living_bodies():
			var hero := body as PlayerCharacter
			if hero == null or not hero.has_item(ItemDB.LANTERN):
				continue
			carrying[hero.get_instance_id()] = true
			if not _lanterns.has(hero.get_instance_id()):
				var light := OmniLight3D.new()
				light.name = "LanternLight"
				light.light_color = Color(1.0, 0.78, 0.46)
				light.omni_range = LANTERN_REACH
				light.omni_attenuation = 1.1
				light.position = Vector3(0.0, 2.3, 0.0)
				hero.add_child(light)
				_lanterns[hero.get_instance_id()] = light
		for id: int in _lanterns.keys():
			if carrying.has(id):
				continue
			if is_instance_valid(_lanterns[id]):
				(_lanterns[id] as Node).queue_free()
			_lanterns.erase(id)
	for id: int in _lanterns:
		var light := _lanterns[id] as OmniLight3D if is_instance_valid(_lanterns[id]) else null
		if light == null:
			continue
		var dark := 0.35 if _underground.get(id, false) else smoothstep(0.25, 0.8, night)
		light.visible = dark > 0.01
		light.light_energy = 2.6 * dark * (1.0 + 0.05 * sin(_flicker * 7.0 + id % 10))


## Heroes going down into a dungeon, or coming back, change to the light of where they are.
func _watch_the_depths() -> void:
	var anyone := false
	for pid: int in PlayerRegistry.bodies:
		var body := PlayerRegistry.body_of(pid) as Node3D
		if body == null:
			continue
		var below := Dungeon.containing(get_tree(), body.global_position) != null
		anyone = anyone or below
		if below != _underground.get(body.get_instance_id(), false):
			_underground[body.get_instance_id()] = below
			_put_underground(body, below)
	_dungeon_light.visible = anyone

class_name DebugCapture
extends Node

## Renders the running game for a moment and writes a PNG, so a change can be checked visually
## without a person watching the window.
##
##   Godot --path . -- --solo --slots=2 --capture=/tmp/shot.png --capture-delay=6
##
## Needs a real window: headless has no renderer, so the captured image would be blank.

var path: String = "user://capture.png"
var delay: float = 5.0
var follow_up: int = 0
## `--capture-overview`: photograph the whole map from above instead of through a player's pane.
## The way to see the shape of the world -- tiers, ramps, coast -- in one picture.
var overview: bool = false
## `--capture-overview=mountain`: just the mountain, from closer, to see its terraces and ramps.
var overview_focus: String = ""
## `--capture-overview --capture-annotate`: the whole map straight down, flat (orthographic),
## with the chunk borders ruled over it and a labelled marker at every dungeon's way in.
var annotate: bool = false
## `--capture-gear`: hand every local player the full set of gear and open the first one's gear
## panel before the photograph, to check the panel and the hotkey row without playing to them.
var wheel: bool = false
var gear: bool = false
## `--capture-map`: open the overhead map (the M key) before the photograph.
var map: bool = false
## `--capture-shop`: hand the first player a few bugs and open the shop's list.
var shop: bool = false
## With `--capture-shop=look`: stand in front of the stall instead of opening its list.
var look_only: bool = false
## `--capture-rock`: give the first player a power glove, stand them by the nearest rock, lift
## it, and throw it a moment before the photograph so the pieces are in the air.
var rock: bool = false
## `--capture-lobby` (without --solo): open the character select with four seats filled --
## different heroes, two of them locked in -- to check the cards and the 3D previews.
var lobby: bool = false
## `--capture-lobby=worlds`: the world page instead. Either way, the most recently played saved
## world (if there is one) is the one the seats are filled for, so their cards show its heroes.
var lobby_view: String = ""
## `--capture-walk`: walk the first player in a curve for the last few seconds before the
## photograph, swinging twice on the way -- to see tracks in the snow and grass bending and
## being cut.
var walk: bool = false
## `--capture-armor=N`: every local player at armour level N, stood in a row facing the first
## player's camera, to compare the dyed clothes.
var armor: int = -1
## `--capture-dragon=<clip>@<seconds>`: stand the first player in front of the dragon and hold it
## in one of its attack poses (claw, breath, tail_sweep, wing_flap, roar, death, rest).
## `--capture-dragon=fly@<seconds>`: send it on a flight, stand the player under the route a
## little ahead of it, and photograph it that many seconds into the flight, breathing fire.
var dragon_view: String = ""
## `--capture-charge=aura`: line the local players up fully charged. `=release`: line them up
## and let every charged attack go a moment before the photograph.
var charge_view: String = ""
## `--capture-raft`: hand the first player a raft and put them on the river, drifting.
var raft: bool = false
## `--capture-dropin`: two seconds before the photograph someone joins on a spare controller,
## to see the screen split again around them.
var drop_in: bool = false
var _dropped: bool = false
var _rafted: bool = false
var _charge_released: bool = false
var _dragon_started: bool = false
var _armored: bool = false
var _walk_step: int = 0
var _thrown: bool = false
var _geared: bool = false
var _rock_step: int = 0

var _elapsed: float = 0.0
var _shots: int = 0
## Set before the first await. _process keeps running while a coroutine is suspended, so
## without this every subsequent frame starts another capture and the run never ends.
var _busy: bool = false


func _process(delta: float) -> void:
	if _busy:
		return
	_elapsed += delta
	if lobby:
		lobby = false
		_fill_lobby()
	if map and _elapsed > delay - 1.0:
		map = false
		(get_parent() as Main).toggle_map()
	if shop and _elapsed > delay - 1.0:
		shop = false
		var buyer := PlayerRegistry.body_of(PlayerRegistry.local_pids()[0]) as PlayerCharacter
		buyer.bugs = 4
		buyer.add_item(ItemDB.NET)
		if look_only:
			var stall := get_tree().get_first_node_in_group("shops") as Node3D
			buyer.global_position = stall.global_position + Vector3(0.0, 0.5, 9.0)
			buyer.reset_physics_interpolation()
		else:
			buyer.set_shop_open(true)
	if rock:
		_drive_rock()
	if walk:
		_drive_walk()
	if drop_in and not _dropped and _elapsed >= delay - 2.0:
		_dropped = true
		(get_parent() as Main).drop_in(7)
	if dragon_view != "":
		_drive_dragon()
	if raft and not _rafted and _elapsed > delay - 2.5:
		_rafted = true
		var rider := PlayerRegistry.body_of(PlayerRegistry.local_pids()[0]) as PlayerCharacter
		var spot := (get_parent() as Main).world.river_landmark("river")
		if rider != null and spot != Vector3.INF:
			rider.add_item(ItemDB.RAFT)
			rider.global_position = spot + Vector3.UP * 0.6
			rider.reset_physics_interpolation()
	if charge_view != "":
		if armor < 0:
			armor = 0
		if _armored:
			for pid in PlayerRegistry.local_pids():
				var hero := PlayerRegistry.body_of(pid) as PlayerCharacter
				if hero == null:
					continue
				if charge_view == "aura":
					hero.charge_level = 1.0
				elif not _charge_released and _elapsed > delay - 0.3:
					hero.use_charged_attack()
			if charge_view == "release" and _elapsed > delay - 0.3:
				_charge_released = true
	if armor >= 0 and not _armored and _elapsed > delay - 1.5:
		_armored = true
		_line_up_armored()
	if gear and not _geared and _elapsed > delay - 1.0:
		_geared = true
		var first := true
		for pid in PlayerRegistry.local_pids():
			var player := PlayerRegistry.body_of(pid) as PlayerCharacter
			if player == null:
				continue
			for item in ItemDB.ORDER:
				player.add_item(item)
			if first:
				if wheel:
					player.remove_item(ItemDB.FAN)
					player.set_wheel_open(true)
					player.point_wheel(Vector2(1.0, 0.2))
				else:
					player.set_inventory_open(true)
				first = false
	if _elapsed < delay:
		return
	_busy = true
	if overview and _shots == 0:
		_frame_whole_map()
		await get_tree().process_frame
		await get_tree().process_frame
	print("capture: window %s, canvas %s, visible rect %s" % [DisplayServer.window_get_size(),
			get_window().content_scale_size, get_viewport().get_visible_rect().size])
	var main := get_parent() as Main
	if main != null and main.split_screen != null:
		for pane in main.split_screen.panes:
			var viewport := pane.get_child(0) as SubViewport
			print("capture: pane %s renders 3D at %dx%d, msaa %d" % [pane.name, viewport.size.x,
					viewport.size.y, viewport.msaa_3d])
	## One frame has to be fully drawn before the texture holds anything.
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var target := path if _shots == 0 else path.get_basename() + "_%d.png" % _shots
	image.save_png(target)
	print("capture -> %s (%dx%d)" % [target, image.get_width(), image.get_height()])

	_shots += 1
	if _shots > follow_up:
		get_tree().quit()
		return
	_elapsed = 0.0
	delay = 2.0
	_busy = false


func _drive_rock() -> void:
	var thrower := PlayerRegistry.body_of(PlayerRegistry.local_pids()[0]) as PlayerCharacter
	if thrower == null:
		return
	if _rock_step == 0 and _elapsed > delay - 3.0:
		_rock_step = 1
		thrower.add_item(ItemDB.GLOVE)
		var nearest := Vector3.ZERO
		var best := INF
		for node in get_tree().get_nodes_in_group("chunks"):
			for at in (node as Chunk).liftable_props():
				if at.distance_to(thrower.global_position) < best:
					best = at.distance_to(thrower.global_position)
					nearest = at
		thrower.global_position = nearest + Vector3(0.0, 0.5, 2.6)
		thrower.rotation.y = PI
		thrower.reset_physics_interpolation()
	elif _rock_step == 1 and _elapsed > delay - 2.2:
		_rock_step = 2
		print("capture: lift -> %s" % thrower.lift_rock())
	elif _rock_step == 2 and _elapsed > delay - 0.9 and follow_up == 0:
		_rock_step = 3
		print("capture: throw -> %s" % thrower.throw_rock())


## Hides the split-screen panes and looks down on the map from a camera in the window itself.
## The panes are SubViewports sharing the window's world, so the terrain is already there to see.
func _frame_whole_map() -> void:
	for node in get_parent().get_children():
		if node is SplitScreen:
			(node as SplitScreen).visible = false
	var centre := WorldGenerator.map_centre()
	var offset := Vector3(0.0, 520.0, 330.0)
	var world := (get_parent() as Main).world
	if world != null:
		world.draw_all = true
	var focus := world.chunk_of_biome(StringName(overview_focus)) if not overview_focus.is_empty() \
			and world != null else null
	if focus != null:
		centre = focus.global_position + Vector3(WorldGenerator.CHUNK_SIZE * 0.5,
				ChunkMesher.height_to_world(WorldGenerator.summit_level()) - 8.0,
				WorldGenerator.CHUNK_SIZE * 0.5)
		## Far enough out to take in the terraces where they spill into the chunks round it.
		offset = Vector3(0.0, 210.0, 120.0)
	var camera := Camera3D.new()
	camera.far = 3000.0
	camera.fov = 50.0
	get_parent().add_child(camera)
	if annotate and focus == null:
		var span := WorldGenerator.GRID * WorldGenerator.CHUNK_SIZE
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = span * 1.04
		camera.look_at_from_position(centre + Vector3(0.0, 600.0, 0.001), centre, Vector3.FORWARD)
		_annotate(world)
	else:
		camera.look_at_from_position(centre + offset, centre, Vector3.UP)
	camera.current = true


## The chunk borders, ruled in white over everything, and a marker at each dungeon's way in: a
## pillar in its shrine's colour with its name over it.
func _annotate(world: GameWorld) -> void:
	var root := Node3D.new()
	root.name = "Annotations"
	get_parent().add_child(root)
	var span := WorldGenerator.GRID * WorldGenerator.CHUNK_SIZE
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in WorldGenerator.GRID + 1:
		for along_x in [true, false]:
			var bar := BoxMesh.new()
			bar.size = Vector3(span, 0.5, 1.6) if along_x else Vector3(1.6, 0.5, span)
			bar.material = line_material
			var line := MeshInstance3D.new()
			line.mesh = bar
			var at := i * WorldGenerator.CHUNK_SIZE
			line.position = Vector3(span * 0.5, 200.0, at) if along_x else Vector3(at, 200.0, span * 0.5)
			root.add_child(line)
	if world == null:
		return
	for entrance in DungeonEntrance.all(get_tree()):
		var id := entrance.dungeon_id
		var colour := MountainShrine.color_for(id)
		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color = colour
		marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var ring := CylinderMesh.new()
		ring.top_radius = 6.0
		ring.bottom_radius = 6.0
		ring.height = 1.0
		ring.material = marker_material
		var marker := MeshInstance3D.new()
		marker.mesh = ring
		marker.position = Vector3(entrance.global_position.x, 210.0, entrance.global_position.z)
		root.add_child(marker)
		var dungeon := Dungeon.by_id(get_tree(), id)
		var label := Label3D.new()
		label.text = dungeon.display_name if dungeon != null else String(id)
		label.font_size = 96
		label.outline_size = 24
		label.pixel_size = 0.08
		label.modulate = Color.WHITE
		label.outline_modulate = Color(0.05, 0.05, 0.08)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = marker.position + Vector3(0.0, 5.0, -11.0)
		root.add_child(label)


func _fill_lobby() -> void:
	var screen := (get_parent() as Main).lobby
	screen._choose_mode("offline")
	if lobby_view == "worlds":
		return
	var saved := SaveManager.list_worlds()
	screen._choose_world(saved[0].id if not saved.is_empty() else LobbyScreen.NEW_WORLD)
	## Seats open to input after a short delay; these are not input, so they go straight in.
	var picks: Array[StringName] = [&"knight", &"mage", &"archer", &"barbarian"]
	var devices: Array[int] = [PlayerBindings.KEYBOARD, 0, 1, 2]
	for seat in devices.size():
		screen.claim_seat(devices[seat])
		while screen.heroes()[seat] != picks[seat]:
			screen.step_hero(devices[seat], 1)
	screen.set_ready(devices[0], true)
	screen.set_ready(devices[2], true)


func _drive_walk() -> void:
	var start := delay - 3.2
	if _walk_step == 0 and _elapsed >= start:
		## A knock first, so the hearts show a half.
		var hero := PlayerRegistry.body_of(PlayerRegistry.local_pids()[0]) as PlayerCharacter
		if hero != null and hero.health == hero.max_health:
			hero.take_damage(1, hero.global_position + Vector3.FORWARD, 0.0, 0.0)
			## In the fall, start beside the nearest leaf pile so the walk goes through it.
			## In summer, beside the nearest long grass, to mow and push through it.
			var pile := _nearest_pile(hero.global_position)
			if pile == Vector3.INF:
				pile = _nearest_grass(hero.global_position)
			if pile != Vector3.INF:
				hero.global_position = pile + Vector3(-2.2, 1.0, 0.6)
				hero.reset_physics_interpolation()
	var plan: Array = [[start, "p0_right", true], [start + 1.0, "p0_up", true],
			[start + 1.2, "p0_item_1", true], [start + 1.3, "p0_item_1", false],
			[start + 1.7, "p0_right", false], [start + 2.0, "p0_item_1", true],
			[start + 2.1, "p0_item_1", false], [start + 2.5, "p0_up", false]]
	if _walk_step == plan.size() and _elapsed >= start + 2.7 and not _thrown:
		## And a boomerang in the air for the photograph.
		_thrown = true
		var thrower := PlayerRegistry.body_of(PlayerRegistry.local_pids()[0]) as PlayerCharacter
		if thrower != null:
			thrower.add_item(ItemDB.BOOMERANG)
			thrower.throw_boomerang()
	while _walk_step < plan.size() and _elapsed >= float(plan[_walk_step][0]):
		var step: Array = plan[_walk_step]
		if step[2]:
			Input.action_press(step[1])
		else:
			Input.action_release(step[1])
		_walk_step += 1


## The middle of the nearest thick patch of long grass: a tuft with plenty more around it.
func _nearest_grass(from: Vector3) -> Vector3:
	var best := Vector3.INF
	for node in get_tree().get_nodes_in_group(GrassField.GROUP):
		var field := node as GrassField
		for block in field._blocks:
			var roots: PackedVector3Array = block["roots"]
			for index in range(0, roots.size(), 25):
				var at := field.global_position + roots[index]
				var around := 0
				for other in roots:
					if other.distance_squared_to(roots[index]) < 9.0:
						around += 1
				if around >= 40 and (best == Vector3.INF
						or at.distance_to(from) < best.distance_to(from)):
					best = at
	return best


func _nearest_pile(from: Vector3) -> Vector3:
	var best := Vector3.INF
	for node in get_tree().get_nodes_in_group(LeafField.GROUP):
		var field := node as LeafField
		for block in field._blocks:
			var positions: PackedVector3Array = block["positions"]
			var floors: PackedFloat32Array = block["floor"]
			for index in positions.size():
				if positions[index].y - floors[index] < 0.45:
					continue
				var at := field.global_position + Vector3(positions[index].x, floors[index],
						positions[index].z)
				if best == Vector3.INF or at.distance_to(from) < best.distance_to(from):
					best = at
	return best


func _line_up_armored() -> void:
	var pids := PlayerRegistry.local_pids()
	var first := PlayerRegistry.body_of(pids[0]) as PlayerCharacter
	if first == null:
		return
	var camera := (get_parent() as Main).split_screen.cameras[0] as PlayerCamera
	var right := Basis(Vector3.UP, camera.yaw) * Vector3.RIGHT
	var toward := Basis(Vector3.UP, camera.yaw) * Vector3.BACK
	var start := first.global_position
	for index in pids.size():
		var hero := PlayerRegistry.body_of(pids[index]) as PlayerCharacter
		if hero == null:
			continue
		hero.set_armor_level(armor)
		hero.global_position = start + right * (index - (pids.size() - 1) * 0.5) * 1.5
		hero.rotation.y = atan2(toward.x, toward.z)
		hero.reset_physics_interpolation()


func _drive_dragon() -> void:
	var main := get_parent() as Main
	if main.world == null or main.world.dragon == null or PlayerRegistry.local_pids().is_empty():
		return
	var dragon := main.world.dragon
	var hero := PlayerRegistry.body_of(PlayerRegistry.local_pids()[0]) as PlayerCharacter
	if hero == null:
		return
	var parts := dragon_view.split("@")
	var what := parts[0]
	var at := float(parts[1]) if parts.size() > 1 else 1.0
	var camera := main.split_screen.cameras[0] as PlayerCamera
	if what == "fly":
		if not _dragon_started and _elapsed > 1.0:
			_dragon_started = true
			dragon._net_take_off(4242)
			## Photographed `at` seconds in.
			delay = _elapsed + at
		if not dragon.is_flying():
			return
		## The player stands under the route ahead of it, looking back along it.
		var ahead := dragon.flight.position_at(dragon.flight_distance + 34.0)
		var space := dragon.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 80.0)
		query.collision_mask = Combatant.LAYER_WORLD
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			hero.global_position = (hit["position"] as Vector3) + Vector3.UP * 0.2
			hero.velocity = Vector3.ZERO
		var back := dragon.global_position - hero.global_position
		camera.yaw = atan2(-back.x, -back.z)
		camera.pitch_offset = -20.0
		if _elapsed > delay - 1.6 and dragon._air_clip_time < 0.0 and not _thrown:
			_thrown = true
			dragon._net_spray(dragon._spray_points())
			print("capture: dragon at %s, player at %s, playing %s" % [dragon.global_position,
					hero.global_position, dragon.animation_player.current_animation])
		return
	## A pose: frozen, with the player standing off its nose. "air_breath" and "flying" show the
	## flying loop, lifted a few metres so the wings clear the ground.
	dragon.set_physics_process(false)
	if what == "flying" or what == "air_breath":
		dragon._clip = ""
		dragon._air_clip_time = at if what == "air_breath" else -1.0
		dragon._play(Dragon.ANIM_FLY, 0.0)
		dragon.poser.offsets = DragonAnimator.sample("air_breath", at) if what == "air_breath" else {}
		dragon._model.position.y = 6.0
	else:
		dragon._clip = "" if what == "rest" else what
		dragon._clip_time = at
		dragon._pose(0.0)
	var forward := -dragon.global_transform.basis.z
	hero.global_position = dragon.global_position + forward * 16.0 + Vector3.RIGHT * 6.0
	hero.velocity = Vector3.ZERO
	var look := dragon.global_position - hero.global_position
	camera.yaw = atan2(-look.x, -look.z)

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
	var camera := Camera3D.new()
	camera.far = 3000.0
	camera.fov = 50.0
	get_parent().add_child(camera)
	camera.look_at_from_position(centre + Vector3(0.0, 520.0, 330.0), centre, Vector3.UP)
	camera.current = true

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
var gear: bool = false
var _geared: bool = false

var _elapsed: float = 0.0
var _shots: int = 0
## Set before the first await. _process keeps running while a coroutine is suspended, so
## without this every subsequent frame starts another capture and the run never ends.
var _busy: bool = false


func _process(delta: float) -> void:
	if _busy:
		return
	_elapsed += delta
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
				player.set_inventory_open(true)
				first = false
	if _elapsed < delay:
		return
	_busy = true
	if overview and _shots == 0:
		_frame_whole_map()
		await get_tree().process_frame
		await get_tree().process_frame
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

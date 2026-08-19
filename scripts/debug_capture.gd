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

var _elapsed: float = 0.0
var _shots: int = 0
## Set before the first await. _process keeps running while a coroutine is suspended, so
## without this every subsequent frame starts another capture and the run never ends.
var _busy: bool = false


func _process(delta: float) -> void:
	if _busy:
		return
	_elapsed += delta
	if _elapsed < delay:
		return
	_busy = true
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

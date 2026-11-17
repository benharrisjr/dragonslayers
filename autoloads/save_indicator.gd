extends Node

## A blinking floppy disk in the bottom-right corner whenever a save file hits
## the disk (SaveManager.save_written: slot saves and the global config). Writes are synchronous and take milliseconds, so the icon holds
## for SHOW_SECONDS after the latest save; back-to-back saves extend it.
##
## Its own CanvasLayer above the transition curtains (101)
## so it reads through scene fades, below the bug-report button/form (109/110).

const LAYER := 103
const ICON := preload("res://art/icons/individual_32x32/icon019.png")
## The 32 px pixel-art icon is drawn at this multiple.
const ICON_SCALE := 2
const MARGIN := 8
const SHOW_SECONDS := 1.5
## One half of a blink (bright → dim or back).
const BLINK_HALF := 0.25
const DIM_ALPHA := 0.2
const FADE_OUT := 0.2

var _icon: TextureRect = null
var _blink: Tween = null
var _remaining: float = 0.0
## The looping blink is running (vs idle or fading out).
var _blinking: bool = false


func _ready() -> void:
	# Modals may pause the tree; the blink must keep going under them.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	# Tests and the run simulator save constantly with nothing on screen.
	if DisplayServer.get_name() == "headless":
		return
	call_deferred("_setup")


func _setup() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = LAYER
	get_tree().root.add_child(canvas)

	var side := float(ICON.get_width() * ICON_SCALE)
	_icon = TextureRect.new()
	_icon.texture = ICON
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_icon.offset_left = -MARGIN - side
	_icon.offset_right = -MARGIN
	_place_vertically()
	_icon.visible = false
	canvas.add_child(_icon)

	SaveManager.save_written.connect(_on_save_written)


func _on_save_written() -> void:
	if _icon == null:
		return
	_remaining = SHOW_SECONDS
	set_process(true)
	_place_vertically()
	if _blinking:
		return
	_kill_blink()
	_blinking = true
	_icon.visible = true
	_icon.modulate.a = 1.0
	_blink = create_tween().set_loops()
	_blink.tween_property(_icon, "modulate:a", DIM_ALPHA, BLINK_HALF) \
			.set_trans(Tween.TRANS_SINE)
	_blink.tween_property(_icon, "modulate:a", 1.0, BLINK_HALF) \
			.set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0:
		return
	set_process(false)
	_kill_blink()
	_blinking = false
	_blink = create_tween()
	_blink.tween_property(_icon, "modulate:a", 0.0, FADE_OUT)
	_blink.tween_callback(func() -> void: _icon.visible = false)


## Bottom-right corner. Raise `bottom` here if the game's HUD uses that corner.
func _place_vertically() -> void:
	var side := float(ICON.get_height() * ICON_SCALE)
	var bottom := float(MARGIN)
	_icon.offset_bottom = -bottom
	_icon.offset_top = -bottom - side


func _kill_blink() -> void:
	if _blink != null:
		_blink.kill()
		_blink = null

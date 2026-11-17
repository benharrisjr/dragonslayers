class_name IconButton extends Button

## Clickable grid cell whose only chrome is an IconPanel frame: the Button has
## empty StyleBoxes for every state, so the IconPanel frame is what the player
## sees. Hover/focus/press feedback is drawn by tinting the frame rather than
## by a StyleBox border, keeping the cell shape identical to a plain IconPanel.

const _HOVER_TINT := Color(1.35, 1.35, 1.35)
const _PRESSED_TINT := Color(0.70, 0.70, 0.70)

var panel: IconPanel = null
## The frame's resting colour (a rarity tint, a "selected" gold). Hover and
## press shade it rather than replacing it, so the colour survives a mouse-over.
var base_frame_tint: Color = Color.WHITE:
	set(v):
		base_frame_tint = v
		_refresh_frame_tint()


static func make(icon_tex: Texture2D, size: Vector2i = Vector2i(60, 60), frame_tex: Texture2D = null) -> IconButton:
	var btn := IconButton.new()
	btn.custom_minimum_size = Vector2(size)
	btn.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	btn.panel = IconPanel.make(icon_tex, size, frame_tex)
	btn.panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_child(btn.panel)

	btn.mouse_entered.connect(btn._refresh_frame_tint)
	btn.mouse_exited.connect(btn._refresh_frame_tint)
	btn.focus_entered.connect(btn._refresh_frame_tint)
	btn.focus_exited.connect(btn._refresh_frame_tint)
	btn.button_down.connect(btn._refresh_frame_tint)
	btn.button_up.connect(btn._refresh_frame_tint)
	return btn


func _refresh_frame_tint() -> void:
	if not panel:
		return
	var mode := get_draw_mode()
	if mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED:
		panel.frame_tint = base_frame_tint * _PRESSED_TINT
	elif mode == DRAW_HOVER or has_focus():
		panel.frame_tint = base_frame_tint * _HOVER_TINT
	else:
		panel.frame_tint = base_frame_tint

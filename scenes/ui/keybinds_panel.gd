class_name KeybindsPanel extends ModalPanel
## Options → Keybindings: every Keybinds.REBINDABLE action with one button
## showing its current key and (with controller support) its gamepad button,
## "key / pad". How the button is pressed picks what it rebinds: a gamepad press
## listens for a pad button, a click or Enter for a key. Then press the new key /
## button (Escape, or Select on the pad, cancels); one another action already
## uses swaps between them. Reset to Defaults restores both maps.

const _BIND_BTN_SIZE := Vector2(200, 56)
## Key / pad glyphs are drawn at this multiple of their pixel-art size.
const _GLYPH_SCALE := 3
## A trigger counts as pressed for a capture past this (PadCursor's press point).
const _TRIGGER_PRESS := 0.6

## Action being rebound, or &"" when idle; _capturing_pad says which column.
var _capturing: StringName = &""
var _capturing_pad: bool = false
var _bind_buttons: Dictionary = {}  # action -> PanelButton
var _key_glyphs: Dictionary = {}    # action -> TextureRect (the key half)
var _pad_glyphs: Dictionary = {}    # action -> TextureRect (the pad half)
var _glyph_rows: Dictionary = {}    # action -> HBoxContainer holding both halves
var _has_key: Dictionary = {}       # action -> bool (false = pad-only row)
## The pad input that just finished a capture: its release (or the trigger
## settling back) is swallowed so PadCursor doesn't fire the bound action.
var _swallow_button: int = -1
var _swallow_axis: int = -1


func _init() -> void:
	z_index = 5
	drop_in = true
	panel_margin = 24
	content_separation = 14
	panel_min_size = Vector2(960, 0)


func _build_content() -> void:
	var title := Label.new()
	title.text = "Keybindings"
	FontSizes.apply(title, FontSizes.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	content.add_child(title)

	content.add_child(HSeparator.new())

	# Two label/binding column groups keep every row on screen at once.
	var per_group := 2
	# A spacer column splits the two groups so the right-hand labels don't
	# butt against the left group's last button.
	var grid := GridContainer.new()
	grid.columns = per_group * 2 + 1
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for g in 2:
		if g == 1:
			grid.add_child(_group_spacer())
		for text in ["", "Keyboard / Gamepad"]:
			var head := Label.new()
			head.text = text
			head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			FontSizes.apply(head, FontSizes.BODY)
			head.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
			grid.add_child(head)
	var shown := 0
	for entry in Keybinds.REBINDABLE:
		var action: StringName = entry["action"]
		var has_key: bool = entry.get("keyboard", true)
		if shown % 2 == 1:
			grid.add_child(_group_spacer())
		shown += 1
		var lbl := Label.new()
		lbl.text = entry["label"]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		FontSizes.apply(lbl, FontSizes.BODY_LARGE)
		grid.add_child(lbl)

		var btn := _make_bind_button(action)
		btn.pressed.connect(_on_bind_pressed.bind(action))
		# Pad-only row: its key is shown but fixed, so only a pad press does anything.
		_has_key[action] = has_key
		grid.add_child(btn)
		_bind_buttons[action] = btn

	content.add_child(HSeparator.new())

	var note := Label.new()
	note.text = "The sticks are fixed. In menus the D-pad always moves the pointer."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	FontSizes.apply(note, FontSizes.CAPTION)
	note.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	content.add_child(note)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)

	var reset_btn := PanelButton.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.custom_minimum_size = Vector2(200, 40)
	FontSizes.apply(reset_btn, FontSizes.BODY_LARGE)
	reset_btn.pressed.connect(func() -> void:
		_end_capture()
		Keybinds.reset_defaults()
		_refresh_rows())
	footer.add_child(reset_btn)

	var close_btn := PanelButton.new()
	close_btn.text = "Close"
	close_btn.texture = PanelButton.RED_TEX
	close_btn.custom_minimum_size = Vector2(130, 40)
	FontSizes.apply(close_btn, FontSizes.BODY_LARGE)
	close_btn.pressed.connect(_on_back)
	footer.add_child(close_btn)

	# Hotkeys underneath stand down while this window is up.
	visibility_changed.connect(func() -> void:
		Keybinds.suppress_hotkeys = visible
		if not visible:
			_end_capture())
	tree_exiting.connect(func() -> void: Keybinds.suppress_hotkeys = false)
	Keybinds.suppress_hotkeys = visible

	_refresh_rows()


func _group_spacer() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(24, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## One binding button: the key glyph, a slash and the pad glyph centred in it
## (just the key without controller support). The glyph row is swapped for a
## "Press ..." prompt while the button is capturing.
func _make_bind_button(action: StringName) -> PanelButton:
	var btn := PanelButton.new()
	btn.custom_minimum_size = _BIND_BTN_SIZE
	btn.button_focus_mode = Control.FOCUS_NONE
	FontSizes.apply(btn, FontSizes.BODY)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	_key_glyphs[action] = _make_glyph(row)
	var slash := Label.new()
	slash.text = "/"
	FontSizes.apply(slash, FontSizes.BODY_LARGE)
	slash.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slash)
	_pad_glyphs[action] = _make_glyph(row)
	_glyph_rows[action] = row
	return btn


func _make_glyph(row: HBoxContainer) -> TextureRect:
	var glyph := TextureRect.new()
	glyph.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glyph)
	# A glyph with no art falls back to its name in this label, next to it.
	var name_lbl := Label.new()
	FontSizes.apply(name_lbl, FontSizes.BODY)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.visible = false
	row.add_child(name_lbl)
	glyph.set_meta(&"name_label", name_lbl)
	return glyph


func _set_glyph(glyph: TextureRect, tex: Texture2D, fallback: String) -> void:
	var name_lbl: Label = glyph.get_meta(&"name_label")
	glyph.texture = tex
	glyph.visible = tex != null
	if tex:
		glyph.custom_minimum_size = tex.get_size() * _GLYPH_SCALE
	name_lbl.visible = tex == null
	name_lbl.text = fallback


func _refresh_rows() -> void:
	for action in _bind_buttons:
		var btn: PanelButton = _bind_buttons[action]
		var row: HBoxContainer = _glyph_rows[action]
		if action == _capturing:
			row.visible = false
			btn.text = "Press a button" if _capturing_pad else "Press a key"
			continue
		row.visible = true
		btn.text = ""
		var keycode := Keybinds.primary_keycode(action)
		# Always drawn here, whatever the Key Hints toggle says.
		_set_glyph(_key_glyphs[action], Keybinds.key_texture(keycode), Keybinds.key_name(keycode))
		if _pad_glyphs.has(action):
			var input := Keybinds.pad_input(action)
			_set_glyph(_pad_glyphs[action], Keybinds.pad_input_texture(input),
					Keybinds.pad_input_name(input))


## The device that pressed the button picks the half it rebinds: the pad's
## confirm (PadCursor.using_pad) listens for a pad button; a click or Enter for a
## key. A pad-only row ignores a key-side press.
func _on_bind_pressed(action: StringName) -> void:
	var pad := PadCursor.using_pad
	if not pad and not _has_key.get(action, true):
		return
	_begin_capture(action, pad)


func _begin_capture(action: StringName, pad: bool) -> void:
	_capturing = action
	_capturing_pad = pad
	_refresh_rows()


func _end_capture() -> void:
	if _capturing == &"":
		return
	_capturing = &""
	_refresh_rows()


## Capture runs in _input  ahead of PadCursor and the ui_cancel / hotkey
## handlers  so the pressed key / button never fires anything else.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _swallow_pending(event):
		get_viewport().set_input_as_handled()
		return
	if _capturing == &"":
		return
	if event is InputEventMouseButton and event.pressed:
		# Clicking anywhere else abandons the capture (another button then
		# starts its own).
		_end_capture()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_capture_key(event as InputEventKey)
	elif _capturing_pad and event is InputEventJoypadButton and event.pressed:
		_capture_pad_button(event as InputEventJoypadButton)
	elif _capturing_pad and event is InputEventJoypadMotion:
		_capture_trigger(event as InputEventJoypadMotion)


func _capture_key(key: InputEventKey) -> void:
	var keycode: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	# A key press during a pad capture only ever cancels it (Escape) or is ignored.
	if keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_end_capture()
		return
	if _capturing_pad:
		return
	get_viewport().set_input_as_handled()
	var action := _capturing
	_capturing = &""
	Keybinds.rebind(action, keycode)
	_refresh_rows()


func _capture_pad_button(jb: InputEventJoypadButton) -> void:
	get_viewport().set_input_as_handled()
	_swallow_button = jb.button_index
	if jb.button_index == JOY_BUTTON_BACK:
		_end_capture()
		return
	var input := Keybinds.pad_letter_button(jb.button_index, SaveManager.global_config.nintendo_layout)
	if not Keybinds.PAD_INPUTS.has(input):
		return  # a stick click / guide: not bindable, keep waiting
	_finish_pad_capture(input)


func _capture_trigger(jm: InputEventJoypadMotion) -> void:
	var input := Keybinds.PAD_LT if jm.axis == JOY_AXIS_TRIGGER_LEFT \
		else (Keybinds.PAD_RT if jm.axis == JOY_AXIS_TRIGGER_RIGHT else Keybinds.PAD_NONE)
	if input == Keybinds.PAD_NONE:
		return  # a stick: let it move the cursor
	get_viewport().set_input_as_handled()
	if jm.axis_value < _TRIGGER_PRESS:
		return
	_swallow_axis = jm.axis
	_finish_pad_capture(input)


func _finish_pad_capture(input: int) -> void:
	var action := _capturing
	_capturing = &""
	# Refused only when it would leave Confirm / Cancel without a button.
	Keybinds.rebind_pad(action, input)
	_refresh_rows()


## The release of the button (or the settle of the trigger) that ended a
## capture: eaten here so it can't reach PadCursor as a half-press.
func _swallow_pending(event: InputEvent) -> bool:
	if _swallow_button >= 0 and event is InputEventJoypadButton \
			and event.button_index == _swallow_button and not event.pressed:
		_swallow_button = -1
		return true
	if _swallow_axis >= 0 and event is InputEventJoypadMotion and event.axis == _swallow_axis:
		if event.axis_value <= 0.3:
			_swallow_axis = -1
		return true
	return false


func _on_back() -> void:
	if _capturing != &"":
		_end_capture()
		return
	request_close()

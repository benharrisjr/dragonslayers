class_name MainMenu
extends Control

## Host, join, or play offline, and say how many people are on this couch.
##
## The local player count is chosen here rather than detected, because "how many controllers are
## plugged in" is a bad proxy for "how many friends are sitting down", and because a solo player
## with a spare pad connected should not get a split screen.

signal start_requested(mode: String, address: String, local_slots: int)

const CHARACTER_HINT := "Slot 1 Knight  |  Slot 2 Shaman  |  Slot 3 Archer  |  Slot 4 Wizard"

var _address_field: LineEdit
var _slots_field: SpinBox
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.connection_changed.connect(_on_connection_changed)


func _build() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.08, 0.1, 0.12)
	add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.position = Vector2(-190, -180)
	column.custom_minimum_size = Vector2(380, 0)
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var title := Label.new()
	title.text = "DRAGONSLAYERS"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Four friends. Sixteen chunks. One dragon."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
	column.add_child(subtitle)

	column.add_child(HSeparator.new())

	var slots_row := HBoxContainer.new()
	var slots_label := Label.new()
	slots_label.text = "Players on this machine"
	slots_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_row.add_child(slots_label)
	_slots_field = SpinBox.new()
	_slots_field.min_value = 1
	_slots_field.max_value = PlayerRegistry.MAX_LOCAL_SLOTS
	_slots_field.value = 1
	slots_row.add_child(_slots_field)
	column.add_child(slots_row)

	var hint := Label.new()
	hint.text = CHARACTER_HINT
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.55))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	column.add_child(_button("Play solo / local co-op", func() -> void:
		start_requested.emit("offline", "", int(_slots_field.value))))
	column.add_child(_button("Host online game", func() -> void:
		start_requested.emit("host", "", int(_slots_field.value))))

	var join_row := HBoxContainer.new()
	_address_field = LineEdit.new()
	_address_field.text = "127.0.0.1"
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_address_field)
	join_row.add_child(_button("Join", func() -> void:
		start_requested.emit("join", _address_field.text, int(_slots_field.value))))
	column.add_child(join_row)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4))
	column.add_child(_status)

	var controls := Label.new()
	controls.text = "\nKeyboard: WASD move, Space jump, left click attack (clicking an enemy\n" \
		+ "also targets it), 1-4 abilities, Tab cycle target, F interact, Q/E turn camera.\n" \
		+ "Gamepads drive slots 2-4: left stick move, A jump, X attack, right stick camera."
	controls.add_theme_font_size_override("font_size", 11)
	controls.add_theme_color_override("font_color", Color(0.55, 0.6, 0.6))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(controls)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.pressed.connect(action)
	return button


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _on_join_failed(reason: String) -> void:
	set_status(reason)
	visible = true


func _on_connection_changed() -> void:
	if NetworkManager.mode == NetworkManager.Mode.HOST and visible:
		set_status("hosting on port %d -- %d player(s) connected" % [
			Transport.DEFAULT_PORT, PlayerRegistry.roster.size()])

class_name InventoryPanel
extends Control

## One player's gear panel: what they hold, and which hotkey each thing is on.
##
## It lives inside that player's own split-screen pane and is driven by that player's own
## controls, so opening it stops nobody else. The world does not pause either -- looking at
## your gear in the middle of a fight is a choice with a cost.
##
## Stick left and right moves along the items. Pressing a hotkey button puts the highlighted
## item on that button. Select closes it again.

const CELL_SIZE := Vector2(88, 92)

var player: PlayerCharacter

var _input: PlayerInput
var _selected: int = 0
var _cells: Array[Dictionary] = []
var _detail: Label
var _hint: Label


func setup(target_player: PlayerCharacter) -> void:
	player = target_player
	_input = PlayerInput.new(player.slot())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	player.inventory_toggled.connect(_on_toggled)
	player.gear_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	var step := _input.menu_step()
	if step != 0:
		_selected = posmod(_selected + step, ItemDB.ORDER.size())
		_refresh()
	for hotkey in ItemDB.HOTKEY_COUNT:
		if _input.item_pressed(hotkey):
			player.assign_hotkey(hotkey, ItemDB.ORDER[_selected])


func selected_item() -> StringName:
	return ItemDB.ORDER[_selected]


func select(id: StringName) -> void:
	var index := ItemDB.ORDER.find(id)
	if index >= 0:
		_selected = index
		_refresh()


func _on_toggled(open: bool) -> void:
	visible = open
	if open:
		_refresh()


func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.05, 0.07, 0.6)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(column)

	column.add_child(_label("Gear", 26, Color(1.0, 0.9, 0.6)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	for id in ItemDB.ORDER:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = CELL_SIZE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(frame)
		var inner := VBoxContainer.new()
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(inner)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(36, 36)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(swatch)
		var name_label := _label(ItemDB.display_name(id), 13, Color.WHITE)
		inner.add_child(name_label)
		var badge := _label("", 12, Color(1.0, 0.9, 0.6))
		inner.add_child(badge)
		_cells.append({"id": id, "frame": frame, "swatch": swatch, "name": name_label,
				"badge": badge})

	_detail = _label("", 15, Color(0.9, 0.93, 0.9))
	column.add_child(_detail)
	_hint = _label("", 12, Color(0.65, 0.7, 0.7))
	column.add_child(_hint)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _refresh() -> void:
	if player == null or _cells.is_empty():
		return
	var slot := player.slot()
	for index in _cells.size():
		var cell: Dictionary = _cells[index]
		var id: StringName = cell["id"]
		var held := player.has_item(id)
		var chosen := index == _selected
		(cell["swatch"] as ColorRect).color = ItemDB.color(id) if held else Color(0.2, 0.22, 0.25)
		(cell["name"] as Label).modulate = Color.WHITE if held else Color(1, 1, 1, 0.35)
		var badge := cell["badge"] as Label
		if not held:
			badge.text = "not found"
		elif ItemDB.is_passive(id):
			badge.text = "always on"
		else:
			var hotkey := player.hotkey_of(id)
			badge.text = PlayerBindings.hotkey_label(slot, hotkey) if hotkey >= 0 else "unassigned"
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.1, 0.12, 0.16, 0.92)
		box.set_border_width_all(3 if chosen else 1)
		box.border_color = Color(1.0, 0.9, 0.6) if chosen else Color(0.35, 0.38, 0.45)
		box.set_corner_radius_all(4)
		(cell["frame"] as PanelContainer).add_theme_stylebox_override("panel", box)

	var id := selected_item()
	var keys := "%s / %s / %s" % [PlayerBindings.hotkey_label(slot, 0),
			PlayerBindings.hotkey_label(slot, 1), PlayerBindings.hotkey_label(slot, 2)]
	if not player.has_item(id):
		_detail.text = "%s -- not found yet. Look in the large chests." % ItemDB.display_name(id)
	else:
		_detail.text = "%s -- %s" % [ItemDB.display_name(id), ItemDB.description(id)]
	if player.has_item(id) and not ItemDB.is_passive(id):
		_hint.text = "Left / right: choose    %s: put on that button    %s: close" % [
			keys, PlayerBindings.inventory_label(slot)]
	else:
		_hint.text = "Left / right: choose    %s: close" % PlayerBindings.inventory_label(slot)

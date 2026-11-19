class_name InventoryPanel
extends Control

## One player's gear panel: what they have found, and which usable is equipped.
##
## It lives inside that player's own split-screen pane and is driven by that player's own
## controls, so opening it stops nobody else. The world does not pause either -- looking at
## your gear in the middle of a fight is a choice with a cost.
##
## Two sections. Usable equipment (hookshot, lantern, power glove, bug net, fan) shares one button, so one of them is
## equipped at a time: move to it and press any action button. Static equipment (boots,
## feather) just works while it is held and has nothing to choose. The sword and shield are not
## here at all: they are always on their own buttons, and the HUD shows them.
##
## Stick left and right moves along the items, through both sections. Select closes it again.

const CELL_SIZE := Vector2(88, 100)
const GOLD := Color(1.0, 0.9, 0.6)

var player: PlayerCharacter

var _input: PlayerInput
var _selected: int = 0
## Every cell in navigation order: the usables, then the statics.
var _items: Array[StringName] = []
var _cells: Array[Dictionary] = []
var _detail: Label
var _hint: Label


func setup(target_player: PlayerCharacter) -> void:
	player = target_player
	_input = PlayerInput.new(player.slot())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_items.append_array(ItemDB.USABLE)
	_items.append_array(ItemDB.STATIC)
	_build()
	player.inventory_toggled.connect(_on_toggled)
	player.gear_changed.connect(_refresh)
	SaveManager.keybinds_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	var step := _input.menu_step()
	if step != 0:
		_selected = posmod(_selected + step, _items.size())
		_refresh()
	var pressed := _input.jump_pressed()
	for hotkey in ItemDB.HOTKEY_COUNT:
		pressed = pressed or _input.item_pressed(hotkey)
	if pressed:
		player.equip(selected_item())


func selected_item() -> StringName:
	return _items[_selected]


func select(id: StringName) -> void:
	var index := _items.find(id)
	if index >= 0:
		_selected = index
		_refresh()


func _on_toggled(open: bool) -> void:
	visible = open
	if open:
		## Open on what is equipped, so the usual visit -- swap to the other one -- is one push.
		var equipped := _items.find(player.equipped())
		_selected = equipped if equipped >= 0 else 0
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

	column.add_child(_label("Gear", 26, GOLD))

	var sections := HBoxContainer.new()
	sections.add_theme_constant_override("separation", 22)
	sections.alignment = BoxContainer.ALIGNMENT_CENTER
	sections.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(sections)
	_build_section(sections, "Usable equipment", ItemDB.USABLE)
	_build_section(sections, "Static equipment", ItemDB.STATIC)

	_detail = _label("", 15, Color(0.9, 0.93, 0.9))
	column.add_child(_detail)
	_hint = _label("", 12, Color(0.65, 0.7, 0.7))
	column.add_child(_hint)


func _build_section(parent: Control, title: String, ids: Array[StringName]) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(section)
	section.add_child(_label(title, 14, Color(0.75, 0.82, 0.9)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(row)
	for id in ids:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = CELL_SIZE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(frame)
		var inner := VBoxContainer.new()
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(inner)
		var icon := ItemIcon.new(id, 44.0)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		inner.add_child(icon)
		var name_label := _label(ItemDB.display_name(id), 12, Color.WHITE)
		inner.add_child(name_label)
		var badge := _label("", 12, GOLD)
		inner.add_child(badge)
		_cells.append({"id": id, "frame": frame, "icon": icon, "name": name_label,
				"badge": badge})


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
	var button := PlayerBindings.hotkey_label(slot, ItemDB.SLOT_USABLE)
	for index in _cells.size():
		var cell: Dictionary = _cells[index]
		var id: StringName = cell["id"]
		var held := player.has_item(id)
		var chosen := index == _selected
		var equipped := held and player.equipped() == id
		(cell["icon"] as ItemIcon).dimmed = not held
		(cell["name"] as Label).modulate = Color.WHITE if held else Color(1, 1, 1, 0.35)
		var badge := cell["badge"] as Label
		if not held:
			badge.text = "not found"
		elif ItemDB.is_usable(id):
			badge.text = "on %s" % button if equipped else ""
		else:
			badge.text = "always on"
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.16, 0.2, 0.14, 0.94) if equipped else Color(0.1, 0.12, 0.16, 0.92)
		box.set_border_width_all(3 if chosen else 1)
		box.border_color = GOLD if chosen else Color(0.35, 0.38, 0.45)
		box.set_corner_radius_all(4)
		(cell["frame"] as PanelContainer).add_theme_stylebox_override("panel", box)

	var id := selected_item()
	var close := PlayerBindings.inventory_label(slot)
	if not player.has_item(id):
		_detail.text = "%s -- not found yet. Look in the large chests." % ItemDB.display_name(id)
	else:
		_detail.text = "%s -- %s" % [ItemDB.display_name(id), ItemDB.description(id)]
	if player.has_item(id) and ItemDB.is_usable(id) and player.equipped() != id:
		var confirm := "%s / %s" % [PlayerBindings.jump_label(), button] \
				if PlayerBindings.on_pad(slot) else "Space / click"
		_hint.text = "Left / right: choose    %s: equip on %s    %s: close" % [confirm, button, close]
	else:
		_hint.text = "Left / right: choose    %s: close" % close

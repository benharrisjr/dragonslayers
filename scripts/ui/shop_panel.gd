class_name ShopPanel
extends Control

## The town shop's list, for one player: what it sells, what each thing costs in bugs, and how
## many bugs they have to spend.
##
## Built like the gear panel and for the same reasons: it lives in that player's own pane, is
## driven by their own controls, and stops nobody else. Stick left and right moves along the
## stock; jump or any attack button buys; interact (the button that opened it) closes it.

const CELL_SIZE := Vector2(88, 112)
const GOLD := Color(1.0, 0.9, 0.6)
const BUG_COLOR := Color(0.6, 0.95, 0.5)

var player: PlayerCharacter

var _input: PlayerInput
var _selected: int = 0
var _cells: Array[Dictionary] = []
var _purse: Label
var _detail: Label
var _hint: Label
## Opening the shop and buying can be the same click on a mouse, so the first frame is skipped.
var _just_opened: bool = false


func setup(target_player: PlayerCharacter) -> void:
	player = target_player
	_input = PlayerInput.new(player.slot())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	player.shop_toggled.connect(_on_toggled)
	player.gear_changed.connect(_refresh)
	player.health_changed.connect(func(_now: int, _most: int) -> void: _refresh())
	SaveManager.keybinds_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	if _just_opened:
		_just_opened = false
		return
	var step := _input.menu_step()
	if step != 0:
		_selected = posmod(_selected + step, ItemDB.SHOP_STOCK.size())
		_refresh()
	var pressed := _input.jump_pressed()
	for hotkey in ItemDB.HOTKEY_COUNT:
		pressed = pressed or _input.item_pressed(hotkey)
	if pressed:
		player.buy(selected_item())


func selected_item() -> StringName:
	return ItemDB.SHOP_STOCK[_selected]


func select(id: StringName) -> void:
	var index := ItemDB.SHOP_STOCK.find(id)
	if index >= 0:
		_selected = index
		_refresh()


func _on_toggled(open: bool) -> void:
	visible = open
	if open:
		_just_opened = true
		_refresh()


func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.06, 0.04, 0.62)
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

	column.add_child(_label("Bug Shop", 26, GOLD))
	_purse = _label("", 15, BUG_COLOR)
	column.add_child(_purse)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	for id in ItemDB.SHOP_STOCK:
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
		var price := _label("", 12, BUG_COLOR)
		inner.add_child(price)
		_cells.append({"id": id, "frame": frame, "icon": icon, "name": name_label,
				"price": price})

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
	_purse.text = "You have %d bug%s" % [player.bugs, "" if player.bugs == 1 else "s"]
	for index in _cells.size():
		var cell: Dictionary = _cells[index]
		var id: StringName = cell["id"]
		var wanted := player.can_take(id)
		var affordable := player.can_buy(id)
		var chosen := index == _selected
		(cell["icon"] as ItemIcon).dimmed = not affordable
		(cell["name"] as Label).modulate = Color.WHITE if wanted else Color(1, 1, 1, 0.4)
		var price := cell["price"] as Label
		var cost := ItemDB.price(id)
		if not wanted:
			price.text = "full" if ItemDB.is_consumable(id) else "owned"
		else:
			price.text = "free" if cost == 0 else "%d bug%s" % [cost, "" if cost == 1 else "s"]
		price.modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.45)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.14, 0.2, 0.14, 0.94) if affordable else Color(0.1, 0.12, 0.16, 0.92)
		box.set_border_width_all(3 if chosen else 1)
		box.border_color = GOLD if chosen else Color(0.35, 0.38, 0.45)
		box.set_corner_radius_all(4)
		(cell["frame"] as PanelContainer).add_theme_stylebox_override("panel", box)

	var id := selected_item()
	var slot := player.slot()
	var cost := ItemDB.price(id)
	if not player.can_take(id):
		_detail.text = "%s -- you have no use for another." % ItemDB.display_name(id)
	elif player.bugs < cost:
		_detail.text = "%s -- %s  (%d more bug%s needed)" % [ItemDB.display_name(id),
				ItemDB.description(id), cost - player.bugs, "" if cost - player.bugs == 1 else "s"]
	else:
		_detail.text = "%s -- %s" % [ItemDB.display_name(id), ItemDB.description(id)]
	var on_pad := PlayerBindings.on_pad(slot)
	var confirm := PlayerBindings.jump_label() if on_pad else "Space / click"
	var close := "D-pad Up" if on_pad else "F"
	_hint.text = "Left / right: choose    %s: buy    %s: leave" % [confirm, close]

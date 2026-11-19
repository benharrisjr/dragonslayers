class_name PlayerHUD
extends Control

## One split-screen pane's overlay: hearts and gold top left, the three equipped things top right
## (sword, shield, and whichever usable is on the third button), and what this player has targeted.
##
## It lives inside that pane's SubViewport, so each of the four HUDs is naturally clipped to its
## own quarter of the window and nothing has to be positioned around the others.


var player: PlayerCharacter

var _hearts: HeartsDisplay
const ICON_SIZE := 40.0
const SLOT_SIZE := Vector2(54, 54)

## One entry per button: {"frame", "icon", "label"}.
var _slots: Array[Dictionary] = []
var _passive_label: Label
var _inventory: InventoryPanel
var _name_label: Label
var _gold_label: Label
var _bug_label: Label
var _shop: ShopPanel
var _wheel: GearWheel
var _target_label: Label


func setup(target_player: PlayerCharacter) -> void:
	player = target_player
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

	player.health_changed.connect(_on_health_changed)
	player.gear_changed.connect(_refresh_gear)
	## The Nintendo Layout switch changes which letters the hotkeys are printed with.
	SaveManager.keybinds_changed.connect(_refresh_gear)
	player.targeting.target_changed.connect(_on_target_changed)
	GameState.gold_changed.connect(_on_gold_changed)
	_on_health_changed(player.health, player.max_health)
	_refresh_gear()
	_on_gold_changed(GameState.gold)
	_on_target_changed(null)


func _process(_delta: float) -> void:
	## Readiness is polled rather than signalled: a cooldown changes every frame while it runs,
	## so a signal per frame per hotkey would be more machinery for the same result.
	if player == null:
		return
	for slot in _slots.size():
		var item: StringName = player.hotkeys[slot]
		(_slots[slot]["icon"] as ItemIcon).dimmed = item != &"" and not player.item_ready(item)


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(14, 10)
	root.add_theme_constant_override("separation", 4)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_name_label = _make_label(player.archetype.display_name, 15, player.archetype.color)
	root.add_child(_name_label)

	_hearts = HeartsDisplay.new()
	root.add_child(_hearts)

	_build_equipped()

	## Passive gear: held, working, nothing to press.
	_passive_label = _make_label("", 12, Color(0.85, 0.9, 0.85))
	root.add_child(_passive_label)

	_gold_label = _make_label("0 gold", 13, Color(1.0, 0.85, 0.3))
	root.add_child(_gold_label)

	_bug_label = _make_label("", 13, Color(0.6, 0.95, 0.5))
	root.add_child(_bug_label)

	## The boss bar belongs to the world rather than to this player, so it sits centred at the
	## top of the pane, above the target name.
	var dragon := get_tree().get_first_node_in_group("dragon") as Dragon
	if dragon != null:
		var boss_bar := BossBar.new()
		boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		boss_bar.position = Vector2(-180, 8)
		boss_bar.custom_minimum_size = Vector2(360, 0)
		add_child(boss_bar)
		boss_bar.setup(dragon)

	## The gear panel, opened by this player alone with Select. Local players only: nobody
	## opens a panel for a body another machine is driving.
	if player.is_local_player():
		_inventory = InventoryPanel.new()
		add_child(_inventory)
		_inventory.setup(player)
		_wheel = GearWheel.new()
		add_child(_wheel)
		_wheel.setup(player)
		_shop = ShopPanel.new()
		add_child(_shop)
		_shop.setup(player)

	## Target name sits at the top centre of the pane rather than with the rest, because it
	## describes something out in the world instead of something about you.
	_target_label = _make_label("", 14, Color(1.0, 0.6, 0.55))
	_target_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.position = Vector2(-70, 52)
	_target_label.custom_minimum_size = Vector2(140, 0)
	add_child(_target_label)


## Top right: an icon for each button -- sword, shield, and the equipped usable -- with the
## button that fires it underneath. The third frame stays empty until a usable is found.
func _build_equipped() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.position += Vector2(-14, 10)
	for _slot in ItemDB.HOTKEY_COUNT:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(column)
		var frame := PanelContainer.new()
		frame.custom_minimum_size = SLOT_SIZE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.08, 0.1, 0.13, 0.78)
		box.set_border_width_all(2)
		box.border_color = Color(0.45, 0.5, 0.58)
		box.set_corner_radius_all(5)
		box.set_content_margin_all(7)
		frame.add_theme_stylebox_override("panel", box)
		column.add_child(frame)
		var icon := ItemIcon.new(&"", ICON_SIZE)
		frame.add_child(icon)
		var label := _make_label("", 12, Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		_slots.append({"frame": frame, "icon": icon, "label": label})


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_health_changed(value: int, maximum: int) -> void:
	_hearts.set_health(value, maximum)


func _refresh_gear() -> void:
	var slot_of_player := player.slot()
	for slot in _slots.size():
		var item: StringName = player.hotkeys[slot]
		(_slots[slot]["icon"] as ItemIcon).item_id = item
		var label := _slots[slot]["label"] as Label
		label.text = PlayerBindings.hotkey_label(slot_of_player, slot)
		label.modulate = Color.WHITE if item != &"" else Color(1, 1, 1, 0.4)
	var passive: PackedStringArray = []
	for item in player.gear:
		if ItemDB.is_passive(item):
			passive.append(ItemDB.display_name(item))
	_passive_label.text = "  ".join(passive)
	## Hidden until there is something to count, so it is not clutter before the first catch.
	_bug_label.text = "%d bug%s" % [player.bugs, "" if player.bugs == 1 else "s"] \
			if player.bugs > 0 or player.has_item(ItemDB.NET) else ""


func _on_gold_changed(value: int) -> void:
	_gold_label.text = "%d gold" % value


func _on_target_changed(target: Combatant) -> void:
	if target == null:
		_target_label.text = ""
		return
	var monster := target as Monster
	_target_label.text = monster.data.display_name if monster != null else "Target"

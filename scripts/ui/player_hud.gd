class_name PlayerHUD
extends Control

## One split-screen pane's overlay: hearts, gear hotkeys, gold, and what this player has targeted.
##
## It lives inside that pane's SubViewport, so each of the four HUDs is naturally clipped to its
## own quarter of the window and nothing has to be positioned around the others.


var player: PlayerCharacter

var _hearts: HeartsDisplay
var _hotkey_labels: Array[Label] = []
var _passive_label: Label
var _inventory: InventoryPanel
var _name_label: Label
var _gold_label: Label
var _target_label: Label


func setup(target_player: PlayerCharacter) -> void:
	player = target_player
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

	player.health_changed.connect(_on_health_changed)
	player.gear_changed.connect(_refresh_gear)
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
	for slot in _hotkey_labels.size():
		var item: StringName = player.hotkeys[slot]
		var ready := item != &"" and player.item_ready(item)
		_hotkey_labels[slot].modulate = Color.WHITE if ready else Color(1, 1, 1, 0.4)


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

	## The three hotkeys, each labelled with the button that fires it. This is the whole of what
	## a player can do on a button, so it sits right under their health.
	var hotkey_row := HBoxContainer.new()
	hotkey_row.add_theme_constant_override("separation", 10)
	hotkey_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for _slot in ItemDB.HOTKEY_COUNT:
		var label := _make_label("", 13, Color.WHITE)
		_hotkey_labels.append(label)
		hotkey_row.add_child(label)
	root.add_child(hotkey_row)

	## Passive gear: held, working, nothing to press.
	_passive_label = _make_label("", 12, Color(0.85, 0.9, 0.85))
	root.add_child(_passive_label)

	_gold_label = _make_label("0 gold", 13, Color(1.0, 0.85, 0.3))
	root.add_child(_gold_label)

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

	## Target name sits at the top centre of the pane rather than with the rest, because it
	## describes something out in the world instead of something about you.
	_target_label = _make_label("", 14, Color(1.0, 0.6, 0.55))
	_target_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.position = Vector2(-70, 52)
	_target_label.custom_minimum_size = Vector2(140, 0)
	add_child(_target_label)


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
	for slot in _hotkey_labels.size():
		var item: StringName = player.hotkeys[slot]
		var label := _hotkey_labels[slot]
		label.text = "%s  %s" % [PlayerBindings.hotkey_label(slot_of_player, slot),
				ItemDB.display_name(item) if item != &"" else "-"]
		label.add_theme_color_override("font_color",
				ItemDB.color(item) if item != &"" else Color(0.6, 0.6, 0.6))
	var passive: PackedStringArray = []
	for item in player.gear:
		if ItemDB.is_passive(item):
			passive.append(ItemDB.display_name(item))
	_passive_label.text = "  ".join(passive)


func _on_gold_changed(value: int) -> void:
	_gold_label.text = "%d gold" % value


func _on_target_changed(target: Combatant) -> void:
	if target == null:
		_target_label.text = ""
		return
	var monster := target as Monster
	_target_label.text = monster.data.display_name if monster != null else "Target"

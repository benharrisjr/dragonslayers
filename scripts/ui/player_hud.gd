class_name PlayerHUD
extends Control

## One split-screen pane's overlay: hearts, magic, gold, and what this player has targeted.
##
## It lives inside that pane's SubViewport, so each of the four HUDs is naturally clipped to its
## own quarter of the window and nothing has to be positioned around the others.

const MAGIC_BAR_SIZE := Vector2(150.0, 12.0)

var player: PlayerCharacter

var _hearts: HeartsDisplay
var _magic_fill: ColorRect
var _name_label: Label
var _gold_label: Label
var _target_label: Label
var _cooldown_row: HBoxContainer


func setup(target_player: PlayerCharacter) -> void:
	player = target_player
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

	player.health_changed.connect(_on_health_changed)
	player.magic_changed.connect(_on_magic_changed)
	player.targeting.target_changed.connect(_on_target_changed)
	GameState.gold_changed.connect(_on_gold_changed)
	_on_health_changed(player.health, player.max_health)
	_on_magic_changed(player.magic, player.max_magic)
	_on_gold_changed(GameState.gold)
	_on_target_changed(null)


func _process(_delta: float) -> void:
	## Cooldown pips are polled rather than signalled: they change every frame while running, so
	## a signal per frame per ability would be more machinery for the same result.
	if player == null or _cooldown_row == null:
		return
	var abilities := player.abilities()
	for index in _cooldown_row.get_child_count():
		var pip := _cooldown_row.get_child(index) as ColorRect
		if index >= abilities.size():
			pip.visible = false
			continue
		var ability := abilities[index]
		var ready := player.cooldown_fraction(ability) <= 0.0 and ability.can_afford(player.magic)
		pip.color = ability.vfx_color if ready else ability.vfx_color.darkened(0.7)


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

	var magic_back := ColorRect.new()
	magic_back.color = Color(0.1, 0.1, 0.16, 0.8)
	magic_back.custom_minimum_size = MAGIC_BAR_SIZE
	root.add_child(magic_back)
	_magic_fill = ColorRect.new()
	_magic_fill.color = Color(0.35, 0.6, 1.0)
	_magic_fill.size = MAGIC_BAR_SIZE
	magic_back.add_child(_magic_fill)

	_cooldown_row = HBoxContainer.new()
	_cooldown_row.add_theme_constant_override("separation", 4)
	for _i in 4:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(20, 6)
		pip.color = Color(0.4, 0.4, 0.4)
		_cooldown_row.add_child(pip)
	root.add_child(_cooldown_row)

	_gold_label = _make_label("0 gold", 13, Color(1.0, 0.85, 0.3))
	root.add_child(_gold_label)

	## Target name sits at the top centre of the pane rather than with the rest, because it
	## describes something out in the world instead of something about you.
	_target_label = _make_label("", 14, Color(1.0, 0.6, 0.55))
	_target_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.position = Vector2(-70, 12)
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


func _on_magic_changed(value: float, maximum: float) -> void:
	var fraction := 0.0 if maximum <= 0.0 else clampf(value / maximum, 0.0, 1.0)
	_magic_fill.size = Vector2(MAGIC_BAR_SIZE.x * fraction, MAGIC_BAR_SIZE.y)


func _on_gold_changed(value: int) -> void:
	_gold_label.text = "%d gold" % value


func _on_target_changed(target: Combatant) -> void:
	if target == null:
		_target_label.text = ""
		return
	var monster := target as Monster
	_target_label.text = monster.data.display_name if monster != null else "Target"

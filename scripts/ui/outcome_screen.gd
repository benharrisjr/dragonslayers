class_name OutcomeScreen
extends Control

## The end of a run: the dragon is dead and the party has won.
##
## Deliberately a full-screen overlay rather than a per-pane one -- the run ends for everybody
## at once, and four separate victory banners in four quarters would read as four results.

signal rematch_requested

var _title: Label
var _detail: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	GameState.phase_changed.connect(_on_phase_changed)


func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.04, 0.06, 0.05, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.position = Vector2(-260, -90)
	column.custom_minimum_size = Vector2(520, 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_title = Label.new()
	_title.text = "THE DRAGON IS SLAIN"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 44)
	_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 8)
	column.add_child(_title)

	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 17)
	_detail.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	column.add_child(_detail)


func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase != GameState.Phase.VICTORY:
		visible = false
		return
	var party := PlayerRegistry.roster.size()
	_detail.text = "%d slayer%s  ·  %d gold earned" % [
		party, "" if party == 1 else "s", GameState.gold]
	visible = true

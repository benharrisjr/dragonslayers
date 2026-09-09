class_name BossBar
extends VBoxContainer

## The dragon's health, shown across the top of a pane while the fight is live.
##
## Appears only when the dragon is engaged and hides again when the party is wiped off the
## platform, which makes it double as the fight's state readout: the bar vanishing is how you
## learn the fight has reset and the health you chipped off has come back.

const BAR_SIZE := Vector2(360.0, 16.0)
const CALM_COLOR := Color(0.75, 0.25, 0.25)
const ENRAGED_COLOR := Color(1.0, 0.55, 0.15)

var dragon: Dragon

var _fill: ColorRect
var _label: Label


func setup(boss: Dragon) -> void:
	dragon = boss
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.text = "The Dragon"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.8))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	var back := ColorRect.new()
	back.color = Color(0.08, 0.05, 0.06, 0.85)
	back.custom_minimum_size = BAR_SIZE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	_fill = ColorRect.new()
	_fill.color = CALM_COLOR
	_fill.size = BAR_SIZE
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(_fill)

	visible = false
	if dragon != null:
		dragon.phase_changed.connect(_on_phase_changed)


func _process(_delta: float) -> void:
	if dragon == null or not is_instance_valid(dragon):
		visible = false
		return
	visible = dragon.is_engaged()
	if not visible:
		return
	var fraction := clampf(dragon.health_fraction(), 0.0, 1.0)
	_fill.size = Vector2(BAR_SIZE.x * fraction, BAR_SIZE.y)
	_label.text = "The Dragon%s" % ("  —  ENRAGED" if dragon.enraged else "")


func _on_phase_changed(enraged: bool) -> void:
	_fill.color = ENRAGED_COLOR if enraged else CALM_COLOR

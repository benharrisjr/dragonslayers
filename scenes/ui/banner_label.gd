class_name BannerLabel extends Control
## A title banner: a flat accent-bordered strip with centred heading text, for
## the top of a panel or page.

const HEIGHT := 56
const MIN_W := 96
const PAD_X := 24

@export var title: String = "" :
	set(v):
		title = v
		if _label and is_node_ready():
			_label.text = v
			update_minimum_size()

var _label: Label


## A centred banner in a margin wrapper, ready to drop at the top of a VBox.
static func make_page_title(title_text: String, width: int = 220) -> MarginContainer:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 4)
	pad.mouse_filter = MOUSE_FILTER_IGNORE
	var b := BannerLabel.new()
	b.title = title_text
	b.custom_minimum_size = Vector2(width, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pad.add_child(b)
	return pad


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", UiTheme.hud_panel_style(UiTheme.TEXT_HEADING.darkened(0.25)))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	_label = Label.new()
	_label.text = title
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", UiTheme.TEXT_HEADING)
	FontSizes.apply(_label, FontSizes.HEADING_SMALL)
	add_child(_label)
	update_minimum_size()


func _get_minimum_size() -> Vector2:
	var w := float(MIN_W)
	if _label:
		w = maxf(w, _label.get_minimum_size().x + PAD_X * 2.0)
	return Vector2(w, HEIGHT)

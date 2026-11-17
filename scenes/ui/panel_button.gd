class_name PanelButton extends Control
## The project's button: a flat UiTheme-styled tile with a label, an optional
## icon and an optional key-prompt badge. Built in code:
##
##   var b := PanelButton.new()
##   b.text = "Play"
##   b.tint = UiTheme.CONFIRM          # optional colour variant
##   b.pressed.connect(_on_play)
##
## The inner Button does the clicking and takes focus (see get_focus_target), so
## SoundManager's hover/click sounds and PadCursor's hand work on it unchanged.

## Colour-variant keys for `texture` / `frame_texture`, kept from when buttons
## wore tinted tile art: assigning one (or null) picks the variant, exactly like
## setting `tint`. Every "Close" button uses RED_TEX so a dismiss action reads
## the same on every panel; green is confirm / selected, blue secondary.
static var RED_TEX: Texture2D = _swatch(UiTheme.DANGER)
static var GREEN_TEX: Texture2D = _swatch(UiTheme.CONFIRM)
static var BLUE_TEX: Texture2D = _swatch(UiTheme.ACCENT)
static var FRAME_TEX: Texture2D = _swatch(UiTheme.NO_TINT)
static var FRAME_GREEN_TEX: Texture2D = GREEN_TEX
static var FRAME_RED_TEX: Texture2D = RED_TEX
static var FRAME_BLUE_TEX: Texture2D = BLUE_TEX
const _TINT_META := &"panel_button_tint"

signal pressed
signal toggled(button_pressed: bool)
## A left click landed while the button is disabled (a disabled Button never
## emits pressed). Lets a refused action explain itself, e.g. a still-charging
## ability says "Still charging!" exactly as its hotkey does.
signal disabled_pressed

# Extra downward nudge for the label/icon on top of vertical centering, for
# fonts or frames that sit high. 0 with the flat style.
const _TOP_PAD := 0.0
# Padding added around the label/icon when computing minimum size, so text
# stays off the border and auto-sized buttons get a roomy click target.
const _MIN_SIZE_PAD := Vector2(32, 16.0 + _TOP_PAD)
const _ICON_SIZE := Vector2(16, 16)
# Space between the icon and the label when a button has both.
const _ICON_TEXT_GAP := 6.0

@export var text: String = "":
	set(v):
		text = v
		if _label:
			_label.text = v
		_layout_icon()
		update_minimum_size()

# Optional content icon: centered on an icon-only button, leading the label
# (the pair centered together) when the button also has text. Drawn on top
# of the tile at 16x16 * icon_scale so 16px and 32px source art land on
# integer pixel scales.
var icon: Texture2D = null:
	set(v):
		icon = v
		if _icon:
			_icon.texture = v
			_icon.visible = v != null
		_layout_icon()
		update_minimum_size()

# Optional hotkey badge (a Keybinds key-prompt texture) pinned over the
# button's top-left corner, overhanging it slightly. Kept
# separate from `icon` so a text button can show its key too. null hides it.
var key_hint: Texture2D = null:
	set(v):
		key_hint = v
		_layout_key_hint()

# Integer multiplier on the 16x16 icon box (2 = 32x32).
var icon_scale: int = 1:
	set(v):
		icon_scale = maxi(1, v)
		_layout_icon()
		update_minimum_size()

var disabled: bool = false:
	set(v):
		disabled = v
		if _btn:
			_btn.disabled = v
		_update_modulate()

var toggle_mode: bool = false:
	set(v):
		toggle_mode = v
		if _btn:
			_btn.toggle_mode = v

var button_pressed: bool = false:
	set(v):
		button_pressed = v
		if _btn:
			_btn.button_pressed = v
		_update_modulate()

var button_focus_mode: int = Control.FOCUS_ALL:
	set(v):
		button_focus_mode = v
		if _btn:
			_btn.focus_mode = v

## Colour variant: UiTheme.ACCENT / CONFIRM / DANGER (or any colour) tints the
## fill and border; UiTheme.NO_TINT is the plain button.
var tint: Color = UiTheme.NO_TINT:
	set(v):
		tint = v
		_refresh_style()

## Variant by swatch (RED_TEX / GREEN_TEX / BLUE_TEX, null = plain). Overrides
## `tint` while set.
var texture: Texture2D = null:
	set(v):
		texture = v
		_refresh_style()

## Same as `texture` (FRAME_*_TEX); wins over it when both are set.
var frame_texture: Texture2D = null:
	set(v):
		frame_texture = v
		_refresh_style()

var _bg: Panel = null
var _hovered := false
var _down := false
var _btn: Button = null
var _label: Label = null
var _icon: TextureRect = null
var _key_hint_rect: TextureRect = null
var _pending_font_size: int = 0
# The label's full-rect left/right offsets before _layout_icon shifts it right
# to make room for a leading icon.
var _base_label_offsets := Vector2.ZERO


func _ready() -> void:
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_IGNORE

	_bg = Panel.new()
	_bg.mouse_filter = MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	var empty := StyleBoxEmpty.new()
	_btn = Button.new()
	_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn.flat = true
	_btn.focus_mode = button_focus_mode
	_btn.toggle_mode = toggle_mode
	_btn.button_pressed = button_pressed
	_btn.disabled = disabled
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"]:
		_btn.add_theme_stylebox_override(state, empty)
	_btn.pressed.connect(func() -> void: pressed.emit())
	_btn.gui_input.connect(_on_btn_gui_input)
	_btn.toggled.connect(_on_btn_toggled)
	_btn.mouse_entered.connect(_on_hover_enter)
	_btn.mouse_exited.connect(_on_hover_exit)
	_btn.button_down.connect(_on_button_down)
	_btn.button_up.connect(_on_button_up)
	_btn.focus_entered.connect(_refresh_style)
	_btn.focus_exited.connect(_refresh_style)
	add_child(_btn)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.offset_top += _TOP_PAD
	_label.offset_bottom += _TOP_PAD
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.text = text
	var font_size := _pending_font_size if _pending_font_size > 0 else FontSizes.size_of(FontSizes.BODY)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", UiTheme.TEXT)
	add_child(_label)
	_base_label_offsets = Vector2(_label.offset_left, _label.offset_right)

	_icon = TextureRect.new()
	_icon.texture = icon
	_icon.visible = icon != null
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.mouse_filter = MOUSE_FILTER_IGNORE
	_layout_icon()
	add_child(_icon)

	# Ensure bg/btn/label/icon stay at the front of the child list so any
	# content added before _ready() fires (e.g. in an off-screen build) ends up
	# on top and remains visible.
	move_child(_bg, 0)
	move_child(_btn, 1)
	move_child(_label, 2)
	move_child(_icon, 3)

	_layout_key_hint()
	_update_modulate()
	update_minimum_size()


static func _swatch(color: Color) -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta(_TINT_META, color)
	return tex


# The variant colour in effect: frame_texture, then texture, then tint.
func _effective_tint() -> Color:
	for tex: Texture2D in [frame_texture, texture]:
		if tex != null and tex.has_meta(_TINT_META) and (tex.get_meta(_TINT_META) as Color).a > 0.0:
			return tex.get_meta(_TINT_META)
	return tint


func _refresh_style() -> void:
	if _bg == null:
		return
	var state := &"normal"
	if disabled:
		state = &"disabled"
	elif _down or (toggle_mode and button_pressed):
		state = &"pressed"
	elif _hovered:
		state = &"hover"
	var focused := _btn != null and _btn.has_focus()
	_bg.add_theme_stylebox_override("panel", UiTheme.button_style(state, _effective_tint(), focused))


# Key-prompt tiles are 16px (wide keys 32x16); 2x reads at the 1920x1080 canvas.
const _KEY_HINT_SCALE := 2.0

func _layout_key_hint() -> void:
	if not is_node_ready():
		return
	if key_hint == null:
		if _key_hint_rect:
			_key_hint_rect.visible = false
		return
	if _key_hint_rect == null:
		_key_hint_rect = TextureRect.new()
		_key_hint_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_key_hint_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_key_hint_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_key_hint_rect.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_key_hint_rect)
	var box := key_hint.get_size() * _KEY_HINT_SCALE
	_key_hint_rect.texture = key_hint
	_key_hint_rect.visible = true
	_key_hint_rect.position = -box * 0.3
	_key_hint_rect.size = box


# Grow past custom_minimum_size when the label text (or icon) doesn't fit 
# Control takes the max of the two, so hardcoded sizes remain floors.
func _get_minimum_size() -> Vector2:
	if _label and not _label.text.is_empty():
		var min_size := _label.get_minimum_size() + _MIN_SIZE_PAD
		if icon:
			min_size.x += _icon_box().x + _ICON_TEXT_GAP
			min_size.y = maxf(min_size.y, _icon_box().y + _MIN_SIZE_PAD.y)
		return min_size
	if icon:
		return _icon_box() + _MIN_SIZE_PAD
	return Vector2.ZERO


func _icon_box() -> Vector2:
	return _ICON_SIZE * icon_scale


# Centre the icon rect at its scaled box size. With text too, icon + gap + text
# are centered as one group: the label shifts right by half the icon's share and
# the icon sits just left of the text's measured width.
func _layout_icon() -> void:
	if not _icon:
		return
	var box := _icon_box()
	var dx := 0.0
	var label_shift := 0.0
	if icon and _label and not _label.text.is_empty():
		var text_w := _label.get_minimum_size().x
		dx = -(text_w + _ICON_TEXT_GAP) * 0.5
		label_shift = (box.x + _ICON_TEXT_GAP) * 0.5
	if _label:
		_label.offset_left = _base_label_offsets.x + label_shift
		_label.offset_right = _base_label_offsets.y + label_shift
	_icon.custom_minimum_size = box
	_icon.set_anchors_preset(Control.PRESET_CENTER)
	_icon.offset_left = -box.x * 0.5 + dx
	_icon.offset_top = -box.y * 0.5 + _TOP_PAD
	_icon.offset_right = box.x * 0.5 + dx
	_icon.offset_bottom = box.y * 0.5 + _TOP_PAD


# The focusable node is the inner Button (the outer wrapper is FOCUS_NONE), so
# focus/neighbor navigation and the SelectionReticle operate on it. Its full-rect
# anchors make its global rect match this PanelButton, so the reticle frames the
# whole button. Callers that want to seed focus use SelectionReticle.focus_first(),
# which honors this getter.
func get_focus_target() -> Control:
	return _btn if _btn else self


## Swap the label's font (e.g. UIFont.READABLE_FILE where a display font's
## digits misread). Call after the button is in the tree.
func set_label_font(font: Font) -> void:
	if _label:
		_label.add_theme_font_override("font", font)
		update_minimum_size()


func set_input_passthrough(enabled: bool) -> void:
	var filter := MOUSE_FILTER_IGNORE if enabled else MOUSE_FILTER_STOP
	mouse_filter = filter
	if _btn:
		_btn.mouse_filter = filter


@warning_ignore("NATIVE_METHOD_OVERRIDE")
func add_theme_font_size_override(prop: StringName, size: int) -> void:
	if _label:
		_label.add_theme_font_size_override(prop, size)
		_layout_icon()
		update_minimum_size()
	elif prop == &"font_size":
		_pending_font_size = size
	else:
		super.add_theme_font_size_override(prop, size)


@warning_ignore("NATIVE_METHOD_OVERRIDE")
func add_theme_color_override(prop: StringName, color: Color) -> void:
	if prop in [&"font_color", &"font_outline_color", &"font_shadow_color"] and _label:
		_label.add_theme_color_override(prop, color)
	else:
		super.add_theme_color_override(prop, color)


@warning_ignore("NATIVE_METHOD_OVERRIDE")
func add_theme_constant_override(prop: StringName, value: int) -> void:
	if prop == &"outline_size" and _label:
		_label.add_theme_constant_override("outline_size", value)
	else:
		super.add_theme_constant_override(prop, value)


func _on_btn_toggled(p: bool) -> void:
	button_pressed = p
	toggled.emit(p)


func _on_hover_enter() -> void:
	_hovered = true
	_refresh_style()


func _on_hover_exit() -> void:
	_hovered = false
	_refresh_style()


func _on_button_down() -> void:
	_down = true
	_refresh_style()


func _on_button_up() -> void:
	_down = false
	_refresh_style()


func _update_modulate() -> void:
	if not _bg:
		return
	_refresh_style()
	# The label/icon grey out with the tile, or a disabled button still reads
	# as live from its bright text.
	var content := Color(0.55, 0.55, 0.55) if disabled else Color.WHITE
	if _label:
		_label.modulate = content
	if _icon:
		_icon.modulate = content


func _on_btn_gui_input(event: InputEvent) -> void:
	if not disabled:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		disabled_pressed.emit()

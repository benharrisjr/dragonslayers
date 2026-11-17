class_name IconPanel extends Control

## Generic bordered icon slot: a frame with a content icon centred inside it.
## Any screen that shows an item / ability / achievement icon can use this so
## the "slotted" look stays consistent.
##
## By default the frame is a flat UiTheme border. Set `frame_texture` to draw a
## game's own frame art instead (nine-patched, see frame_slice / frame_pixel_scale).

## Border width of the flat frame, and the pixel scale a frame texture is drawn
## at: the texture is laid out at 1/FRAME_PIXEL_SCALE of the control's size and
## scaled back up, so every source pixel becomes a FRAME_PIXEL_SCALE-px block.
const FRAME_PIXEL_SCALE := 3
const _FRAME_SLICE := 3
## Inset ratio (of this control's size) the icon is drawn at, so the sprite
## sits inside the frame's border band instead of drawing over it.
const ICON_INSET_RATIO := 0.12

## Optional frame art; null draws the flat UiTheme frame.
@export var frame_texture: Texture2D = null:
	set(v):
		frame_texture = v
		_refresh_frame()

## Flat frame: border width in px. Frame texture: its pixel scale (see
## FRAME_PIXEL_SCALE).
@export var frame_pixel_scale: int = FRAME_PIXEL_SCALE:
	set(v):
		frame_pixel_scale = maxi(v, 1)
		_refresh_frame()

## Nine-patch margin (source px) on every edge of a frame texture.
@export var frame_slice: int = _FRAME_SLICE:
	set(v):
		frame_slice = maxi(v, 1)
		_refresh_frame()

@export var icon_texture: Texture2D = null:
	set(v):
		icon_texture = v
		if _icon:
			_icon.texture = v
			_icon.visible = v != null

## Tint applied to the frame only (e.g. to fade a locked slot's border without
## also dimming the icon drawn over it).
var frame_tint: Color = Color.WHITE:
	set(v):
		frame_tint = v
		_refresh_frame()

## Tint applied to the icon only, independent of `frame_tint`.
var content_modulate: Color = Color.WHITE:
	set(v):
		content_modulate = v
		if _icon:
			_icon.modulate = v

## Material on the icon only (e.g. a silhouette shader for an empty slot's
## placeholder); the frame is never affected.
var icon_material: Material = null:
	set(v):
		icon_material = v
		if _icon:
			_icon.material = v

## Material on the frame only; the icon is never affected.
var frame_material: Material = null:
	set(v):
		frame_material = v
		if _flat:
			_flat.material = v
		if _frame:
			_frame.material = v

## Fill behind the frame (e.g. UiTheme.PANEL_BACKING_COLOR). Transparent = no fill.
var fill_color: Color = Color.TRANSPARENT:
	set(v):
		fill_color = v
		_refresh_frame()

var _fill: ColorRect = null      # fill under a frame texture
var _flat: Panel = null          # the flat frame (and its fill)
var _frame: NinePatchRect = null # frame texture, when one is set
var _icon: TextureRect = null


static func make(icon_tex: Texture2D, size: Vector2i = Vector2i(48, 48), frame_tex: Texture2D = null) -> IconPanel:
	var node := IconPanel.new()
	if frame_tex:
		node.frame_texture = frame_tex
	node.custom_minimum_size = Vector2(size)
	node.icon_texture = icon_tex
	return node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_fill = ColorRect.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)

	_flat = Panel.new()
	_flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flat.material = frame_material
	add_child(_flat)

	_frame = NinePatchRect.new()
	_frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	_frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.material = frame_material
	add_child(_frame)
	_refresh_frame()
	resized.connect(_layout_frame)

	_icon = TextureRect.new()
	_icon.texture = icon_texture
	_icon.visible = icon_texture != null
	_icon.modulate = content_modulate
	_icon.material = icon_material
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_layout_icon()


## The icon TextureRect inside the frame, for owners that need to hide or
## anchor to the icon alone (a drag source). Only valid once the panel is in
## the tree.
func icon_control() -> Control:
	return _icon


# Flat UiTheme frame by default; the nine-patch (over its own fill) when a
# frame texture is set.
func _refresh_frame() -> void:
	if not _frame:
		return
	var textured := frame_texture != null
	_flat.visible = not textured
	_frame.visible = textured
	_fill.visible = textured and fill_color.a > 0.0
	if textured:
		_frame.texture = frame_texture
		_frame.self_modulate = frame_tint
		_frame.scale = Vector2.ONE * frame_pixel_scale
		_frame.patch_margin_left = frame_slice
		_frame.patch_margin_right = frame_slice
		_frame.patch_margin_top = frame_slice
		_frame.patch_margin_bottom = frame_slice
		_fill.color = fill_color
		_layout_frame()
	else:
		_flat.add_theme_stylebox_override("panel",
				UiTheme.slot_style(UiTheme.BUTTON_BORDER * frame_tint, fill_color, frame_pixel_scale))


func _layout_frame() -> void:
	if not _frame:
		return
	_frame.position = Vector2.ZERO
	_frame.size = size / frame_pixel_scale
	_fill.position = Vector2.ONE * frame_pixel_scale
	_fill.size = (size - Vector2.ONE * 2.0 * frame_pixel_scale).max(Vector2.ZERO)


func _layout_icon() -> void:
	if not _icon:
		return
	var r := ICON_INSET_RATIO
	_icon.anchor_left = r
	_icon.anchor_right = 1.0 - r
	_icon.anchor_top = r
	_icon.anchor_bottom = 1.0 - r
	_icon.offset_left = 0.0
	_icon.offset_right = 0.0
	_icon.offset_top = 0.0
	_icon.offset_bottom = 0.0

class_name PixelBar extends ColorRect
## Pixel-art skin for a ProgressBar (pixel_bar.gdshader). attach() blanks the
## bar's own styleboxes and lays this rect under its other children; the ratio
## follows the bar's value through Range's signals, so the host keeps setting
## value/max_value exactly as before and pays nothing per frame.
##
## Modes: HP (colour by threshold, low-HP pulse, hit flash, heal sheen) and
## ATB (caller-chosen fill, charge stripes, ready pulse + looping sheen, stopped
## hatch). Hosts drive the moments with flash() / sheen().

const SHADER := preload("res://scenes/ui/pixel_bar.gdshader")

const HP_HIGH := Color(0.2, 0.75, 0.3)
const HP_MID := Color(0.9, 0.75, 0.15)
const HP_LOW := Color(0.85, 0.2, 0.15)
const HP_MID_AT := 0.5
const HP_LOW_AT := 0.25

const FLASH_T := 0.12
const SHEEN_T := 0.45

var _bar: Range = null
var _mat: ShaderMaterial = null
var _hp_mode := false
var _flash_tween: Tween = null
var _sheen_tween: Tween = null


## Skin `bar`. `hp` turns on threshold colours and the low-HP pulse;
## otherwise the fill is whatever set_fill_color() says. `px` is the art-pixel
## size in screen pixels.
static func attach(bar: ProgressBar, hp: bool, px: float = 2.0) -> PixelBar:
	var empty := StyleBoxEmpty.new()
	bar.add_theme_stylebox_override("fill", empty)
	bar.add_theme_stylebox_override("background", empty)
	var pb := PixelBar.new()
	pb._bar = bar
	pb._hp_mode = hp
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb._mat = ShaderMaterial.new()
	pb._mat.shader = SHADER
	pb._mat.set_shader_parameter("px", px)
	pb.material = pb._mat
	bar.add_child(pb)
	bar.move_child(pb, 0)
	pb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pb.resized.connect(pb._on_resized)
	bar.value_changed.connect(func(_v: float) -> void: pb._sync())
	bar.changed.connect(pb._sync)
	pb._on_resized()
	pb._sync()
	return pb


func _on_resized() -> void:
	_mat.set_shader_parameter("rect_size", size)


func _sync() -> void:
	var span := _bar.max_value - _bar.min_value
	var r := clampf((_bar.value - _bar.min_value) / span, 0.0, 1.0) if span > 0.0 else 0.0
	_mat.set_shader_parameter("ratio", r)
	if _hp_mode:
		var c := HP_HIGH
		if r <= HP_LOW_AT:
			c = HP_LOW
		elif r <= HP_MID_AT:
			c = HP_MID
		_mat.set_shader_parameter("fill_color", c)
		# Critical: a slow red throb, like the classic low-HP warning. Not at 0.
		_mat.set_shader_parameter("pulse", 0.35 if r > 0.0 and r <= HP_LOW_AT else 0.0)


func set_fill_color(c: Color) -> void:
	_mat.set_shader_parameter("fill_color", c)


## ATB looks: `stripes` while charging, `ready` pulses with a looping sheen,
## `stopped` swaps the fill for a grey hatch.
func set_atb_look(stripes: bool, ready: bool, stopped: bool) -> void:
	_mat.set_shader_parameter("stripe_strength", 0.12 if stripes else 0.0)
	_mat.set_shader_parameter("pulse", 0.3 if ready else 0.0)
	_mat.set_shader_parameter("sheen_loop", 1.0 if ready else 0.0)
	_mat.set_shader_parameter("hatch", 1.0 if stopped else 0.0)


## A white blink over the whole bar (a hit landed).
func flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_mat.set_shader_parameter("flash", 0.85)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float) -> void: _mat.set_shader_parameter("flash", v),
		0.85, 0.0, FLASH_T)


## One bright band swept along the fill (a heal landed).
func sheen() -> void:
	if _sheen_tween and _sheen_tween.is_valid():
		_sheen_tween.kill()
	_sheen_tween = create_tween()
	_sheen_tween.tween_method(func(v: float) -> void: _mat.set_shader_parameter("sheen_pos", v),
		-0.3, 1.3, SHEEN_T)
	_sheen_tween.tween_callback(func() -> void: _mat.set_shader_parameter("sheen_pos", -1.0))

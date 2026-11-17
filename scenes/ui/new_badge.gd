class_name NewBadge
extends RefCounted
## "Something new here" marks:
## - set_dot: a red dot in a control's top-right corner.
## - wrap_glow: a pulsing outline around a row.
## Both are cleared by the same calls with `on` false (set_dot) / clear_glow.
## dot_until_pressed wears the dot until the control is pressed once.

const DOT_NAME := &"NewBadgeDot"
const GLOW_NAME := &"NewBadgeGlow"
const DOT_SIZE := 16.0
const DOT_INSET := Vector2(-2, -4)    # from the top-right corner (left, down)
const DOT_COLOR := Color(0.92, 0.22, 0.22)
const DOT_RIM := Color(1, 1, 1, 0.9)
const GLOW_COLOR := Color(1.0, 0.82, 0.35)
const GLOW_SIZE := 10
const GLOW_PULSE := Vector2(0.35, 0.9)   # alpha low / high
const GLOW_PERIOD := 0.7


class Dot extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sz := Vector2.ONE * NewBadge.DOT_SIZE
		size = sz
		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 0.0
		anchor_bottom = 0.0
		offset_left = -sz.x + NewBadge.DOT_INSET.x
		offset_right = NewBadge.DOT_INSET.x
		offset_top = NewBadge.DOT_INSET.y
		offset_bottom = NewBadge.DOT_INSET.y + sz.y

	func _draw() -> void:
		var r := NewBadge.DOT_SIZE * 0.5
		draw_circle(Vector2(r, r), r, NewBadge.DOT_RIM)
		draw_circle(Vector2(r, r), r - 2.0, NewBadge.DOT_COLOR)


## Show or clear the red dot on `c` (any non-container control: a PanelButton,
## a CheckBox).
static func set_dot(c: Control, on: bool) -> void:
	if c == null:
		return
	var dot := c.get_node_or_null(NodePath(DOT_NAME))
	if on and dot == null:
		dot = Dot.new()
		dot.name = DOT_NAME
		c.add_child(dot)
	elif not on and dot != null:
		dot.queue_free()


## Puts `row` (already in a container) inside a holder that also carries a
## pulsing glow behind it. Returns the holder; clear_glow undoes the glow only
## (the holder stays, it lays out exactly like the bare row).
static func wrap_glow(row: Control) -> Control:
	var parent := row.get_parent()
	var idx := row.get_index()
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = row.size_flags_horizontal
	parent.add_child(holder)
	parent.move_child(holder, idx)
	row.reparent(holder, false)

	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_corner_radius_all(6)
	style.shadow_size = GLOW_SIZE
	style.shadow_color = GLOW_COLOR
	var glow := Panel.new()
	glow.name = GLOW_NAME
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.add_theme_stylebox_override("panel", style)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	holder.add_child(glow)
	holder.move_child(glow, 0)   # behind the row
	glow.modulate.a = GLOW_PULSE.x
	var pulse := glow.create_tween().set_loops()
	pulse.tween_property(glow, "modulate:a", GLOW_PULSE.y, GLOW_PERIOD) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow, "modulate:a", GLOW_PULSE.x, GLOW_PERIOD) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	glow.set_meta(&"pulse", pulse)
	return holder


static func clear_glow(holder: Control) -> void:
	if holder == null:
		return
	var glow := holder.get_node_or_null(NodePath(GLOW_NAME))
	if glow == null:
		return
	var pulse: Tween = glow.get_meta(&"pulse", null)
	if pulse and pulse.is_valid():
		pulse.kill()
	var tw := glow.create_tween()
	tw.tween_property(glow, "modulate:a", 0.0, 0.2)
	tw.tween_callback(glow.queue_free)


## Wears the red dot until `btn` (a Button or PanelButton: both have `pressed`)
## is pressed, then the dot goes and `on_pressed` runs.
static func dot_until_pressed(btn: Control, on_pressed: Callable) -> void:
	set_dot(btn, true)
	btn.connect(&"pressed", func() -> void:
		set_dot(btn, false)
		on_pressed.call(), CONNECT_ONE_SHOT)

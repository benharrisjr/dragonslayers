class_name PopMessage extends RefCounted

## Stacked pop-in message: up to a few short lines centred on a point, each
## popping in on its own (scale-up, with an optional chime stepping up in
## pitch), a number line then rolling from its old value to the new one, and
## once all have held they pop back out one by one, each leaving a small burst
## of sparks in its own colour. Use it for rewards, level-ups, stat changes.
##
## Pieces: {"text": String, "color": Color} for a plain line, or
##         {"label": String, "from": float, "to": float, "suffix": String} for
##         a rolling number ("HP 120 → 165" reads as "HP 165" at rest), or
##         {"text_from": String, "text": String, "color": Color} for a line that
##         pops in as `text_from` and flips to `text` ("Cleave II" → "Cleave III").
##
## `framed`: the stack sits in a UiTheme panel, popping in first and out last.
##
## Sounds are off until a game names them: register streams with
## SoundManager.register_sfx and set the sfx_* ids below.

## SoundManager.play_sfx ids; empty = silent.
static var sfx_pop: StringName = &""       # each piece popping in / out
static var sfx_count: StringName = &""     # each tick of a rolling number
static var sfx_flip: StringName = &""      # a text_from -> text flip

const NAME_COLOR := Color(1.0, 0.9, 0.4)
const LABEL_COLOR := Color(0.9, 0.92, 1.0)
const VALUE_COLOR := Color(0.55, 1.0, 0.65)
const POP_IN := 0.28        # per-piece scale-up (TRANS_BACK overshoot)
const STAGGER := 0.24       # gap between one piece popping and the next
const COUNT := 0.55         # a number's from→to roll, after its pop
const HOLD := 0.9           # everything up and settled before popping out
const POP_OUT := 0.18
const FLIP := 0.12          # each half of a text_from → text flip (squash, swap, unsquash)
const LINE_SEP := 2
const EDGE := 8.0
const FRAME_PAD := Vector2(14, 8)  # stack inset inside the frame


## Plays `pieces` centred on `center` (global), kept inside `bounds` (global),
## as children of `host` (a free-layout Control such as an overlay layer).
## `on_done` fires after the last piece has popped out.
static func play(host: Control, pieces: Array, center: Vector2, bounds: Rect2,
		on_done: Callable = Callable(), framed: bool = false) -> void:
	if host == null or not is_instance_valid(host) or pieces.is_empty():
		return
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", LINE_SEP)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.z_index = 200
	host.add_child(stack)

	var labels: Array[Label] = []
	for piece: Dictionary in pieces:
		var lbl := Label.new()
		var is_number: bool = piece.has("from")
		if is_number:
			lbl.text = _number_text(piece, piece["from"])
		else:
			lbl.text = str(piece.get("text_from", piece.get("text", "")))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		FontSizes.apply(lbl, FontSizes.BODY)
		lbl.add_theme_color_override("font_color",
			piece.get("color", VALUE_COLOR if is_number else NAME_COLOR))
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 6)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.scale = Vector2.ZERO
		# Reserve the widest text the line will show (rolled-to number, flipped-to
		# name) so the frame sized below never clips it mid-ceremony.
		var font := lbl.get_theme_font("font")
		var fsize := lbl.get_theme_font_size("font_size")
		var widest := 0.0
		for t in _texts_of(piece):
			widest = maxf(widest, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x)
		lbl.custom_minimum_size.x = ceilf(widest)
		stack.add_child(lbl)
		labels.append(lbl)

	# Let the box lay its lines out once so every label has a size to pivot on
	# and the stack a size to centre.
	await host.get_tree().process_frame
	if not is_instance_valid(stack) or not is_instance_valid(host):
		return
	# A frame grows the footprint past the lines, so keep that inside too.
	var edge := Vector2.ONE * EDGE + (FRAME_PAD if framed else Vector2.ZERO)
	var x := clampf(center.x - stack.size.x * 0.5, bounds.position.x + edge.x,
		maxf(bounds.position.x + edge.x, bounds.end.x - stack.size.x - edge.x))
	var y := clampf(center.y - stack.size.y * 0.5, bounds.position.y + edge.y,
		maxf(bounds.position.y + edge.y, bounds.end.y - stack.size.y - edge.y))
	stack.global_position = Vector2(x, y)
	for lbl in labels:
		lbl.pivot_offset = lbl.size * 0.5

	var tw := host.create_tween()
	var frame := _build_frame(host, stack) if framed else null
	if frame:
		tw.parallel().tween_property(frame, "scale", Vector2.ONE, POP_IN)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# Pop in, one piece at a time.
	for i in labels.size():
		var lbl := labels[i]
		var piece: Dictionary = pieces[i]
		var at := float(i) * STAGGER
		tw.parallel().tween_callback(_sfx.bind(sfx_pop, 1.0 + 0.12 * i)).set_delay(at)
		tw.parallel().tween_property(lbl, "scale", Vector2.ONE, POP_IN)\
			.set_delay(at).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		if piece.has("from"):
			# Roll the number once the piece is up, clicking on each change.
			var shown := [roundi(piece["from"])]
			tw.parallel().tween_method(func(v: float) -> void:
				lbl.text = _number_text(piece, v)
				if roundi(v) != shown[0]:
					shown[0] = roundi(v)
					_sfx(sfx_count),
				float(piece["from"]), float(piece["to"]), COUNT)\
				.set_delay(at + POP_IN).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		elif piece.has("text_from"):
			# Flip to the new text once the piece is up: squash flat, swap, spring back.
			var flip_at := at + POP_IN + COUNT * 0.5
			tw.parallel().tween_property(lbl, "scale:y", 0.0, FLIP)\
				.set_delay(flip_at).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_callback(func() -> void:
				lbl.text = str(piece.get("text", ""))
				lbl.reset_size()
				lbl.pivot_offset = lbl.get_combined_minimum_size() * 0.5
				_sfx(sfx_flip)).set_delay(flip_at + FLIP)
			tw.parallel().tween_property(lbl, "scale:y", 1.0, FLIP)\
				.set_delay(flip_at + FLIP).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# Hold, then pop out in order, each with a burst of sparks.
	var out_at := float(labels.size() - 1) * STAGGER + POP_IN + COUNT + HOLD
	for i in labels.size():
		var lbl := labels[i]
		var at := out_at + float(i) * STAGGER * 0.6
		tw.parallel().tween_callback(func() -> void:
			if is_instance_valid(lbl) and is_instance_valid(host):
				_spawn_sparks(host, lbl.get_global_rect().get_center(),
					lbl.get_theme_color("font_color"))
				_sfx(sfx_pop, 0.8)).set_delay(at)
		tw.parallel().tween_property(lbl, "scale", Vector2.ZERO, POP_OUT)\
			.set_delay(at).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	if frame:
		var frame_out := out_at + float(labels.size()) * STAGGER * 0.6
		tw.parallel().tween_property(frame, "scale", Vector2.ZERO, POP_OUT)\
			.set_delay(frame_out).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
		tw.chain().tween_callback(frame.queue_free)
	tw.chain().tween_callback(stack.queue_free)
	if on_done.is_valid():
		tw.tween_callback(on_done)


# Every string a piece can show, for sizing its line up front.
static func _texts_of(piece: Dictionary) -> Array[String]:
	if piece.has("from"):
		return [_number_text(piece, piece["from"]), _number_text(piece, piece["to"])]
	return [str(piece.get("text_from", "")), str(piece.get("text", ""))]


# The frame around a laid-out `stack`, added to `host` just under it and
# started at zero scale (play() pops it).
static func _build_frame(host: Control, stack: Control) -> Control:
	var box := make_frame()
	box.z_index = stack.z_index
	host.add_child(box)
	host.move_child(box, stack.get_index())
	box.size = (stack.size + FRAME_PAD * 2.0).round()
	box.global_position = (stack.global_position - FRAME_PAD).round()
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2.ZERO
	return box


## The near-opaque panel a framed message is shown in: it sits over whatever is
## underneath and has to hide it for the lines to read.
static func make_frame() -> Control:
	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiTheme.hud_panel_style()
	style.bg_color = Color(UiTheme.PANEL_BACKING_COLOR, 0.95)
	box.add_theme_stylebox_override("panel", style)
	return box


static func _sfx(id: StringName, pitch: float = 1.0) -> void:
	if not id.is_empty():
		SoundManager.play_sfx(id, pitch)


static func _number_text(piece: Dictionary, value: float) -> String:
	return "%s%d%s" % [piece.get("label", ""), roundi(value), piece.get("suffix", "")]


## Small one-shot spark burst where a piece popped out, in its colour.
static func _spawn_sparks(host: Control, global_pos: Vector2, color: Color) -> void:
	var fx := CPUParticles2D.new()
	fx.emitting = true
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = 16
	fx.lifetime = 0.5
	fx.direction = Vector2(0, -1)
	fx.spread = 180.0
	fx.initial_velocity_min = 50.0
	fx.initial_velocity_max = 140.0
	fx.gravity = Vector2(0, 220.0)
	fx.scale_amount_min = 2.0
	fx.scale_amount_max = 3.5
	fx.color = color
	fx.z_index = 200
	host.add_child(fx)
	fx.global_position = global_pos
	var done := fx.create_tween()
	done.tween_interval(fx.lifetime + 0.2)
	done.tween_callback(fx.queue_free)

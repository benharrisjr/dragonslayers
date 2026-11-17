class_name SweepText extends Label

## A sweeping callout ("Stage 2", "Revived!", "+2 ATK"): the text sweeps in
## from past the left edge to a
## centre point, blinks, holds, then either parks somewhere (the caller chains
## onto the returned tween) or fades out and frees itself (sweep_and_fade).
##
## Free-floating  no container  so position and scale tween about the text's
## own centre (pivot_offset). `centre` arguments are in the parent's local
## space; both hosts are full-rect controls, so that is screen space.

const SWEEP := 0.45
const FLASHES := 3
const FLASH_STEP := 0.08
const FLASH_ALPHA := 0.15
const HOLD := 0.6
const FADE := 0.3

var _tween: Tween = null


## A styled, hidden SweepText ready for sweep_to()/sweep_and_fade(). The caller
## add_child()s it wherever it should draw.
static func make(font_size: int, color: Color, outline: int = 6) -> SweepText:
	var lbl := SweepText.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	FontSizes.apply(lbl, font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", outline)
	lbl.visible = false
	return lbl


## Sweep `text` in from the left edge to `centre`, blink it, hold. Returns the
## (sequential) tween so the caller can append what happens next; the label
## stays put and visible until then. `sfx` (a SoundManager.play_sfx id) plays
## as the text lands.
func sweep_to(new_text: String, centre: Vector2, sfx: StringName = &"") -> Tween:
	stop()
	text = new_text
	reset_size()
	var half := size / 2.0
	pivot_offset = half
	scale = Vector2.ONE
	modulate = Color(1, 1, 1, 1)
	position = Vector2(-size.x, centre.y - half.y)
	visible = true

	_tween = create_tween()
	_tween.tween_property(self, "position", centre - half, SWEEP) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not sfx.is_empty():
		_tween.tween_callback(func() -> void: SoundManager.play_sfx(sfx))
	for _i in FLASHES:
		_tween.tween_property(self, "modulate:a", FLASH_ALPHA, FLASH_STEP)
		_tween.tween_property(self, "modulate:a", 1.0, FLASH_STEP)
	_tween.tween_interval(HOLD)
	return _tween


## One-shot form: sweep_to, then fade out and free the label.
func sweep_and_fade(new_text: String, centre: Vector2, sfx: StringName = &"") -> void:
	var tween := sweep_to(new_text, centre, sfx)
	tween.tween_property(self, "modulate:a", 0.0, FADE)
	tween.tween_callback(queue_free)


## Kill the running sequence (leaves the label wherever it got to).
func stop() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


## Kill the sequence and hide, ready for the next sweep.
func reset() -> void:
	stop()
	visible = false
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE

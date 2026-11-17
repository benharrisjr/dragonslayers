class_name DropIn
## Shared window entrance: the target starts off screen (below the viewport,
## or above it with `from_top`) and settles onto `rest_top` on a fast-out ease
## with no overshoot; closing slides it back out the way it came. Every window
## that slides in (options, shops, inventories, game over, a
## party column via open_curve) goes through here so they all move the same
## way. Callers own the returned Tween so they can kill it if the window is
## toggled mid-flight.

const OPEN_DURATION := 0.5
const CLOSE_DURATION := 0.55
## The entrance curve. QUINT lands hard with zero overshoot  the old elastic
## spring had far too much bounce for a panel.
const OPEN_TRANS := Tween.TRANS_QUINT
const OPEN_EASE := Tween.EASE_OUT
## Dimming backdrops fade rather than pop, so the window and its shadow arrive
## together instead of the screen darkening a beat before anything moves.
const BACKDROP_FADE := 0.3


## The motion is applied as an equal shift to offset_top/offset_bottom rather
## than through `position`: a window whose content is mid-rebuild (the party
## panel's tabs) can carry a transient, far-too-tall minimum size, which both
## pushes `position` off its anchors and would get baked into the offsets by
## a position write. Offsets stay true to the anchors, so the window keeps
## whatever size they settle on.
##
## `rest_top` is the offset_top the window rests at when open  its position.y
## for a control anchored to the top edge, which every drop-in window is.

static func open(target: Control, rest_top: float, from_top: bool = false) -> Tween:
	PadNav.set_closing(target, false)
	var d := rest_top - target.offset_top
	var bottom := target.offset_bottom + d
	var travel := _travel(target, rest_top, bottom, from_top)
	_shift(travel, target, rest_top, bottom)
	var t := target.create_tween()
	open_curve(t.tween_method(_shift.bind(target, rest_top, bottom), travel, 0.0, OPEN_DURATION))
	return t


static func close(target: Control, to_top: bool = false) -> Tween:
	# The pad's hand leaves a window the moment it starts sliding out.
	PadNav.set_closing(target, true)
	var top := target.offset_top
	var bottom := target.offset_bottom
	var travel := _travel(target, top, bottom, to_top)
	var t := target.create_tween()
	t.tween_method(_shift.bind(target, top, bottom), 0.0, travel, CLOSE_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	return t


## Apply the shared entrance curve to any tweener (PropertyTweener or
## MethodTweener  both take set_ease/set_trans) so a slide that can't go
## through open() still moves like every other window. Returns the tweener.
static func open_curve(tweener):
	return tweener.set_ease(OPEN_EASE).set_trans(OPEN_TRANS)


## Shift that puts the window fully off screen: past the bottom edge, or
## (`above`) past the top edge, for a window resting at top/bottom offsets.
static func _travel(target: Control, top: float, bottom: float, above: bool) -> float:
	if above:
		return -_anchored_bottom(target, bottom)
	return target.get_viewport_rect().size.y - _anchored_top(target, top)


## Top edge in parent space for a given offset_top, from the anchors alone.
static func _anchored_top(target: Control, offset_top: float) -> float:
	var parent := target.get_parent() as Control
	var parent_h := parent.size.y if parent else target.get_viewport_rect().size.y
	return target.anchor_top * parent_h + offset_top


## Bottom edge in parent space for a given offset_bottom, from the anchors alone.
static func _anchored_bottom(target: Control, offset_bottom: float) -> float:
	var parent := target.get_parent() as Control
	var parent_h := parent.size.y if parent else target.get_viewport_rect().size.y
	return target.anchor_bottom * parent_h + offset_bottom


static func _shift(y: float, target: Control, top: float, bottom: float) -> void:
	target.offset_top = top + y
	target.offset_bottom = bottom + y


## Fades a backdrop's alpha to `to` (1 = fully shown, 0 = gone) on `tween`,
## in parallel with whatever is already queued on it.
static func fade_backdrop(tween: Tween, backdrop: CanvasItem, to: float) -> void:
	if backdrop == null:
		return
	tween.parallel().tween_property(backdrop, "modulate:a", to, BACKDROP_FADE)

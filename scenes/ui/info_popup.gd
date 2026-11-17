class_name InfoPopup extends PanelContainer
## The project's one tooltip: a dark bordered card with a title, an optional
## BBCode description and an optional muted note above the title. Hover and tap
## both show this same card in the same spot, so a layout that works for the
## mouse works for touch too.
##
## Usage:
##   InfoPopup.attach(anchor, title, desc)                    # hover + tap
##   InfoPopup.attach(button, title, desc, {tap = false})     # hover only
##   InfoPopup.pin(anchor)            # toggle from your own tap handler
##   InfoPopup.clear(anchor)          # detach
##
## attach() is safe to call again whenever the content changes; an open card
## for that anchor rebuilds in place.
##
## Two modes, one card open at a time:
##  - Hover: the pointer rests on the anchor for HOVER_DELAY. Leaving the anchor
##    closes it. Hovering another anchor replaces whatever is open, pinned or not.
##  - Pinned: a tap on the anchor (or pin()). It stays until the next press
##    anywhere: on the card, on empty space, or on the anchor (which toggles it
##    closed). The press is never consumed, so it still does its normal job.
##
## The card is parented to the anchor's outermost Control (top_level, high z)
## so ScrollContainers can't clip it, and it ignores the mouse so taps pass
## through to whatever is underneath.

enum Place {
	SIDE,   ## right of the anchor, top-aligned; flips left when out of room
	ABOVE,  ## above, then below, then right, then left
	BELOW,  ## below, then above, then right, then left
}

const WIDTH := 360.0
const Z := 210
const GAP := 6.0
const MARGIN := 4.0
const HOVER_DELAY := 0.25
const TITLE_SIZE := 24
const BODY_SIZE := 20
const META := &"info_popup"

const TITLE_COLOR := UiTheme.TEXT_HEADING
const BODY_COLOR := UiTheme.TEXT
const NOTE_COLOR := UiTheme.TEXT_MUTED
## opts "dimmed": the card's contents greyed out (e.g. something not yet owned).
const DIMMED_MODULATE := Color(0.55, 0.56, 0.6)

static var _open: InfoPopup = null
## The anchor the pointer is resting on, if any: a pending hover only opens
## if the pointer is still here when HOVER_DELAY runs out.
static var _hover_anchor: Control = null

var anchor: Control = null
var pinned := false


## Registers (or updates) `anchor`'s card. `opts`:
##   note    muted line above the title
##   place   Place.SIDE (default) / ABOVE / BELOW
##   beside  Control to place the card next to instead of the anchor
##   bounds  Control whose rect the card is kept inside (default: the viewport)
##   extra   Callable returning a Control added under the description
##   tap     false for anchors whose click already does something: hover only
##   dimmed  true greys the card's contents
## An empty `title` detaches the card.
static func attach(anchor: Control, title: String, desc: String = "", opts: Dictionary = {}) -> void:
	if anchor == null:
		return
	if title.is_empty():
		clear(anchor)
		return
	var first := not anchor.has_meta(META)
	anchor.set_meta(META, {"title": title, "desc": desc, "opts": opts})
	if first:
		anchor.mouse_entered.connect(func() -> void: _on_anchor_entered(anchor))
		anchor.mouse_exited.connect(func() -> void: _on_anchor_exited(anchor))
		anchor.gui_input.connect(func(ev: InputEvent) -> void: _on_anchor_input(anchor, ev))
		anchor.tree_exiting.connect(func() -> void: _on_anchor_exiting(anchor))
	if opts.get("tap", true):
		anchor.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Content changed under an open card: rebuild it where it stands.
	if _is_open_for(anchor):
		_show(anchor, _open.pinned)


## Drops `anchor`'s card, closing it if open.
static func clear(anchor: Control) -> void:
	if anchor == null:
		return
	if _is_open_for(anchor):
		close_open()
	if anchor.has_meta(META):
		anchor.set_meta(META, null)
		anchor.remove_meta(META)


## Tap toggle for anchors that run their own press/drag logic (attached with
## tap = false): promotes this anchor's hover card to pinned, closes it if
## already pinned, or opens it pinned. Returns the open card, or null.
static func pin(anchor: Control) -> InfoPopup:
	if anchor == null or not is_instance_valid(anchor) or not anchor.has_meta(META):
		return null
	if _is_open_for(anchor):
		if _open.pinned:
			close_open()
			return null
		_open.pinned = true
		return _open
	return _show(anchor, true)


## One-shot form: attach the content, then toggle it pinned. `beside` overrides
## the rect the card is placed next to. An anchor that already has a card keeps
## its other options (placement, tap); a new one is attached hover-only, since
## its caller is evidently running its own tap handling.
static func toggle(anchor: Control, title: String, desc: String = "", note: String = "",
		beside: Control = null) -> InfoPopup:
	if anchor == null:
		return null
	var opts: Dictionary = {"tap": false}
	if anchor.has_meta(META):
		opts = ((anchor.get_meta(META) as Dictionary)["opts"] as Dictionary).duplicate()
	opts["note"] = note
	if beside != null:
		opts["beside"] = beside
	attach(anchor, title, desc, opts)
	return pin(anchor)


static func close_open() -> void:
	if _open != null and is_instance_valid(_open):
		_open.close()
	_open = null


## The anchor whose card is open (hover or pinned), or null.
static func open_anchor() -> Control:
	if _open == null or not is_instance_valid(_open) or not is_instance_valid(_open.anchor):
		return null
	return _open.anchor


static func is_open() -> bool:
	return _open != null and is_instance_valid(_open)


## Builds the card (not yet in the tree). `desc` is BBCode.
static func make(title: String, desc: String = "", note: String = "", extra: Control = null) -> InfoPopup:
	var panel := InfoPopup.new()
	panel.top_level = true
	panel.z_index = Z
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.add_theme_stylebox_override("panel", UiTheme.tooltip_style())

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	m.add_child(vb)

	# Dimmer than the description so it reads as an aside above the name.
	if not note.is_empty():
		vb.add_child(_line(note, BODY_SIZE, NOTE_COLOR))
	vb.add_child(_line(title, TITLE_SIZE, TITLE_COLOR))
	if not desc.is_empty():
		var body := RichTextLabel.new()
		body.bbcode_enabled = true
		body.fit_content = true
		body.scroll_active = false
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = WIDTH
		body.add_theme_font_size_override("normal_font_size", BODY_SIZE)
		body.add_theme_font_size_override("bold_font_size", BODY_SIZE)
		body.add_theme_color_override("default_color", BODY_COLOR)
		body.text = desc
		vb.add_child(body)
	if extra != null:
		vb.add_child(extra)

	_set_click_through(panel)
	return panel


static func _line(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = WIDTH
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


static func _is_open_for(anchor: Control) -> bool:
	return _open != null and is_instance_valid(_open) and _open.anchor == anchor


# Opens `anchor`'s card from its stored meta, replacing whatever is open.
static func _show(anchor: Control, as_pinned: bool) -> InfoPopup:
	close_open()
	if not is_instance_valid(anchor) or not anchor.is_inside_tree() or not anchor.has_meta(META):
		return null
	var info: Dictionary = anchor.get_meta(META)
	var opts: Dictionary = info["opts"]
	var extra: Control = null
	var extra_fn: Callable = opts.get("extra", Callable())
	if extra_fn.is_valid():
		extra = extra_fn.call()
	var panel := make(info["title"], info["desc"], opts.get("note", ""), extra)
	panel.anchor = anchor
	panel.pinned = as_pinned
	if opts.get("dimmed", false):
		# The contents only, so the card's background and border stay solid.
		(panel.get_child(0) as CanvasItem).modulate = DIMMED_MODULATE
	_host_for(anchor).add_child(panel)

	# Untyped reads: a stored beside/bounds node may since have been freed.
	var beside = opts.get("beside", null)
	var rect: Rect2 = (beside as Control).get_global_rect() if is_instance_valid(beside) \
		else anchor.get_global_rect()
	var bounds_ctl = opts.get("bounds", null)
	var bounds: Rect2 = (bounds_ctl as Control).get_global_rect() if is_instance_valid(bounds_ctl) \
		else anchor.get_viewport_rect()
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	panel.global_position = placed(sz, opts.get("place", Place.SIDE), rect, bounds)
	_open = panel
	return panel


## Where a card of size `sz` goes next to `anchor_rect` under `mode`, kept
## inside `bounds`. Hover and tap share this, so both land in the same spot.
static func placed(sz: Vector2, mode: Place, anchor_rect: Rect2, bounds: Rect2) -> Vector2:
	var lo := bounds.position + Vector2(MARGIN, MARGIN)
	var hi := bounds.end - Vector2(MARGIN, MARGIN)
	var right := Vector2(anchor_rect.end.x + GAP, anchor_rect.position.y)
	var left := Vector2(anchor_rect.position.x - GAP - sz.x, anchor_rect.position.y)
	var above := Vector2(anchor_rect.position.x, anchor_rect.position.y - GAP - sz.y)
	var below := Vector2(anchor_rect.position.x, anchor_rect.end.y + GAP)
	var fits_right := right.x + sz.x <= hi.x
	var pos: Vector2
	match mode:
		Place.SIDE:
			pos = right if fits_right else left
		_:
			var order := [above, below] if mode == Place.ABOVE else [below, above]
			pos = order[0]
			var first_fits: bool = order[0].y >= lo.y and order[0].y + sz.y <= hi.y
			var second_fits: bool = order[1].y >= lo.y and order[1].y + sz.y <= hi.y
			if first_fits:
				pos = order[0]
			elif second_fits:
				pos = order[1]
			elif fits_right:
				pos = right
			elif left.x >= lo.x:
				pos = left
	pos.x = clampf(pos.x, lo.x, maxf(lo.x, hi.x - sz.x))
	pos.y = clampf(pos.y, lo.y, maxf(lo.y, hi.y - sz.y))
	return pos


# --- anchor signal handlers -------------------------------------------------

static func _on_anchor_entered(anchor: Control) -> void:
	_hover_anchor = anchor
	if _is_open_for(anchor) or not anchor.is_inside_tree():
		return
	anchor.get_tree().create_timer(HOVER_DELAY).timeout.connect(func() -> void:
		if _hover_anchor != anchor or not is_instance_valid(anchor) or _is_open_for(anchor):
			return
		if not anchor.is_visible_in_tree() or not anchor.has_meta(META):
			return
		# A held button means a drag is under way: no cards over
		# the drop targets.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return
		_show(anchor, false))


static func _on_anchor_exited(anchor: Control) -> void:
	if _hover_anchor == anchor:
		_hover_anchor = null
	if _is_open_for(anchor) and not _open.pinned:
		close_open()


static func _on_anchor_input(anchor: Control, ev: InputEvent) -> void:
	if not anchor.has_meta(META):
		return
	var info: Dictionary = anchor.get_meta(META)
	if not (info["opts"] as Dictionary).get("tap", true):
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		pin(anchor)


static func _on_anchor_exiting(anchor: Control) -> void:
	if _hover_anchor == anchor:
		_hover_anchor = null
	if _is_open_for(anchor):
		close_open()


# --- card lifetime ----------------------------------------------------------

func close() -> void:
	if _open == self:
		_open = null
	# Hide rather than remove_child: close() can run from the anchor's
	# tree_exiting, while the shared parent is busy removing children. The card
	# is top_level, so lingering hidden until the free takes no layout space.
	hide()
	set_process(false)
	set_process_input(false)
	queue_free()


# The anchor can vanish without a signal this card hears (an ancestor hidden,
# a screen swapped out), so check each frame.
func _process(_delta: float) -> void:
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_visible_in_tree():
		close()


## A pinned card closes on any press. A press on its own anchor is left to the
## anchor's tap handler, which toggles it closed. Never consumes the event.
func _input(event: InputEvent) -> void:
	if not pinned:
		return
	var p: Vector2
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		p = event.position
	elif event is InputEventScreenTouch and event.pressed:
		p = event.position
	else:
		return
	if anchor != null and is_instance_valid(anchor) \
			and anchor.get_global_rect().has_point(_canvas_point(p)):
		return
	close()


# Viewport event position → the anchor's canvas coordinates (they differ when
# the anchor lives under a CanvasLayer with its own transform).
func _canvas_point(p: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * p


## The outermost Control above `anchor`  where the card lives so no
## ScrollContainer between them can clip it.
static func _host_for(anchor: Control) -> Control:
	var host := anchor
	var p := anchor.get_parent()
	while p is Control:
		host = p
		p = p.get_parent()
	return host


# The card and its subtree ignore the mouse so taps pass straight through to
# whatever is behind it (tapping a covered cell opens its card instead).
static func _set_click_through(root: Control) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in root.get_children():
		if c is Control:
			_set_click_through(c)

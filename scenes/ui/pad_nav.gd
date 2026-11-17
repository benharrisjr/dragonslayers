class_name PadNav
extends RefCounted
## Snap navigation for the pad's pointing hand: which window the D-pad is
## driving, what in it can be pointed at, and which of those lies in a given
## direction. PadCursor owns the hand and does the clicking (synthesized mouse
## events at the target's centre), so every screen keeps its mouse code.
##
## A screen or window opts in by joining SCOPE_GROUP. The topmost visible scope
## (highest CanvasLayer, then latest in the tree, i.e. drawn last) is the active
## one; with none visible (gameplay with no window up) the D-pad fires whatever
## the game bound to it.
##
## Targets inside the active scope: enabled BaseButtons, Sliders, and any Control
## in TARGET_GROUP (custom gui_input controls such as inventory slots).
## SKIP_GROUP opts a control out. While an item is held, the targets are instead
## every visible DROP_GROUP control anywhere (drop zones can live outside the
## window that started the drag).

const SCOPE_GROUP := &"pad_scope"
const TARGET_GROUP := &"pad_target"
const DROP_GROUP := &"pad_drop"
const SKIP_GROUP := &"pad_skip"
## A scope can pull controls that live outside it (HUD slots beside a window)
## into its targets: put them in a group of the game's choosing and set this
## meta on the scope to that group's name.
const EXTRA_GROUP_META := &"pad_extra_group"

## How far off the pressed direction a target may sit (cosine of ~60°).
const _CONE_COS := 0.5
## Sideways offset costs this much more than distance along the direction, so
## a press prefers the target straight ahead over a nearer diagonal one.
const _PERP_WEIGHT := 2.0


const _CLOSING_META := &"pad_closing"


## The scope the D-pad drives right now, or null. `skip` leaves one scope out
## (the next one down, under a spotlight card).
static func active_scope(tree: SceneTree, skip: Control = null) -> Control:
	var best: Control = null
	var best_layer := -2147483648
	for node in tree.get_nodes_in_group(SCOPE_GROUP):
		var c := node as Control
		if c == null or c == skip or not _shown(c) or c.get_meta(_CLOSING_META, false):
			continue
		var layer := _layer_of(c)
		if best == null or layer > best_layer \
				or (layer == best_layer and c.is_greater_than(best)):
			best = c
			best_layer = layer
	return best


## Mark the scope that `window` belongs to (itself or its nearest scope
## ancestor) as sliding shut, so it stops counting as a scope at once rather
## than when its close animation ends. DropIn calls this on close and open.
static func set_closing(window: Node, closing: bool) -> void:
	var n := window
	while n != null:
		if n.is_in_group(SCOPE_GROUP):
			n.set_meta(_CLOSING_META, closing)
			return
		n = n.get_parent()


## Everything the hand can point at: the drop zones while holding, else the
## active scope's targets.
static func targets(tree: SceneTree, holding: bool) -> Array[Control]:
	var out: Array[Control] = []
	if holding:
		for node in tree.get_nodes_in_group(DROP_GROUP):
			var c := node as Control
			# Drop zones needn't take the mouse (an empty slot may ignore it).
			if c != null and _pointable(c, false) and DragState.accepts_drop(c):
				out.append(c)
		return out
	var scope := active_scope(tree)
	if scope == null:
		return out
	_scope_targets(tree, scope, out)
	# A spotlight overlay (a scope with a pad_hole_rects() method, e.g. a tutorial
	# card) lets clicks through its holes, so the hand also reaches whatever the
	# scope underneath has inside them, or, with no window under it, whatever
	# the overlay's own screen does.
	if scope.has_method(&"pad_hole_rects"):
		var holes: Array = scope.call(&"pad_hole_rects")
		if not holes.is_empty():
			var below: Array[Control] = []
			var under := active_scope(tree, scope)
			if under != null:
				_scope_targets(tree, under, below)
			elif scope.get_parent() != null:
				_collect(scope.get_parent(), below)
			for c in below:
				var centre := c.get_global_rect().get_center()
				for h: Rect2 in holes:
					if h.has_point(centre):
						if not out.has(c):
							out.append(c)
						break
	return out


static func _scope_targets(tree: SceneTree, scope: Control, out: Array[Control]) -> void:
	_collect(scope, out)
	var extra: StringName = scope.get_meta(EXTRA_GROUP_META, &"")
	if extra != &"":
		for node in tree.get_nodes_in_group(extra):
			var c := node as Control
			if c != null and not out.has(c) and _pointable(c):
				out.append(c)


## Whether `c` can still be pointed at (it may have been hidden or freed since).
static func is_target_live(c: Control) -> bool:
	return is_instance_valid(c) and c.is_inside_tree() and not c.is_queued_for_deletion() \
		and _pointable(c, not c.is_in_group(DROP_GROUP))


## The best target from `from_rect` in direction `dir` (a unit D-pad vector), or
## null. Targets in the "beam"  overlapping `from_rect` across the direction of
## travel, i.e. the same row for left/right or the same column for up/down,
## win over everything else, however much nearer: so ◄ goes to ► across a wide
## panel instead of dropping to the closer button in the row below. With
## nothing in the beam or the cone, the best target anywhere on that side is
## taken, so a press never dead-ends while something lies that way.
##
## Pass the current target as `exclude`. While it sits in a ScrollContainer, the
## rest of that list comes first: a target scrolled out of view still has its
## real (off-screen) position, which can lie past something pinned outside the
## list, so without this the hand would jump to the pinned control before
## walking the entries still hidden beyond it.
static func pick(from_rect: Rect2, dir: Vector2, cands: Array[Control], exclude: Control = null) -> Control:
	# A sideways press from outside the preferred set lands on it first when
	# any of it lies that way; once inside it, normal geometry takes over.
	if dir.y == 0.0 and not _is_preferred(exclude):
		var preferred: Array[Control] = []
		for c in cands:
			if _is_preferred(c):
				preferred.append(c)
		if not preferred.is_empty():
			var first := _pick(from_rect, dir, preferred, exclude)
			if first != null:
				return first
	var scroll := _scroll_of(exclude) if exclude != null else null
	if scroll != null:
		var inner: Array[Control] = []
		for c in cands:
			if _scroll_of(c) == scroll:
				inner.append(c)
		var next := _pick(from_rect, dir, inner, exclude)
		if next != null:
			return next
	return _pick(from_rect, dir, cands, exclude)


static func _pick(from_rect: Rect2, dir: Vector2, cands: Array[Control], exclude: Control) -> Control:
	var from := from_rect.get_center()
	var best: Control = null
	var best_score := INF
	var best_in_beam := false
	var fallback: Control = null
	var fallback_score := INF
	for c in cands:
		if c == exclude:
			continue
		var rect := beam_rect(c)
		# Aim at the nearest point of the rect, not its centre, so a wide button
		# beside a narrow one still counts as "straight across".
		var to := rect.get_center() - from
		var edge := Vector2(clampf(from.x, rect.position.x, rect.end.x),
			clampf(from.y, rect.position.y, rect.end.y)) - from
		if edge.length_squared() > 0.0:
			# A row-beam target stands for its whole row: no centre pull, or a
			# far end of the row would lose to a nearer-centred button past it.
			to = edge if rect != nav_rect(c) else to.lerp(edge, 0.5)
		var along := to.dot(dir)
		if along <= 1.0:
			continue
		var in_beam := _overlaps_across(from_rect, rect, dir)
		var perp := absf(to.dot(Vector2(-dir.y, dir.x)))
		var score := along + perp * _PERP_WEIGHT
		if not in_beam and along / to.length() < _CONE_COS:
			if score < fallback_score:
				fallback_score = score
				fallback = c
			continue
		if (in_beam and not best_in_beam) or (in_beam == best_in_beam and score < best_score):
			best_score = score
			best = c
			best_in_beam = in_beam
	return best if best != null else fallback


## Marks a target (meta true) that a left/right press from any target outside
## the marked set goes to before anything else on that side, even out of the
## beam. For content that should come between two columns of navigation.
const PREFER_META := &"pad_prefer_sideways"


static func _is_preferred(c: Control) -> bool:
	return c != null and c.get_meta(PREFER_META, false)


## Whether `a` and `b` share any span across `dir`: vertical overlap for a
## horizontal move, horizontal overlap for a vertical one.
static func _overlaps_across(a: Rect2, b: Rect2, dir: Vector2) -> bool:
	if dir.y == 0.0:
		return a.position.y < b.end.y and b.position.y < a.end.y
	return a.position.x < b.end.x and b.position.x < a.end.x


## Where `c` sits for navigation and where the hand points. A slider or
## checkbox laid out after its label in a row (Options) stands for the whole
## row, so rows line up as one column and the hand sits before the label rather
## than on it. Clicks still land on the control itself.
static func nav_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	if (c is Slider or c is CheckBox) and c.get_parent() is HBoxContainer:
		var row := (c.get_parent() as Control).get_global_rect()
		return Rect2(row.position.x, r.position.y, row.size.x, r.size.y)
	return r


## A lone button centred in a row can sit in nobody's beam (between a pair of
## buttons above and another pair below), so a screen can
## mark it with ROW_BEAM_META to navigate as its whole parent row. The mark may
## sit on an ancestor of the target (a PanelButton, whose inner Button is what
## the hand points at). Only the beam search uses this; the hand still points
## at nav_rect.
const ROW_BEAM_META := &"pad_row_beam"


static func beam_rect(c: Control) -> Rect2:
	var r := nav_rect(c)
	var n: Node = c
	while n is Control and not n.is_in_group(SCOPE_GROUP):
		if n.get_meta(ROW_BEAM_META, false):
			var row := n.get_parent() as Control
			if row == null:
				break
			var rr := row.get_global_rect()
			return Rect2(rr.position.x, r.position.y, rr.size.x, r.size.y)
		n = n.get_parent()
	return r


## Where the hand should land first in a freshly opened scope: under a
## spotlight card that asks for its spotlit control (an action card that takes
## the pad), that control; else the control the screen already seeded focus on
## (SelectionReticle) when it's a target; else the top-left-most target.
static func seed_target(viewport: Viewport, cands: Array[Control]) -> Control:
	if cands.is_empty():
		return null
	var scope := active_scope(viewport.get_tree())
	if scope != null and scope.has_method(&"pad_prefers_holes") and scope.call(&"pad_prefers_holes"):
		var holes: Array = scope.call(&"pad_hole_rects")
		for c in cands:
			if scope.is_ancestor_of(c):
				continue
			var centre := c.get_global_rect().get_center()
			for h: Rect2 in holes:
				if h.has_point(centre):
					return c
	var focus := viewport.gui_get_focus_owner()
	if focus != null:
		for c in cands:
			if c == focus or c.is_ancestor_of(focus):
				return c
	var best: Control = cands[0]
	for c in cands:
		var p := c.get_global_rect().position
		var b := best.get_global_rect().position
		if p.y < b.y - 4.0 or (absf(p.y - b.y) <= 4.0 and p.x < b.x):
			best = c
	return best


## Scroll `c` into view inside its nearest ScrollContainer, if it has one.
static func reveal(c: Control) -> void:
	var scroll := _scroll_of(c)
	if scroll != null:
		scroll.ensure_control_visible(c)


## Whether `c` sits in a ScrollContainer that has scrolled its centre out of
## view (behind the window's header or footer).
static func scrolled_out(c: Control) -> bool:
	var scroll := _scroll_of(c)
	return scroll != null and not scroll.get_global_rect().has_point(c.get_global_rect().get_center())


## `rect` (one of `c`'s rects) pulled inside the visible area of `c`'s
## ScrollContainer, keeping its size: where the hand parks when the list has
## scrolled its target out of view and nothing else in the list is showing, so
## it waits at the list's edge instead of trailing the target off the window.
## Unchanged when `c` isn't in a list or is still in view.
static func park_in_scroll(c: Control, rect: Rect2) -> Rect2:
	if not scrolled_out(c):
		return rect
	var view := _scroll_of(c).get_global_rect()
	var p := rect.position
	p.x = clampf(p.x, view.position.x, maxf(view.position.x, view.end.x - rect.size.x))
	p.y = clampf(p.y, view.position.y, maxf(view.position.y, view.end.y - rect.size.y))
	return Rect2(p, rect.size)


## The target in `c`'s ScrollContainer still in view and nearest to `c`, or null:
## where the hand moves when the list is scrolled out from under it, so it stays
## on the list (and the right stick keeps scrolling it) instead of trailing its
## old target over the header or footer buttons.
static func nearest_in_view(c: Control, cands: Array[Control]) -> Control:
	var scroll := _scroll_of(c)
	if scroll == null:
		return null
	var at := c.get_global_rect().get_center()
	var best: Control = null
	var best_d := INF
	for o in cands:
		if o == c or _scroll_of(o) != scroll or scrolled_out(o):
			continue
		var d := o.get_global_rect().get_center().distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = o
	return best


## The first pointable target under `root` in tree order (a list's first
## entry, built before anything beside it), or null.
static func first_target_in(root: Node) -> Control:
	var out: Array[Control] = []
	_collect(root, out)
	return out[0] if not out.is_empty() else null


static func _collect(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		var c := child as Control
		if c == null:
			# CanvasLayers / Node2Ds inside a window can still hold controls.
			if child is CanvasItem and not (child as CanvasItem).visible:
				continue
			_collect(child, out)
			continue
		if not c.visible:
			continue
		if _is_target(c) and _pointable(c):
			out.append(c)
		_collect(c, out)


static func _is_target(c: Control) -> bool:
	if c.is_in_group(SKIP_GROUP):
		return false
	if c.is_in_group(TARGET_GROUP):
		return true
	if c is BaseButton:
		return not (c as BaseButton).disabled
	return c is Slider


static func _pointable(c: Control, need_mouse := true) -> bool:
	if c.is_queued_for_deletion() or not _shown(c):
		return false
	if need_mouse and c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	var rect := c.get_global_rect()
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return false
	# Faded out (a lifted drag slot hidden at alpha 0; ghost spacers).
	if c.self_modulate.a <= 0.01:
		return false
	var n: Node = c
	while n is CanvasItem:
		if (n as CanvasItem).modulate.a <= 0.01:
			return false
		n = n.get_parent()
	# Off screen counts only when a ScrollContainer can bring it back.
	if not c.get_viewport_rect().intersects(rect) and not _in_scroll(c):
		return false
	return true


static func _shown(c: CanvasItem) -> bool:
	if not c.is_visible_in_tree():
		return false
	var layer := c.get_canvas_layer_node()
	return layer == null or layer.visible


static func _layer_of(c: CanvasItem) -> int:
	var layer := c.get_canvas_layer_node()
	return layer.layer if layer != null else 0


static func _in_scroll(c: Control) -> bool:
	return _scroll_of(c) != null


## The nearest ScrollContainer `c` sits in, or null.
static func _scroll_of(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p as ScrollContainer
		p = p.get_parent()
	return null

extends Node

## Full-screen curtain transitions: an animated black overlay that covers and
## then reveals the screen, for swapping what is on screen without a scene
## change (entering a level, opening a shop, a room-to-room cut).
##
## Usage:
##   await ScreenTransitions.cover()        # darken screen
##   ...mutate state...                     # swap UI here while hidden
##   await ScreenTransitions.reveal()       # un-darken
##
##   # Or in one shot:
##   await ScreenTransitions.swap(func(): _do_state_swap())
##
##   # A different curtain, and an iris closing on a point:
##   await ScreenTransitions.cover(ScreenTransitions.Type.IRIS, player_screen_pos)
##
## Sits on a CanvasLayer above SceneManager's fade. For a full scene change use
## SceneManager.change_scene (and clear() any curtain still up).

enum Type { TILES, WEDGES, IRIS, SPLIT }

const TILE_COLS := 16
const TILE_ROWS := 9
const TILE_DURATION := 0.32
const TILE_STAGGER := 0.012

## Wedge curtain: four triangles, one per screen edge, whose apexes meet at
## screen centre. Together they tile the viewport exactly.
const WEDGE_DURATION := 0.35
## Grown past the screen edges and the centre apex so no seam shows where the
## four meet  Polygon2D edges land on fractional pixels at odd resolutions.
const WEDGE_PAD := 2.0

## Iris curtain: a circle wipe closing on the screen centre (the shader in
## iris_wipe.gdshader; radius runs from the corner distance down to 0).
## cover()/reveal()'s "no focus point" default: the iris centres on the view.
const NO_FOCUS := Vector2(-1.0, -1.0)
const IRIS_DURATION := 0.45
const IRIS_SHADER := preload("res://autoloads/iris_wipe.gdshader")
## Split curtain: the screen cut along the top-left → bottom-right diagonal
## into two black halves that slide apart (or back together) along it.
const SPLIT_DURATION := 0.4

## Upper bound on how long a curtain may be awaited (see _await_tweens).
const AWAIT_TIMEOUT_MS := 5000
## Print each cover / reveal to the output log. Debug builds only.
const TRACE := false

var _canvas: CanvasLayer
var _root: Control
## Full-rect black rect wearing the iris shader; shown only while an IRIS
## curtain is on screen.
var _iris_rect: ColorRect
var _iris_material: ShaderMaterial
var _tile_layer: Control
var _wedge_layer: Control
var _split_layer: Control
var _busy: bool = false


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 101  # one above SceneManager's fade layer
	get_tree().root.add_child(_canvas)

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	_canvas.add_child(_root)

	# The iris sits under the other curtains, so one of them can be built over a
	# closed iris and take over from it without a visible seam.
	_iris_material = ShaderMaterial.new()
	_iris_material.shader = IRIS_SHADER
	_iris_rect = ColorRect.new()
	_iris_rect.color = Color.BLACK
	_iris_rect.material = _iris_material
	_iris_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_iris_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_iris_rect.visible = false
	_root.add_child(_iris_rect)

	# One container per curtain style, so rebuilding one never frees another's
	# nodes.
	_tile_layer = _make_layer()
	_wedge_layer = _make_layer()
	_split_layer = _make_layer()


func _make_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(layer)
	return layer


## Animate the overlay onto the screen. await this before swapping visible state.
## `focus` (canvas pixels) is where an IRIS closes to; the default is the
## screen centre. Other curtains ignore it.
func cover(type: Type = Type.TILES, focus: Vector2 = NO_FOCUS) -> void:
	if _busy:
		_trace("cover(%s) REFUSED: busy" % Type.keys()[type])
		return
	_busy = true
	_trace("cover(%s)" % Type.keys()[type])
	match type:
		Type.TILES:
			await _play_tiles(true)
		Type.WEDGES:
			await _play_wedges(true)
		Type.IRIS:
			await _play_iris(true, focus)
		Type.SPLIT:
			await _play_split(true)
	_busy = false


## True while any curtain is on screen (covering, covered, or still opening).
func is_covering() -> bool:
	return _root != null and _root.visible


## Animate the overlay away. `focus` as for cover().
func reveal(type: Type = Type.TILES, focus: Vector2 = NO_FOCUS) -> void:
	if _busy:
		_trace("reveal(%s) REFUSED: busy" % Type.keys()[type])
		return
	_busy = true
	_trace("reveal(%s)" % Type.keys()[type])
	match type:
		Type.TILES:
			await _play_tiles(false)
		Type.WEDGES:
			await _play_wedges(false)
		Type.IRIS:
			await _play_iris(false, focus)
		Type.SPLIT:
			await _play_split(false)
	_busy = false


## One-shot: cover, run mid(), reveal. mid() is invoked while the screen is
## fully covered, so any visible state change is hidden from the player.
func swap(mid: Callable, type: Type = Type.TILES) -> void:
	await cover(type)
	if mid.is_valid():
		mid.call()
	await reveal(type)


## Drops the overlay on the screen instantly (no animation). Used when a scene
## needs to come up already-covered so the first reveal looks clean.
func snap_cover(type: Type = Type.TILES) -> void:
	if _root == null:
		await get_tree().process_frame
	match type:
		Type.TILES:
			_rebuild_tiles(Vector2.ONE)
		Type.WEDGES:
			_rebuild_wedges(false)
		Type.IRIS:
			_set_iris(0.0)
		Type.SPLIT:
			_rebuild_split(false)
	_root.visible = true


func _trace(stage: String) -> void:
	if TRACE and OS.is_debug_build():
		print("[ScreenTransitions] ", stage)


## Drop the whole overlay instantly, mid-transition if need be. Used when the
## thing behind the curtain is going away entirely (a SceneManager change, which
## brings its own fade) so there is nothing worth animating a reveal over.
func clear() -> void:
	if _root == null:
		return
	_trace("clear")
	_clear_curtains()
	_iris_rect.visible = false
	_root.visible = false
	_busy = false


# ─── Curtain builders ────────────────────────────────────────────────────────

func _play_tiles(covering: bool) -> void:
	var start := Vector2.ZERO if covering else Vector2.ONE
	var ending := Vector2.ONE if covering else Vector2.ZERO
	_rebuild_tiles(start)
	_root.visible = true

	var tiles := _tile_layer.get_children()
	var max_diag := (TILE_COLS - 1) + (TILE_ROWS - 1)
	var tweens: Array[Tween] = []
	for i in tiles.size():
		var t: Control = tiles[i]
		var col := i / TILE_ROWS
		var row := i % TILE_ROWS
		var diag := col + row
		var delay := (diag if covering else max_diag - diag) * TILE_STAGGER
		var tween := create_tween()
		if delay > 0.0:
			tween.tween_interval(delay)
		tween.tween_property(t, "scale", ending, TILE_DURATION).set_trans(Tween.TRANS_QUART)
		tweens.append(tween)

	await _await_tweens(tweens)
	if not covering:
		_root.visible = false


## Slide the four wedges in from their own edges (covering) or back out to them.
## Cubic ease-in on the way in reads as a slam; ease-out on the way back snaps
## them off the screen.
func _play_wedges(covering: bool) -> void:
	_rebuild_wedges(covering)
	_root.visible = true

	var easing := Tween.EASE_IN if covering else Tween.EASE_OUT
	var tweens: Array[Tween] = []
	for w in _wedge_layer.get_children():
		var target: Vector2 = Vector2.ZERO if covering else w.get_meta(&"home")
		var tween := create_tween()
		tween.tween_property(w, "position", target, WEDGE_DURATION) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(easing)
		tweens.append(tween)

	await _await_tweens(tweens)
	if not covering:
		_root.visible = false


## Circle wipe. Covering shrinks the open circle from the corner distance to
## nothing; revealing grows it back out. The rect stays up (black) after a
## cover so a following curtain can take over from it. `focus` moves the
## circle's centre off the middle of the screen (onto the player, a door); the
## starting radius grows to reach the farthest corner from it.
func _play_iris(covering: bool, focus: Vector2 = NO_FOCUS) -> void:
	var view := get_viewport().get_visible_rect().size
	var center := _iris_center(view, focus)
	var full := 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(view.x, 0.0), Vector2(0.0, view.y), view]:
		full = maxf(full, center.distance_to(corner))
	_set_iris(full if covering else 0.0, focus)
	_root.visible = true

	var tween := create_tween()
	tween.tween_property(_iris_material, "shader_parameter/radius",
			0.0 if covering else full, IRIS_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN if covering else Tween.EASE_OUT)
	var tweens: Array[Tween] = [tween]
	await _await_tweens(tweens)
	if not covering:
		_iris_rect.visible = false
		_root.visible = false


func _iris_center(view: Vector2, focus: Vector2) -> Vector2:
	if focus == NO_FOCUS:
		return view / 2.0
	return focus.clamp(Vector2.ZERO, view)


## Put the iris on screen at `radius` (0 = fully black), centred on the view
## or on `focus`.
func _set_iris(radius: float, focus: Vector2 = NO_FOCUS) -> void:
	var view := get_viewport().get_visible_rect().size
	_iris_material.set_shader_parameter("size", view)
	_iris_material.set_shader_parameter("center", _iris_center(view, focus))
	_iris_material.set_shader_parameter("radius", radius)
	_iris_rect.visible = true


## Slide the two diagonal halves together (covering) or apart along the
## diagonal's normal. Same easing story as the wedges. `keep_root` leaves the
## overlay on screen after a reveal, for when the split opens onto something
## else the overlay holds.
func _play_split(covering: bool, keep_root: bool = false) -> void:
	_rebuild_split(covering)
	_root.visible = true

	var easing := Tween.EASE_IN if covering else Tween.EASE_OUT
	var tweens: Array[Tween] = []
	for half in _split_layer.get_children():
		var target: Vector2 = Vector2.ZERO if covering else half.get_meta(&"home")
		var tween := create_tween()
		tween.tween_property(half, "position", target, SPLIT_DURATION) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(easing)
		tweens.append(tween)

	await _await_tweens(tweens)
	if not covering and not keep_root:
		_root.visible = false


## Block until every tween in `tweens` has actually applied its final value.
## A parallel create_timer() of the same nominal length is NOT equivalent: it
## lands on the same frame as the tweens but can fire first, so the caller would
## resume with the curtain a hair short of closed and hairline seams on screen.
func _await_tweens(tweens: Array[Tween]) -> void:
	if tweens.is_empty():
		return
	# GDScript lambdas capture locals by value, so the counter has to live in a
	# reference type for the callback's decrement to be visible out here.
	var pending := [tweens.size()]
	for tween in tweens:
		tween.finished.connect(func() -> void: pending[0] -= 1, CONNECT_ONE_SHOT)
	# A tween whose target gets freed mid-flight stops without ever emitting
	# finished, so cap the wait rather than stranding the caller's coroutine.
	var deadline := Time.get_ticks_msec() + AWAIT_TIMEOUT_MS
	while pending[0] > 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	# One more frame so the last value written this frame is drawn before a
	# caller mutates whatever is behind the curtain.
	await get_tree().process_frame


func _clear_curtains() -> void:
	for child in _tile_layer.get_children():
		child.queue_free()
	for child in _wedge_layer.get_children():
		child.queue_free()
	for child in _split_layer.get_children():
		child.queue_free()


func _rebuild_tiles(initial_scale: Vector2) -> void:
	_clear_curtains()
	var size := get_viewport().get_visible_rect().size
	var tw := size.x / float(TILE_COLS)
	var th := size.y / float(TILE_ROWS)
	for col in TILE_COLS:
		for row in TILE_ROWS:
			var t := ColorRect.new()
			t.color = Color.BLACK
			t.position = Vector2(col * tw, row * th)
			t.size = Vector2(tw, th)
			t.pivot_offset = Vector2(tw / 2.0, th / 2.0)
			t.scale = initial_scale
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tile_layer.add_child(t)


## Build the four wedges against the live viewport rect. Each is stored with its
## fully-retracted offscreen position in the "home" meta, so _play_wedges can
## tween either way without recomputing the geometry.
## `start_offscreen` places them at home (a cover about to sweep in); otherwise
## they start assembled at the centre (a reveal about to sweep out).
func _rebuild_wedges(start_offscreen: bool) -> void:
	_clear_curtains()
	var size := get_viewport().get_visible_rect().size
	var w := size.x
	var h := size.y
	var p := WEDGE_PAD
	var hx := w / 2.0
	var hy := h / 2.0

	# points, home (offscreen resting position)
	var specs := [
		[PackedVector2Array([Vector2(-p, -p), Vector2(w + p, -p), Vector2(hx, hy + p)]),
			Vector2(0.0, -(hy + p))],                                        # top
		[PackedVector2Array([Vector2(-p, h + p), Vector2(w + p, h + p), Vector2(hx, hy - p)]),
			Vector2(0.0, hy + p)],                                           # bottom
		[PackedVector2Array([Vector2(-p, -p), Vector2(-p, h + p), Vector2(hx + p, hy)]),
			Vector2(-(hx + p), 0.0)],                                        # left
		[PackedVector2Array([Vector2(w + p, -p), Vector2(w + p, h + p), Vector2(hx - p, hy)]),
			Vector2(hx + p, 0.0)],                                           # right
	]
	for spec in specs:
		var wedge := Polygon2D.new()
		wedge.polygon = spec[0]
		wedge.color = Color.BLACK
		wedge.set_meta(&"home", spec[1])
		wedge.position = spec[1] if start_offscreen else Vector2.ZERO
		_wedge_layer.add_child(wedge)


## The two halves of the split curtain: the screen cut along the top-left →
## bottom-right diagonal. Each half's "home" moves it a full screen width and
## height away, perpendicular-ish to the cut, which clears the viewport
## entirely. Same shape as _rebuild_wedges, but on _split_layer.
func _rebuild_split(start_offscreen: bool) -> void:
	_clear_curtains()
	var size := get_viewport().get_visible_rect().size
	var w := size.x
	var h := size.y
	var p := WEDGE_PAD

	var specs := [
		[PackedVector2Array([Vector2(-p, -p), Vector2(w + p, -p), Vector2(w + p, h + p)]),
			Vector2(w, -h)],                                                  # upper-right
		[PackedVector2Array([Vector2(-p, -p), Vector2(w + p, h + p), Vector2(-p, h + p)]),
			Vector2(-w, h)],                                                  # lower-left
	]
	for spec in specs:
		var half := Polygon2D.new()
		half.polygon = spec[0]
		half.color = Color.BLACK
		half.set_meta(&"home", spec[1])
		half.position = spec[1] if start_offscreen else Vector2.ZERO
		_split_layer.add_child(half)

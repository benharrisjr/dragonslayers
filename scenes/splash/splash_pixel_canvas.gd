class_name SplashPixelCanvas
extends Control

const NEON_GREEN    := Color(0.05, 1.0, 0.28)
const BASE_DURATION := 2.0   # baseline travel time per pixel (seconds)
const STAGGER       := 1.0   # max random start-delay spread (seconds)

# Each element: {start, final, delay, duration, size}
var blocks: Array = []
var elapsed: float = 0.0
var running: bool = false

var _total_duration: float = 0.0   # computed by start()

# collapse(): every block spirals into `_sink`, shrinking and dimming on the
# way  the logo being drawn into the void that opens behind it.
var _collapsing := false
var _collapse_elapsed := 0.0
var _collapse_total := 0.0
var _sink := Vector2.ZERO
var _collapse_turn := 0.0

signal done
signal collapsed


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)


## Call instead of setting running=true so _total_duration is computed first.
func start() -> void:
	_total_duration = 0.0
	for b: Dictionary in blocks:
		_total_duration = maxf(_total_duration, (b["delay"] as float) + (b["duration"] as float))
	running = true


## Pull every block into `sink` over about `duration` seconds, outermost
## blocks last. Each turns `turn` radians on the way in (negative = the way
## the void spins). Emits `collapsed` when the last block is gone.
func collapse(sink: Vector2, duration: float, turn: float = -2.4) -> void:
	_sink = sink
	_collapse_turn = turn
	var far := 1.0
	for b: Dictionary in blocks:
		far = maxf(far, ((b["final"] as Vector2) - sink).length())
	_collapse_total = 0.0
	for b: Dictionary in blocks:
		var dist := ((b["final"] as Vector2) - sink).length() / far
		b["c_delay"] = dist * duration * 0.35 + randf() * duration * 0.15
		b["c_dur"] = duration * (0.45 + randf() * 0.1)
		_collapse_total = maxf(_collapse_total, b["c_delay"] + b["c_dur"])
	_collapse_elapsed = 0.0
	_collapsing = true


func _process(delta: float) -> void:
	if _collapsing:
		_collapse_elapsed += delta
		queue_redraw()
		if _collapse_elapsed >= _collapse_total:
			_collapsing = false
			collapsed.emit()
		return
	if not running:
		return
	elapsed += delta
	queue_redraw()
	if elapsed >= _total_duration + 0.05:
		running = false
		done.emit()


func _draw() -> void:
	if _collapsing or _collapse_total > 0.0:
		_draw_collapse()
		return
	for b: Dictionary in blocks:
		var t := clampf((elapsed - b["delay"]) / b["duration"], 0.0, 1.0)
		t = 1.0 - pow(1.0 - t, 5.0)
		var pos: Vector2 = (b["start"] as Vector2).lerp(b["final"], t)
		draw_rect(Rect2(pos, Vector2(b["size"], b["size"])), NEON_GREEN)


func _draw_collapse() -> void:
	for b: Dictionary in blocks:
		var t := clampf((_collapse_elapsed - (b["c_delay"] as float)) / (b["c_dur"] as float), 0.0, 1.0)
		if t >= 1.0:
			continue
		var e := t * t * t   # ease in: lingers, then gets sucked in
		var sz: float = b["size"]
		var off: Vector2 = (b["final"] as Vector2) + Vector2(sz, sz) * 0.5 - _sink
		var pos := _sink + off.rotated(_collapse_turn * e) * (1.0 - e)
		var s := maxf(sz * (1.0 - e * 0.75), 1.0)
		var col := NEON_GREEN
		col.a = 1.0 - e * 0.6
		draw_rect(Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), col)

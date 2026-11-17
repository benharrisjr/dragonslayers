class_name PerfProbe
extends Node

## Samples frame cost and what the renderer is actually being asked to do.
##
##   Godot --path . -- --solo --slots=2 --seed=4242 --perf
##
## Exists because "it stutters" has several possible causes that call for different fixes --
## too many draw calls, too much skinned animation, or physics -- and guessing between them
## wastes more time than measuring does.

const WARMUP := 4.0
const SAMPLE := 6.0


var _elapsed: float = 0.0
var _samples: int = 0
var _worst_frame: float = 0.0
var _total_frame: float = 0.0
var _draw_calls: float = 0.0
var _objects: float = 0.0
var _primitives: float = 0.0
var _process_time: float = 0.0
var _physics_time: float = 0.0
var _done: bool = false


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed < WARMUP:
		return

	_samples += 1
	_total_frame += delta
	## The worst frame matters more than the average: a stutter is one long frame, and an
	## average hides it completely.
	_worst_frame = maxf(_worst_frame, delta)
	_draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_process_time += Performance.get_monitor(Performance.TIME_PROCESS)
	_physics_time += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)

	if _elapsed < WARMUP + SAMPLE:
		return
	_done = true
	_report()
	get_tree().quit()


func _report() -> void:
	var n := maxf(1.0, float(_samples))
	print("\n=== performance (%d frames, %d panes) ===" % [
		_samples, PlayerRegistry.local_pids().size()])
	print("  fps avg        %.1f" % (n / _total_frame))
	print("  frame avg      %.2f ms" % (_total_frame / n * 1000.0))
	print("  frame worst    %.2f ms" % (_worst_frame * 1000.0))
	print("  process        %.2f ms" % (_process_time / n * 1000.0))
	print("  physics        %.2f ms" % (_physics_time / n * 1000.0))
	print("  draw calls     %.0f" % (_draw_calls / n))
	print("  objects drawn  %.0f" % (_objects / n))
	print("  primitives     %.0f" % (_primitives / n))
	print("  scene nodes    %d" % get_tree().get_node_count())
	var total := 0
	var drawn := 0
	var thinking := 0
	var animating := 0
	for node in get_tree().get_nodes_in_group("monsters"):
		var monster := node as Monster
		if monster == null:
			continue
		total += 1
		if monster.visible:
			drawn += 1
		if not monster._dormant:
			thinking += 1
		if monster.visual != null and monster.visual.animation_player != null \
				and monster.visual.animation_player.active:
			animating += 1
	print("  monsters       %d (%d drawn, %d thinking, %d animating)" % [
		total, drawn, thinking, animating])
	print("  fire patches   %d" % _count_of("FirePatch"))



func _count_of(type_name: String) -> int:
	var count := 0
	for node in GameWorld.effects_root(get_tree()).get_children():
		if node.get_class() == "Node3D" and node.get_script() != null \
				and node.get_script().get_global_name() == type_name:
			count += 1
	return count

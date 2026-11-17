class_name JitterProbe
extends Node

## Measures how smoothly a jumping player moves on screen.
##
##   Godot --path . -- --solo --jitter
##
## Stutter is the character's *screen* position advancing unevenly from one drawn frame to the
## next, so that is what is recorded: where the player projects to in its pane's camera, every
## rendered frame, across a run-and-jump. A smooth arc has a second difference near zero; a
## body that only moves on physics ticks while the camera moves every frame does not.

var main: Main

var _elapsed := 0.0
var _samples: Array[Vector2] = []
var _deltas: Array[float] = []
var _repeats := 0
var _last_world := Vector3.INF
var _state := 0


func _process(delta: float) -> void:
	if OS.get_cmdline_user_args().has("--jitter-trace") and delta > 0.04:
		print("STALL %.0f ms at t=%.2f (process %.1f ms, physics %.1f ms)" % [delta * 1000.0, _elapsed,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	if main == null or main.world == null or main.split_screen == null:
		return
	var pids := PlayerRegistry.local_pids()
	if pids.is_empty() or main.split_screen.cameras.is_empty():
		return
	var player := PlayerRegistry.body_of(pids[0]) as PlayerCharacter
	if player == null:
		return
	_elapsed += delta
	match _state:
		0:
			if _elapsed > 3.0:
				## Jumping needs the feather now.
				player.add_item(ItemDB.FEATHER)
				Input.action_press("p0_right")
				_state = 1
		1:
			if _elapsed > 3.6:
				Input.action_press("p0_jump")
				_state = 2
		2:
			_record(player, delta)
			if _elapsed > 4.6:
				Input.action_release("p0_jump")
				Input.action_release("p0_right")
				_report()
				get_tree().quit()


func _record(player: PlayerCharacter, delta: float) -> void:
	var camera: Camera3D = main.split_screen.cameras[0].viewport_camera()
	## The drawn transform, which is what physics interpolation changes; global_position alone
	## would report the last physics tick whether or not the picture is being smoothed.
	var drawn := player.get_global_transform_interpolated().origin
	_samples.append(camera.unproject_position(drawn))
	if OS.get_cmdline_user_args().has("--jitter-trace"):
		print("TRACE t=%.3f player=%s cam=%s screen=%s floor=%s vel=%s" % [_elapsed, drawn.snapped(Vector3.ONE * 0.01),
				camera.global_position.snapped(Vector3.ONE * 0.01), _samples[-1].snapped(Vector2.ONE), player.is_on_floor(), player.velocity.snapped(Vector3.ONE * 0.1)])
	_deltas.append(delta)
	if drawn.is_equal_approx(_last_world):
		_repeats += 1
	_last_world = drawn


func _report() -> void:
	var worst := 0.0
	var total := 0.0
	for index in range(2, _samples.size()):
		var step := _samples[index] - _samples[index - 1]
		var previous := _samples[index - 1] - _samples[index - 2]
		var wobble := (step - previous).length()
		worst = maxf(worst, wobble)
		total += wobble
	var average_delta := 0.0
	for delta in _deltas:
		average_delta += delta
	average_delta /= maxf(1.0, _deltas.size())
	print("JITTER frames=%d fps=%.0f physics=%d repeated_positions=%d wobble_avg=%.2fpx wobble_max=%.2fpx" % [
		_samples.size(), 1.0 / maxf(average_delta, 0.0001), Engine.physics_ticks_per_second,
		_repeats, total / maxf(1.0, _samples.size() - 2), worst])

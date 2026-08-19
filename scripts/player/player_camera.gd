class_name PlayerCamera
extends Node3D

## One split-screen pane's camera: a fixed-pitch orbit rig that trails its player.
##
## The pitch never changes. A locked, fairly high angle is what gives the Links-Awakening read
## on the terrain -- you can see the plateaus you are about to be knocked off, which matters
## when getting shoved off them is the game. Yaw *is* player-controlled, because a fixed yaw in
## a world full of cliffs means spending half the game behind one.
##
## Every pane shares one World3D, so per-player markers (the target reticle) are separated by
## render layer rather than by scene: this camera sees its own slot's markers and none of the
## other three.

const PITCH_DEGREES := 42.0
const DISTANCE := 14.0
const HEIGHT_OFFSET := 1.6
const TURN_SPEED := 2.4
## Position follow is heavily smoothed; without it, knockback makes the camera jerk hard enough
## to be unpleasant in a four-way split.
const FOLLOW_SHARPNESS := 8.0
## How close to the wall the camera is allowed to get when something is between it and the player.
const COLLISION_MARGIN := 0.45

var player: PlayerCharacter
var yaw: float = 0.0

var camera: Camera3D
var _input: PlayerInput
var _smoothed_focus: Vector3


func setup(target: PlayerCharacter, slot: int) -> void:
	player = target
	_input = PlayerInput.new(slot)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 58.0
	camera.far = 400.0
	## Show the world plus this slot's own marker layer, and hide the other three slots'.
	var mask := 0xFFFFF
	for other in range(PlayerRegistry.MAX_LOCAL_SLOTS):
		mask &= ~(1 << (TargetingService.FIRST_MARKER_LAYER + other))
	camera.cull_mask = mask | (1 << (TargetingService.FIRST_MARKER_LAYER + slot))
	add_child(camera)

	if player != null:
		_smoothed_focus = player.global_position
	_apply()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _input != null:
		yaw -= _input.camera_turn() * TURN_SPEED * delta
	## The player reads its movement basis from here, so pushing "up" always means "away from
	## the camera" no matter which way this pane happens to be facing.
	player.camera_yaw = yaw

	var focus := player.global_position + Vector3.UP * HEIGHT_OFFSET
	_smoothed_focus = _smoothed_focus.lerp(focus, 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	_apply()


func _apply() -> void:
	if camera == null:
		return
	var pitch := deg_to_rad(PITCH_DEGREES)
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)) * DISTANCE
	var wanted := _smoothed_focus + offset

	## Pull in if terrain is in the way. Cliffs are everywhere and the camera sitting inside one
	## is the difference between a readable fight and a black screen.
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(_smoothed_focus, wanted)
		if player != null:
			query.exclude = [player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			wanted = hit["position"] + (_smoothed_focus - hit["position"]).normalized() * COLLISION_MARGIN

	camera.global_position = wanted
	camera.look_at(_smoothed_focus, Vector3.UP)


## Screen position within this pane -> a pick in the shared world. Used by click-targeting,
## which has to work in whichever quarter of the window the cursor happens to be in.
func viewport_camera() -> Camera3D:
	return camera

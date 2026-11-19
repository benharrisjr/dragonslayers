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
## Pulled back and flattened while fighting the dragon. At the normal follow distance a 5.6 m
## boss fills the pane and its wind-ups happen off the top of the screen -- and a telegraph you
## cannot see is not a telegraph.
const BOSS_DISTANCE := 26.0
const BOSS_PITCH_DEGREES := 30.0
## Seconds to ease between the two framings, so stepping onto the platform is a camera move
## rather than a cut.
const FRAMING_BLEND := 1.6
const HEIGHT_OFFSET := 1.6
const TURN_SPEED := 2.4
## Radians of camera rotation per pixel of mouse movement while the right button is held.
const MOUSE_SENSITIVITY := 0.006
## Degrees per second the right stick tilts the view at full deflection.
const STICK_PITCH_SPEED := 45.0
## How far the pitch may be dragged either side of whatever the current framing wants. Bounded
## rather than free: the fixed high angle is what makes the plateaus and their edges readable,
## and letting the camera drop to ground level would hide the ledge you are about to be knocked
## off. Enough range to look up at the dragon or down over a cliff.
const PITCH_RANGE := 22.0
## Position follow is heavily smoothed; without it, knockback makes the camera jerk hard enough
## to be unpleasant in a four-way split.
const FOLLOW_SHARPNESS := 8.0
## How close to the wall the camera is allowed to get when something is between it and the player.
const COLLISION_MARGIN := 0.45
## Metres per second the camera backs out to its full distance once nothing is in the way.
const RELEASE_SPEED := 14.0

var player: PlayerCharacter
var yaw: float = 0.0

var camera: Camera3D
var _input: PlayerInput
var _smoothed_focus: Vector3
## 0 = normal follow, 1 = boss framing. Eased rather than switched.
var _boss_framing: float = 0.0
## Manual pitch adjustment from a right-button drag, applied on top of whichever framing is
## active so that dragging the view does not undo the boss pull-back.
var pitch_offset: float = 0.0
## How far out the camera currently sits after collision; negative until first placed.
var _pulled_distance: float = -1.0
var _frame_delta: float = 0.0


func setup(target: PlayerCharacter, slot: int) -> void:
	player = target
	_input = PlayerInput.new(slot)
	## The rig is placed every drawn frame from the player's *interpolated* position. Bodies only
	## move on physics ticks; reading their raw position at a display rate that is not a
	## multiple of the tick rate is what makes a jumping character judder against the view.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 58.0
	## The map is 512 m across and the summit looks over all of it, so the far plane has to clear
	## the diagonal or the boundary cliffs are clipped away and the void shows through.
	camera.far = 1100.0
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
	_frame_delta = delta
	## Holding the wheel button hands the camera's stick (and Q / E) to the gear wheel.
	if _input != null and not player.wheel_open and not _input.wheel_held():
		yaw -= _input.camera_turn() * TURN_SPEED * delta
		pitch_offset = clampf(pitch_offset + _input.camera_pitch() * STICK_PITCH_SPEED * delta,
				-PITCH_RANGE, PITCH_RANGE)
	## The player reads its movement basis from here, so pushing "up" always means "away from
	## the camera" no matter which way this pane happens to be facing.
	player.camera_yaw = yaw

	var wanted_framing := 1.0 if _in_boss_arena() else 0.0
	_boss_framing = move_toward(_boss_framing, wanted_framing, delta / FRAMING_BLEND)

	var focus := player.get_global_transform_interpolated().origin + Vector3.UP * HEIGHT_OFFSET
	## While fighting, sit the focus between the player and the dragon so both are on screen
	## instead of framing the player with the boss somewhere off the edge.
	var dragon := _dragon()
	if dragon != null and _boss_framing > 0.0:
		focus = focus.lerp(focus.lerp(dragon.hit_centre(), 0.35), _boss_framing)
	_smoothed_focus = _smoothed_focus.lerp(focus, 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	_apply()


func _dragon() -> Dragon:
	var found := get_tree().get_first_node_in_group("dragon")
	return found as Dragon


func _in_boss_arena() -> bool:
	var dragon := _dragon()
	if dragon == null or player == null or dragon.is_dead:
		return false
	var offset := player.global_position - dragon.arena_centre
	offset.y = 0.0
	return offset.length() <= dragon.arena_radius + Dragon.ENGAGE_MARGIN


func _apply() -> void:
	if camera == null:
		return
	var base_pitch := lerpf(PITCH_DEGREES, BOSS_PITCH_DEGREES, _boss_framing)
	var pitch := deg_to_rad(clampf(base_pitch + pitch_offset, 8.0, 78.0))
	var distance := lerpf(DISTANCE, BOSS_DISTANCE, _boss_framing)
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)) * distance
	var wanted := _smoothed_focus + offset

	## Pull in if terrain is in the way. Cliffs are everywhere and the camera sitting inside one
	## is the difference between a readable fight and a black screen.
	var allowed := distance
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(_smoothed_focus, wanted)
		## Terrain only. A monster walking behind the player is not an occluder, and yanking the
		## camera in every time one does is worse than briefly seeing through it.
		query.collision_mask = Combatant.LAYER_WORLD
		if player != null:
			query.exclude = [player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			allowed = maxf(0.5, _smoothed_focus.distance_to(hit["position"]) - COLLISION_MARGIN)

	## In at once, out gradually. Coming in has to be immediate or the camera spends a frame
	## inside the cliff; but letting it spring straight back out the moment a tree trunk has
	## passed is a visible lurch, so the way out is eased.
	if _pulled_distance < 0.0 or allowed < _pulled_distance:
		_pulled_distance = allowed
	else:
		_pulled_distance = move_toward(_pulled_distance, allowed, RELEASE_SPEED * _frame_delta)
	wanted = _smoothed_focus + offset.normalized() * _pulled_distance

	camera.global_position = wanted
	camera.look_at(_smoothed_focus, Vector3.UP)


## Free-look from a right-button drag. Horizontal movement does exactly what Q and E do, so the
## two controls stay consistent; vertical movement tilts within PITCH_RANGE of the current
## framing. Fed in by SplitScreen, which owns the one mouse and decides whose pane it is in.
func apply_mouse_look(motion: Vector2) -> void:
	yaw -= motion.x * MOUSE_SENSITIVITY
	pitch_offset = clampf(pitch_offset + motion.y * MOUSE_SENSITIVITY * 30.0,
			-PITCH_RANGE, PITCH_RANGE)


## Screen position within this pane -> a pick in the shared world. Used by click-targeting,
## which has to work in whichever quarter of the window the cursor happens to be in.
func viewport_camera() -> Camera3D:
	return camera

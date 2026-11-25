class_name PlayerInput
extends RefCounted

## Reads one split-screen slot's controls.
##
## The same actions exist four times over, prefixed p0_ through p3_. PlayerBindings builds them
## at runtime from whichever devices claimed each seat in the lobby, so this class never needs
## to know whether a slot is a keyboard, a gamepad, or both.

const MOUSE_SLOT := 0

## False while a menu is open over the match. The world keeps running (it has to, online), so
## the players simply stop reading their controls rather than the tree being paused.
static var enabled: bool = true

var slot: int = 0

var _prefix: String


func _init(player_slot: int) -> void:
	slot = player_slot
	_prefix = "p%d_" % slot


## Raw stick/WASD direction, y positive meaning "away from the camera".
func move_vector() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	return Input.get_vector(_prefix + "left", _prefix + "right",
			_prefix + "down", _prefix + "up")


func jump_pressed() -> bool:
	return enabled and Input.is_action_just_pressed(_prefix + "jump")


func jump_held() -> bool:
	return enabled and Input.is_action_pressed(_prefix + "jump")


## The three gear hotkeys, 0-based.
func item_pressed(hotkey: int) -> bool:
	return enabled and Input.is_action_just_pressed("%sitem_%d" % [_prefix, hotkey + 1])


func item_held(hotkey: int) -> bool:
	return enabled and Input.is_action_pressed("%sitem_%d" % [_prefix, hotkey + 1])


func dash_pressed() -> bool:
	return enabled and Input.is_action_just_pressed(_prefix + "dash")


func dash_held() -> bool:
	return enabled and Input.is_action_pressed(_prefix + "dash")


func inventory_pressed() -> bool:
	return enabled and Input.is_action_just_pressed(_prefix + "inventory")


## Held to turn the right stick (or the keyboard's camera keys) from the camera over to the gear
## wheel.
func wheel_held() -> bool:
	return enabled and Input.is_action_pressed(_prefix + "wheel")


## Stepping left or right through a menu with the stick, D-pad-style: one step per push.
func menu_step() -> int:
	if not enabled:
		return 0
	if Input.is_action_just_pressed(_prefix + "left"):
		return -1
	if Input.is_action_just_pressed(_prefix + "right"):
		return 1
	return 0


## Up or down through a menu laid out in rows: -1 up, 1 down.
func menu_step_vertical() -> int:
	if not enabled:
		return 0
	if Input.is_action_just_pressed(_prefix + "up"):
		return -1
	if Input.is_action_just_pressed(_prefix + "down"):
		return 1
	return 0


func target_next_pressed() -> bool:
	return enabled and Input.is_action_just_pressed(_prefix + "target_next")


func target_prev_pressed() -> bool:
	return enabled and Input.is_action_just_pressed(_prefix + "target_prev")


func interact_pressed() -> bool:
	return enabled and Input.is_action_just_pressed(_prefix + "interact")


## Camera yaw, as a -1..1 rate rather than a delta, so the camera integrates it at its own
## speed and a stick held at half deflection turns at half rate.
func camera_turn() -> float:
	if not enabled:
		return 0.0
	return Input.get_axis(_prefix + "cam_left", _prefix + "cam_right")


## Camera tilt as a -1..1 rate: negative (stick up) looks up, matching a mouse drag upwards.
func camera_pitch() -> float:
	if not enabled:
		return 0.0
	return Input.get_axis(_prefix + "cam_up", _prefix + "cam_down")


## Where the right stick points, in screen terms (y down), for the gear wheel. Not a rate: the
## wheel wants the direction itself. Zero inside the stick's dead zone.
func wheel_vector() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	return Input.get_vector(_prefix + "wheel_left", _prefix + "wheel_right",
			_prefix + "wheel_up", _prefix + "wheel_down")


## One slice round the wheel, for the keyboard: Q and E (the item buttons, which do nothing else
## while the wheel is open), or Z and C (the camera keys). Not while the stick is pointing: the
## stick, which is also bound to the camera actions, points instead.
func wheel_step() -> int:
	if not enabled or wheel_vector() != Vector2.ZERO:
		return 0
	if Input.is_action_just_pressed(_prefix + "cam_left") \
			or Input.is_action_just_pressed(_prefix + "item_2"):
		return -1
	if Input.is_action_just_pressed(_prefix + "cam_right") \
			or Input.is_action_just_pressed(_prefix + "item_3"):
		return 1
	return 0


## Only one mouse exists no matter how many people are on the couch, so click-to-target is the
## keyboard slot's privilege and everyone else cycles targets with a bumper.
func uses_mouse() -> bool:
	return slot == MOUSE_SLOT

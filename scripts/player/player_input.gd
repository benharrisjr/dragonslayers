class_name PlayerInput
extends RefCounted

## Reads one split-screen slot's controls.
##
## The InputMap defines the same actions four times over, prefixed p0_ through p3_, with slot 0
## bound to keyboard+mouse and slots 1-3 bound to joypad devices 0-2. Per-slot actions rather
## than filtering raw InputEvents by device id keeps Godot's own deadzone and axis handling
## instead of reimplementing it, at the cost of a verbose [input] section that is generated
## rather than hand-written.

const MOUSE_SLOT := 0

var slot: int = 0

var _prefix: String


func _init(player_slot: int) -> void:
	slot = player_slot
	_prefix = "p%d_" % slot


## Raw stick/WASD direction, y positive meaning "away from the camera".
func move_vector() -> Vector2:
	return Input.get_vector(_prefix + "left", _prefix + "right",
			_prefix + "down", _prefix + "up")


func jump_pressed() -> bool:
	return Input.is_action_just_pressed(_prefix + "jump")


func jump_held() -> bool:
	return Input.is_action_pressed(_prefix + "jump")


func attack_pressed() -> bool:
	return Input.is_action_just_pressed(_prefix + "attack")


func ability_pressed(index: int) -> bool:
	return Input.is_action_just_pressed("%sability_%d" % [_prefix, index + 1])


func target_next_pressed() -> bool:
	return Input.is_action_just_pressed(_prefix + "target_next")


func target_prev_pressed() -> bool:
	return Input.is_action_just_pressed(_prefix + "target_prev")


func interact_pressed() -> bool:
	return Input.is_action_just_pressed(_prefix + "interact")


## Camera yaw, as a -1..1 rate rather than a delta, so the camera integrates it at its own
## speed and a stick held at half deflection turns at half rate.
func camera_turn() -> float:
	return Input.get_axis(_prefix + "cam_left", _prefix + "cam_right")


## Only one mouse exists no matter how many people are on the couch, so click-to-target is the
## keyboard slot's privilege and everyone else cycles targets with a bumper.
func uses_mouse() -> bool:
	return slot == MOUSE_SLOT

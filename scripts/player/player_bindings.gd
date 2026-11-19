class_name PlayerBindings
extends RefCounted

## Builds the per-player input actions (p0_ .. p3_) from who claimed which device.
##
## The actions are not in project.godot. Which device drives which player is decided in the
## lobby -- anyone can press A or Space to take the next seat -- so the bindings are laid over
## the InputMap at runtime from the two tables below. Keeping them as per-slot actions (rather
## than filtering raw events by device) keeps Godot's own deadzone and axis handling, and means
## nothing that reads input has to know how the seats were handed out.

## Stands for "keyboard and mouse" in a slot's device list; joypads use their device id (>= 0).
const KEYBOARD := -1

const DEADZONE := 0.25
const ACTIONS: Array[String] = [
	"left", "right", "up", "down", "jump", "dash",
	"item_1", "item_2", "item_3", "inventory", "wheel",
	"target_next", "target_prev", "interact",
	"cam_left", "cam_right", "cam_up", "cam_down",
	"wheel_left", "wheel_right", "wheel_up", "wheel_down",
]

## Physical keys per action. The sword is also the left mouse button and the equipped usable the
## right one, added separately.
const KEYS: Dictionary = {
	"left": [KEY_A, KEY_LEFT],
	"right": [KEY_D, KEY_RIGHT],
	"up": [KEY_W, KEY_UP],
	"down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE],
	"dash": [KEY_SHIFT],
	"item_1": [KEY_J],
	"item_2": [KEY_K],
	"item_3": [KEY_L],
	"inventory": [KEY_I],
	"wheel": [KEY_R],
	"target_next": [KEY_TAB],
	"target_prev": [KEY_BACKSPACE],
	"interact": [KEY_F],
	"cam_left": [KEY_Q],
	"cam_right": [KEY_E],
}

## Pad buttons per action, by position (Godot's ids are positional: JOY_BUTTON_A is the bottom
## face button on every pad). Play keeps the same fingers on every controller -- jump is always
## the bottom button -- and the Options "Nintendo Layout" switch only changes which letter the
## HUD prints for each (see hotkey_label). Menus are different: there the switch moves Confirm.
const PAD_BUTTONS: Dictionary = {
	"jump": JOY_BUTTON_A,
	"item_1": JOY_BUTTON_X,
	"item_2": JOY_BUTTON_Y,
	"item_3": JOY_BUTTON_B,
	"inventory": JOY_BUTTON_BACK,
	"target_prev": JOY_BUTTON_LEFT_SHOULDER,
	"target_next": JOY_BUTTON_RIGHT_SHOULDER,
	"interact": JOY_BUTTON_DPAD_UP,
}

## Pad axes per action, as [axis, direction]. The triggers are axes in Godot 4, not buttons.
const PAD_AXES: Dictionary = {
	"left": [JOY_AXIS_LEFT_X, -1.0],
	"right": [JOY_AXIS_LEFT_X, 1.0],
	"up": [JOY_AXIS_LEFT_Y, -1.0],
	"down": [JOY_AXIS_LEFT_Y, 1.0],
	"cam_left": [JOY_AXIS_RIGHT_X, -1.0],
	"cam_right": [JOY_AXIS_RIGHT_X, 1.0],
	"cam_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"cam_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"dash": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"wheel": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	## The camera's stick again, under names no key is bound to, so the gear wheel can tell a
	## stick pointing from Q and E turning the camera.
	"wheel_left": [JOY_AXIS_RIGHT_X, -1.0],
	"wheel_right": [JOY_AXIS_RIGHT_X, 1.0],
	"wheel_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"wheel_down": [JOY_AXIS_RIGHT_Y, 1.0],
}

## One entry per slot, each a list of device ids (KEYBOARD or a joypad id).
static var _assignment: Array = []


## Lays `assignment` over the InputMap: assignment[slot] is that player's device list. Slots
## past the end of the list get actions with nothing bound, so reading them is always safe.
static func apply(assignment: Array) -> void:
	_assignment = assignment.duplicate(true)
	for slot in PlayerRegistry.MAX_LOCAL_SLOTS:
		var devices: Array = _assignment[slot] if slot < _assignment.size() else []
		for action_name in ACTIONS:
			var action := StringName("p%d_%s" % [slot, action_name])
			if InputMap.has_action(action):
				InputMap.action_erase_events(action)
			else:
				InputMap.add_action(action, DEADZONE)
			for device: int in devices:
				if device == KEYBOARD:
					_add_keyboard(action, action_name)
				else:
					_add_pad(action, action_name, device)


## The assignment used when nobody went through the lobby (command-line starts, tests): if
## every local player can have a pad they each get one and the keyboard doubles up on player 1,
## otherwise the keyboard is player 1 and the pads follow.
static func apply_auto(slot_count: int) -> void:
	var pads := Input.get_connected_joypads()
	var everyone_has_pad := pads.size() >= slot_count
	var assignment: Array = []
	for slot in PlayerRegistry.MAX_LOCAL_SLOTS:
		var devices: Array = []
		if slot == 0:
			devices.append(KEYBOARD)
		## Pad ids are assumed rather than read from the connected list so that a pad plugged
		## in after the match starts still lands on the seat it would have had.
		var pad := slot if everyone_has_pad else slot - 1
		if pad >= 0:
			devices.append(pad)
		assignment.append(devices)
	apply(assignment)


## Rebuilds the actions after something reset the InputMap (Options > Reset to Defaults).
static func reapply() -> void:
	if _assignment.is_empty():
		apply_auto(1)
	else:
		apply(_assignment)


static func devices_of(slot: int) -> Array:
	return _assignment[slot] if slot < _assignment.size() else []


## Which local slot a joypad drives, or -1.
static func slot_of_pad(device: int) -> int:
	for slot in _assignment.size():
		if (_assignment[slot] as Array).has(device):
			return slot
	return -1


## What to call a hotkey on screen for whoever is in `slot`: the pad's button letter if they
## are on a pad, the key otherwise.
static func hotkey_label(slot: int, hotkey: int) -> String:
	if not on_pad(slot):
		return ["LMB", "K", "RMB"][hotkey]
	## The hotkeys are the left, top and right face buttons; a Nintendo pad prints different
	## letters on those than an Xbox one.
	return ["Y", "X", "A"][hotkey] if _nintendo() else ["X", "Y", "B"][hotkey]


## Whether `slot`'s prompts should name pad buttons rather than keys.
static func on_pad(slot: int) -> bool:
	var devices := devices_of(slot)
	var on_pad := false
	for device: int in devices:
		if device != KEYBOARD:
			on_pad = true
	## A seat with both (the command-line default) shows the pad letters only if a pad is
	## actually plugged in.
	if on_pad and devices.has(KEYBOARD) and Input.get_connected_joypads().is_empty():
		on_pad = false
	return on_pad


static func inventory_label(slot: int) -> String:
	return "Select" if on_pad(slot) else "I"


## What is held to bring up the gear wheel: the left trigger, or R.
static func wheel_label(slot: int) -> String:
	return "LT" if on_pad(slot) else "R"


## The letter printed on the jump button (the bottom face button).
static func jump_label() -> String:
	return "B" if _nintendo() else "A"


static func _nintendo() -> bool:
	return SaveManager.global_config != null and SaveManager.global_config.nintendo_layout


static func device_label(device: int) -> String:
	return "Keyboard + mouse" if device == KEYBOARD else "Gamepad %d" % (device + 1)


static func _add_keyboard(action: StringName, action_name: String) -> void:
	for keycode: int in KEYS.get(action_name, []):
		var key := InputEventKey.new()
		key.physical_keycode = keycode as Key
		InputMap.action_add_event(action, key)
	if action_name == "item_1":
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(action, click)
	if action_name == "item_3":
		var right_click := InputEventMouseButton.new()
		right_click.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action, right_click)


static func _add_pad(action: StringName, action_name: String, device: int) -> void:
	if PAD_BUTTONS.has(action_name):
		var button := InputEventJoypadButton.new()
		button.device = device
		button.button_index = PAD_BUTTONS[action_name] as JoyButton
		InputMap.action_add_event(action, button)
	if PAD_AXES.has(action_name):
		var motion := InputEventJoypadMotion.new()
		motion.device = device
		motion.axis = PAD_AXES[action_name][0] as JoyAxis
		motion.axis_value = PAD_AXES[action_name][1]
		InputMap.action_add_event(action, motion)

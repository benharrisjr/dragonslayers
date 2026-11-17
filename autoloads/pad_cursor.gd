extends CanvasLayer

## The gamepad cursor, and the router for the pad buttons whose meaning depends
## on it. Screens are mouse-driven, so rather than teach every screen about the
## pad, this drives the mouse: the left stick moves a drawn cursor and each move
## is fed back in as a synthesized InputEventMouseMotion (plus a warp of the real
## pointer, so get_global_mouse_position() agrees). A clicks with it.
##
## Pad map, by the letter on the button (Xbox / Steam Deck positions by default,
## A = bottom; Options "Nintendo Layout" puts A on the right, see confirm_button).
## Every button's action comes from Keybinds (PAD_DEFAULTS + the player's rebinds):
##   A       confirm: a left click at the cursor / hand while it shows, else the
##           ui_accept action
##   B       ui_cancel; while an item is held it puts it back instead
##   Start   open_menu
##   Select  report_bug (the feedback form) by default; left unbound, it
##           toggles D-pad cursor mode instead, for pads without a stick
##   D-pad   in a window or menu (a PadNav scope): snaps the pointing hand from
##           target to target, and A clicks the one it points at; otherwise
##           whatever the game bound to it, or cursor movement in D-pad mode
##   LB RB X Y L3 R3   whatever the game bound to them
##   LT RT   likewise, edge-detected here (an axis bound in the InputMap would
##           re-fire on every motion event while the trigger is held)
##   R stick scrolls whatever is under the cursor, as synthesized mouse-wheel
##           events, so every ScrollContainer works without knowing about the pad
##
## Keyboard: in a PadNav scope the arrow keys move the same snap hand the D-pad
## does, and while the hand is out Enter / Space click what it points at, like A
## (Escape puts a carried item back, like B). Outside a scope the arrows pass
## through untouched.
##
## The left stick / D-pad cursor speed and the right stick's scroll speed are
## scaled by GlobalConfig.pad_cursor_speed / pad_scroll_speed (Options sliders).
##
## Pad buttons are deliberately NOT InputMap-bound (SaveManager.apply_pad_layout
## strips them): an autoload's _input runs after every scene node's, so it could
## never stop a bound action reaching the scene first. They're routed here and
## re-emitted as InputEventActions instead.
##
## Toggle pickup: item drags are press-follow-release. When an A press starts one
## (DragState goes active) the matching mouse-up is held back, so the item rides
## the cursor until the next A press drops it.
##
## The cursor hides after HIDE_DELAY without stick input (never while holding an
## item or in D-pad mode); real mouse motion hides it at once.

signal input_device_changed(using_pad: bool)

const LAYER := 126  # above everything but the (parked) selection reticle
const HIDE_DELAY := 3.0
const STICK_DEADZONE := 0.2
## Cursor speed in viewport px/s at full tilt; the stick's response is squared
## below that so small tilts give fine control.
const STICK_SPEED := 1500.0
## D-pad mode: starts slow for single-item nudges, ramps to full over DPAD_RAMP.
const DPAD_SPEED_MIN := 450.0
const DPAD_SPEED_MAX := 1300.0
const DPAD_RAMP := 0.6
## Right-stick scroll rate at full tilt, in mouse-wheel notches per second (a
## notch scrolls a ScrollContainer by an eighth of its page). Squared response
## like the left stick.
const SCROLL_NOTCHES_PER_SEC := 24.0
## Smallest wheel step sent: a gentle tilt banks fractional notches until they
## reach this, since a sub-pixel scroll would round away on the scrollbar.
const SCROLL_MIN_NOTCH := 0.125
const CURSOR_SCALE := 2.0
const CURSOR_TEX := preload("res://art/kenney_cursor-pixel-pack/Tiles/tile_0106.png")
const HOLD_TEX := preload("res://art/kenney_cursor-pixel-pack/Tiles/tile_0136.png")
## The snap hand: points right, so it sits just left of whatever it selects.
const HAND_TEX := preload("res://art/icons/individual_32x32/icon081.png")
const HAND_SIZE := Vector2(40, 40)
## Negative: the fingertip tucks just inside the target's edge, so in a tight
## row the hand covers less of the neighbour to its left.
const HAND_GAP := -8.0
const HAND_BOB := 5.0
const HAND_BOB_TIME := 0.45
## Held D-pad direction in a menu: first repeat after this, then every interval.
const NAV_REPEAT_DELAY := 0.38
const NAV_REPEAT_INTERVAL := 0.11
## A slider under the hand moves one of its own steps (1% on the Options
## sliders) per D-pad press. Held, it repeats sooner than menu navigation and
## speeds up the longer it's held: the repeat interval shrinks from
## SLIDER_REPEAT_SLOW to SLIDER_REPEAT_FAST over SLIDER_RAMP_TIME, then each
## repeat moves more steps (one more per SLIDER_STEPS_GROW_TIME held).
const SLIDER_REPEAT_DELAY := 0.3
const SLIDER_REPEAT_SLOW := 0.1
const SLIDER_REPEAT_FAST := 0.025
const SLIDER_RAMP_TIME := 1.2
const SLIDER_STEPS_GROW_TIME := 0.6
## Real mouse motion this soon after a pointer warp is the warp's echo.
const WARP_ECHO_MSEC := 200
const DPAD_MODE_TINT := Color(0.55, 0.85, 1.0)
## While any node in this group is in the tree (the intro splash and its
## hand-off), the pad does nothing at all: no cursor, no hand, no buttons, just
## like the mouse and keyboard are shut out there.
const BLOCK_GROUP := &"pad_input_block"
## While any node in this group is in the tree (a cutscene playing), pad
## buttons go past PadCursor untouched: A is not taken as the hand's confirm,
## so a screen that treats every button alike (press anything to skip) gets
## A too. The stick cursor still works.
const PASSTHROUGH_GROUP := &"pad_button_passthrough"
## Synthesized mouse events carry this device id so _input can tell them from
## the real mouse (motion events are accumulated and flushed later, so a
## re-entrancy flag wouldn't survive the trip).
const SYNTH_DEVICE := -7
## Where a cancelled pickup is "dropped": off every drop target, so each drag
## system takes its own snap-back path and the item stays where it came from.
const CANCEL_POS := Vector2(-100000, -100000)

## Trigger axis -> its Keybinds pad input (the action comes from the bindings).
const _TRIGGER_INPUTS := {
	JOY_AXIS_TRIGGER_LEFT: Keybinds.PAD_LT,
	JOY_AXIS_TRIGGER_RIGHT: Keybinds.PAD_RT,
}
## Trigger hysteresis: fires past PRESS, re-arms below RELEASE.
const TRIGGER_PRESS := 0.6
const TRIGGER_RELEASE := 0.3

const _DPAD_DIRS := {
	JOY_BUTTON_DPAD_UP: Vector2.UP,
	JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT,
	JOY_BUTTON_DPAD_DOWN: Vector2.DOWN,
	JOY_BUTTON_DPAD_LEFT: Vector2.LEFT,
}
## Arrow keys (physical) that drive the snap hand like the D-pad.
const _ARROW_DIRS := {
	KEY_UP: Vector2.UP,
	KEY_RIGHT: Vector2.RIGHT,
	KEY_DOWN: Vector2.DOWN,
	KEY_LEFT: Vector2.LEFT,
}

## Last input came from a pad (any button or stick) rather than keyboard/mouse.
var using_pad := false
## Select-toggled: the D-pad steers the cursor instead of firing its bindings.
var dpad_cursor_mode := false
## An A press picked up an item; the next A press drops it.
var holding := false
## Screenshot harnesses set this so a real mouse wandering over their window
## can't take over from the pad mid-run.
var ignore_real_mouse := false
## Headless tests have no joypad: a non-zero value here stands in for the
## right stick's reading.
var test_right_stick := Vector2.ZERO

var _sprite: TextureRect
var _hand: TextureRect
var _hand_bob := 0.0  # seconds, drives the hand's sideways bob
## The control the hand points at (null when the cursor is free or hidden).
var _snapped: Control = null
## The slot an A press lifted an item from, so the hand can drop it back there.
var _pickup_source: Control = null
## Instance id of the scope last seen on top (0 = none). An id, not a Control:
## a freed node compares equal to null, so a freed scope would never look
## "changed" to a plain reference.
var _last_scope_id := 0
## The held menu-navigation direction (ZERO = none), and the D-pad button or
## arrow key holding it (-1 / KEY_NONE for the other kind).
var _nav_dir := Vector2.ZERO
var _nav_dir_button := -1
var _nav_key: Key = KEY_NONE
## The arrow keys drove the hand last (cleared by the pad or the real mouse):
## the hand follows into new windows for the keyboard too, and the OS pointer
## stays hidden under it.
var _key_nav := false
var _key_confirm: Key = KEY_NONE  # the Enter/Space whose press went out as an A
var _nav_repeat := 0.0
var _nav_held := 0.0        # how long _nav_dir has been held
var _reseed_pending := false  # a new scope opened; snap into it once it has targets
var _last_warp_msec := -100000  # when the real pointer was last warped
var _return_pos := Vector2.ZERO  # after a hand drop: where the item came from
var _return_frames := 0          # frames left to find a target near _return_pos
## Scope instance id -> the target the hand last pointed at in it, so closing a
## window puts the hand back on the button that opened it.
var _scope_memory := {}
var _pos := Vector2.ZERO
var _shown := false
var _idle := 0.0
var _dpad_held := 0.0
var _a_down := false        # A is physically down and its click is open
var _a_was_action := false  # this A press went out as the confirm action
var _swallow_a_release := false
var _trigger_down := {}     # JoyAxis -> bool
## Cancel put a carried item back on its press; its release fires nothing.
var _swallow_cancel_release: bool = false
var _scroll_banked := Vector2.ZERO  # fractional wheel notches not yet sent
## Synthesized events wait here for the end of the frame: injecting one from
## inside _input would re-enter the viewport's dispatch and clear the handled
## flag of the pad event still being processed.
var _queue: Array[InputEvent] = []


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sprite = TextureRect.new()
	_sprite.texture = CURSOR_TEX
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.size = Vector2(CURSOR_TEX.get_size()) * CURSOR_SCALE
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.visible = false
	add_child(_sprite)
	_hand = TextureRect.new()
	_hand.texture = HAND_TEX
	_hand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hand.size = HAND_SIZE
	_hand.visible = false
	add_child(_hand)
	# A scene node can handle a pad press before this autoload's _input ever
	# sees it; the window hears every event first.
	get_tree().root.window_input.connect(_on_window_input)


## Whether the cursor is on screen right now.
func is_shown() -> bool:
	return _shown


## The cursor's position in root-viewport coordinates.
func get_cursor_position() -> Vector2:
	return _pos


## The control the snap hand points at, or null.
func get_snapped() -> Control:
	return _snapped


## Put the hand on `target` from code, so A there clicks it. Works with no
## PadNav scope.
func point_at(target: Control) -> void:
	_set_using_pad(true)
	_snap_to(target)


## A drag that code started with no A press behind it: carry it like a
## picked-up item, so the D-pad hops between its drop zones and the next A drops
## it. The owner's flag must already be reporting to DragState. No-op off the pad.
func adopt_hold() -> void:
	if not (using_pad or _key_nav) or holding or not DragState.is_active():
		return
	holding = true
	_pickup_source = null
	_a_down = false
	if not _shown:
		_show_cursor()
	if not dpad_cursor_mode and (_snapped == null or not DragState.accepts_drop(_snapped)):
		var near := _nearest(PadNav.targets(get_tree(), true), _pos)
		if near != null:
			_snap_to(near)
	_refresh_sprite()


## Put the hand away if it is still on `target` (where point_at left it).
func release_point(target: Control) -> void:
	if _snapped == target and target != null:
		_hide_cursor()


## The physical button bound to Confirm (A by default: the bottom face button,
## the right one under the Nintendo layout; Godot's ids are positional).
## JOY_BUTTON_INVALID when Confirm sits on a trigger.
func confirm_button() -> JoyButton:
	return _physical_for(Keybinds.CONFIRM_ACTION)


## The physical button bound to Cancel (B by default).
func cancel_button() -> JoyButton:
	return _physical_for(Keybinds.CANCEL_ACTION)


func _physical_for(action: StringName) -> JoyButton:
	var input := Keybinds.pad_input(action)
	if input < 0 or input >= Keybinds.PAD_LT:
		return JOY_BUTTON_INVALID
	return Keybinds.pad_physical_button(input, _nintendo()) as JoyButton


func _blocked() -> bool:
	return get_tree().get_first_node_in_group(BLOCK_GROUP) != null


func _nintendo() -> bool:
	var cfg := SaveManager.global_config
	return cfg != null and cfg.nintendo_layout


func _process(delta: float) -> void:
	if _blocked():
		if _shown:
			_hide_cursor()
		_end_nav()
		return
	_process_nav(delta)
	var move := Vector2.ZERO
	var stick := _read_stick()
	if stick != Vector2.ZERO:
		_unsnap()
		move = stick * STICK_SPEED * _cursor_speed() * delta
	elif dpad_cursor_mode:
		var dir := _read_dpad()
		if dir != Vector2.ZERO:
			_dpad_held += delta
			var t := clampf(_dpad_held / DPAD_RAMP, 0.0, 1.0)
			move = dir * lerpf(DPAD_SPEED_MIN, DPAD_SPEED_MAX, t * t) * _cursor_speed() * delta
		else:
			_dpad_held = 0.0
	_scroll_with_right_stick(delta)

	if move != Vector2.ZERO:
		_set_using_pad(true)
		if not _shown:
			_show_cursor()
		_idle = 0.0
		_move_to(_pos + move)
	elif _shown and _snapped == null:
		_idle += delta
		if _idle >= HIDE_DELAY and not holding and not dpad_cursor_mode:
			_hide_cursor()

	# The drag that A picked up ended some other way (its window closed, a
	# cancel path ran): let go of the virtual button too.
	if holding and not DragState.is_active():
		holding = false
		_pickup_source = null
		_emit_button(false, _pos)
		_refresh_sprite()


func _on_window_input(event: InputEvent) -> void:
	if _blocked():
		return
	if event is InputEventJoypadButton and event.pressed:
		_set_using_pad(true)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == SYNTH_DEVICE:
		return
	if ignore_real_mouse and (event is InputEventMouse or event is InputEventScreenTouch):
		return
	if _blocked() and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		get_viewport().set_input_as_handled()
		# The feedback form still opens over a screen that blocks the pad.
		if event is InputEventJoypadButton and Keybinds.pad_action_for(
				Keybinds.pad_letter_button((event as InputEventJoypadButton).button_index, _nintendo())) == &"report_bug":
			_emit_action(&"report_bug", event.pressed)
		return
	if event is InputEventJoypadButton \
			and get_tree().get_first_node_in_group(PASSTHROUGH_GROUP) != null \
			and not _passthrough_takes(event as InputEventJoypadButton):
		return
	if event is InputEventMouseMotion:
		# The warp itself can come back as an OS motion event at our own spot.
		# (_input sees events already in viewport coordinates, like _pos.)
		# A hand following a moving target (a window sliding in) warps every
		# frame, and the OS can hand those back several frames late: anything
		# arriving just after a warp is taken as its echo.
		var at := (event as InputEventMouseMotion).position
		if _shown and (at.distance_to(_pos) < 3.0 \
				or Time.get_ticks_msec() - _last_warp_msec < WARP_ECHO_MSEC):
			return
		_on_real_mouse()
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_on_real_mouse()
		return
	if event is InputEventKey:
		if event.pressed:
			_set_using_pad(false)
		if _on_key(event as InputEventKey):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if absf(jm.axis_value) > 0.5:
			_set_using_pad(true)
		if _TRIGGER_INPUTS.has(jm.axis):
			_on_trigger(jm.axis, jm.axis_value)
		return
	if not event is InputEventJoypadButton:
		return
	var jb := event as InputEventJoypadButton
	_set_using_pad(true)
	# Select with nothing bound to it toggles the D-pad cursor mode.
	if jb.button_index == JOY_BUTTON_BACK and Keybinds.pad_action_for(JOY_BUTTON_BACK) == &"":
		if jb.pressed:
			get_viewport().set_input_as_handled()
			_toggle_dpad_mode()
		return
	# The D-pad always drives the hand in a menu (and the cursor in D-pad mode),
	# whatever it is bound to; only outside those does its binding fire.
	if _DPAD_DIRS.has(jb.button_index) and (_nav_owns_dpad() or dpad_cursor_mode):
		get_viewport().set_input_as_handled()
		if _nav_owns_dpad():
			if jb.pressed:
				_begin_nav(_DPAD_DIRS[jb.button_index], jb.button_index, KEY_NONE)
			elif jb.button_index == _nav_dir_button:
				_end_nav()
		elif jb.pressed:
			_dpad_held = 0.0
		return
	if jb.button_index == _nav_dir_button and not jb.pressed:
		_end_nav()
	# Every other button fires whatever the player bound to it (Keybinds).
	var action := Keybinds.pad_action_for(Keybinds.pad_letter_button(jb.button_index, _nintendo()))
	if action == &"":
		return
	get_viewport().set_input_as_handled()
	_on_pad_action(action, jb.pressed)


## Under PASSTHROUGH_GROUP, the few buttons PadCursor still keeps: the D-pad
## while a scope owns it (a prompt's hand), and Confirm while the hand
## points at something (it clicks that), plus the release of a press it took.
func _passthrough_takes(jb: InputEventJoypadButton) -> bool:
	if _DPAD_DIRS.has(jb.button_index):
		return _nav_owns_dpad() and not dpad_cursor_mode
	var action := Keybinds.pad_action_for(Keybinds.pad_letter_button(jb.button_index, _nintendo()))
	if action != Keybinds.CONFIRM_ACTION:
		return false
	if jb.pressed:
		return _hand.visible and _snapped != null and not jb.is_echo()
	return _a_down or _swallow_a_release or _a_was_action


## One bound pad input pressed / released. Confirm and Cancel keep their hand
## behaviour (click / put a carried item back); the rest become InputEventActions.
func _on_pad_action(action: StringName, pressed: bool) -> void:
	match action:
		Keybinds.CONFIRM_ACTION:
			_on_confirm(pressed)
		Keybinds.CANCEL_ACTION:
			if pressed and holding:
				_swallow_cancel_release = true
				_cancel_hold()
			elif not pressed and _swallow_cancel_release:
				_swallow_cancel_release = false
			else:
				_emit_action(action, pressed)
		_:
			# A gameplay hotkey: the player is driving by buttons, so the free
			# cursor gets out of the way.
			if pressed and not action in Keybinds.MENU_ACTIONS:
				_step_aside()
			_emit_action(action, pressed)


## Arrow keys step the hand while a scope owns the D-pad; Enter / Space click
## with it while it's out (Escape drops a carried item back). True = consumed.
func _on_key(ev: InputEventKey) -> bool:
	if _blocked():
		return false
	# A focused text field (the feedback form) owns arrows and Enter.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is TextEdit or focus is LineEdit:
		return false
	var key := ev.physical_keycode
	if _ARROW_DIRS.has(key):
		if ev.pressed:
			if not _nav_owns_dpad():
				return false
			if not ev.echo:  # held keys repeat on our own clock, like the D-pad
				_key_nav = true
				_begin_nav(_ARROW_DIRS[key], -1, key)
			return true
		if key == _nav_key:
			_end_nav()
			return true
		return false
	if not ev.pressed and key == _key_confirm:
		# The press clicked; its release goes the same way even if the click
		# closed the window and put the hand away.
		_key_confirm = KEY_NONE
		_on_confirm(false)
		return true
	if not ev.pressed or not _hand.visible or _snapped == null:
		return false
	if ev.is_action(Keybinds.CANCEL_ACTION) and holding:
		_cancel_hold()
		return true
	if ev.is_action(Keybinds.CONFIRM_ACTION):
		if not ev.echo and _key_confirm == KEY_NONE:
			_key_confirm = key
			_on_confirm(true)
		return true
	return false


func _begin_nav(dir: Vector2, button: int, key: Key) -> void:
	_nav_dir = dir
	_nav_dir_button = button
	_nav_key = key
	_nav_held = 0.0
	_nav_repeat = SLIDER_REPEAT_DELAY if _on_slider_x(dir) else NAV_REPEAT_DELAY
	_nav_step(dir)


func _end_nav() -> void:
	_nav_dir = Vector2.ZERO
	_nav_dir_button = -1
	_nav_key = KEY_NONE


func _nav_still_held() -> bool:
	if _nav_key != KEY_NONE:
		return Input.is_physical_key_pressed(_nav_key)
	var device := _pad_device()
	return device >= 0 and Input.is_joy_button_pressed(device, _nav_dir_button)


# --- A: click at the cursor, or confirm ----------------------------------------

func _on_confirm(pressed: bool) -> void:
	if pressed:
		if holding:
			# Second press: drop the held item where the cursor is.
			holding = false
			if _snapped != null and _is_live(_pickup_source):
				# Hand back to the slot it came from once the drop has landed.
				_return_pos = _pickup_source.get_global_rect().get_center()
				_return_frames = 3
			_pickup_source = null
			_swallow_a_release = true
			_emit_button(false, _pos)
			_refresh_sprite()
		elif _snapped != null and _snapped is Slider:
			# A click would jump the slider to its middle; the D-pad steps it.
			_swallow_a_release = true
		elif not _shown and _nav_owns_dpad() \
				and _nearest_to_pointer(PadNav.targets(get_tree(), false)) != null:
			# A menu is up but the hand isn't: bring it out nearest where the
			# mouse was, click nothing. (A window with nothing to point at yet
			# falls through to the confirm action below instead.)
			_swallow_a_release = true
			_snap_to(_nearest_to_pointer(PadNav.targets(get_tree(), false)))
		elif _snapped != null and PadNav.scrolled_out(_snapped):
			# The hand is parked at the list's edge: A brings its target back
			# into view rather than clicking whatever sits under the parked
			# hand.
			_swallow_a_release = true
			PadNav.reveal(_snapped)
		elif _shown:
			_a_down = true
			_a_was_action = false
			_idle = 0.0
			# A drag source fades out on the press itself, so note it now.
			_pickup_source = _snapped
			_emit_button(true, _pos)
		else:
			_a_was_action = true
			# A window with nothing to point at yet: show the hand as soon as
			# it has something.
			if _nav_owns_dpad():
				_reseed_pending = true
			_emit_action(Keybinds.CONFIRM_ACTION, true)
		return
	if _swallow_a_release:
		_swallow_a_release = false
		return
	if _a_was_action:
		_a_was_action = false
		_emit_action(Keybinds.CONFIRM_ACTION, false)
		return
	if _a_down:
		_a_down = false
		if DragState.is_active():
			# The press lifted an item: keep the button "down" so it follows the
			# cursor until the next A.
			holding = true
			_refresh_sprite()
		else:
			_pickup_source = null
			_emit_button(false, _pos)


## A gameplay hotkey means the player is driving by buttons, so the cursor gets
## out of the way and the next A confirms instead of clicking.
func _step_aside() -> void:
	if _hand.visible:
		return
	if _shown and not holding and not dpad_cursor_mode and not _a_down:
		_hide_cursor()


func _on_trigger(axis: JoyAxis, value: float) -> void:
	var down: bool = _trigger_down.get(axis, false)
	var action := Keybinds.pad_action_for(_TRIGGER_INPUTS[axis])
	if not down and value >= TRIGGER_PRESS:
		_trigger_down[axis] = true
		if action != &"":
			_on_pad_action(action, true)
	elif down and value <= TRIGGER_RELEASE:
		_trigger_down[axis] = false
		if action != &"":
			_on_pad_action(action, false)


func _cancel_hold() -> void:
	holding = false
	_emit_button(false, CANCEL_POS)
	_refresh_sprite()
	# Back to the slot it came from, so the next A can pick it up again.
	if _snapped != null and _is_live(_pickup_source):
		_snap_to(_pickup_source)
	_pickup_source = null


func _toggle_dpad_mode() -> void:
	_unsnap()
	dpad_cursor_mode = not dpad_cursor_mode
	_dpad_held = 0.0
	if dpad_cursor_mode and not _shown:
		_show_cursor()
	_idle = 0.0
	_refresh_sprite()


# --- Device switching -----------------------------------------------------------

func _on_real_mouse() -> void:
	_snapped = null
	_end_nav()
	_key_nav = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if holding:
		_cancel_hold()
	if _shown:
		_hide_cursor()
	if dpad_cursor_mode:
		dpad_cursor_mode = false
		_refresh_sprite()
	_set_using_pad(false)


func _set_using_pad(value: bool) -> void:
	if value:
		_key_nav = false
	if using_pad == value:
		return
	using_pad = value
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if value else Input.MOUSE_MODE_VISIBLE
	input_device_changed.emit(value)
	# Every hotkey badge repaints through this one signal.
	SaveManager.keybinds_changed.emit()


func _show_cursor() -> void:
	_shown = true
	_idle = 0.0
	# Pick up from wherever the real pointer was left.
	_pos = _clamp(get_viewport().get_mouse_position())
	_sprite.position = _pos
	_sprite.visible = true
	_refresh_sprite()


func _hide_cursor() -> void:
	_shown = false
	_snapped = null
	_sprite.visible = false
	_hand.visible = false
	if not using_pad:
		# The arrow keys hid the pointer under the hand; give it back.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_sprite() -> void:
	_sprite.texture = HOLD_TEX if holding else CURSOR_TEX
	_sprite.modulate = DPAD_MODE_TINT if dpad_cursor_mode else Color.WHITE
	_sprite.visible = _shown and _snapped == null
	_hand.visible = _shown and _snapped != null


# --- Snap hand (menus and windows; see PadNav) ------------------------------------

## The D-pad navigates (rather than firing its bindings) while a PadNav scope is up,
## or while an item is held with the hand (to carry it to a drop zone).
func _nav_owns_dpad() -> bool:
	if dpad_cursor_mode:
		return false
	if holding and _snapped != null:
		return true
	return PadNav.active_scope(get_tree()) != null


func _process_nav(delta: float) -> void:
	# A newly opened (or closed) window: if the player is on the pad and was
	# using the hand (or nothing), carry it into the new top window.
	# Mid scene change: the old screen is fading out under the black (which the
	# hand would draw over), the new one isn't up yet. Hide and wait.
	if SceneManager.is_transitioning():
		if _shown and not holding:
			_hide_cursor()
			_reseed_pending = using_pad or _key_nav
		return
	# The hand's target can be freed outright (its whole screen went), and a
	# freed node compares equal to null, so check validity explicitly.
	if _hand.visible and not is_instance_valid(_snapped):
		_snapped = null
		_lose_snap()
	var scope := PadNav.active_scope(get_tree())
	var scope_id := scope.get_instance_id() if scope else 0
	if scope_id != _last_scope_id:
		_last_scope_id = scope_id
		if not holding:
			var was_snapped := _hand.visible
			if was_snapped:
				# Whatever it pointed at belongs to the window that just went
				# (or is sliding out): don't trail it off screen.
				_hide_cursor()
			if scope != null and (using_pad or _key_nav) and not dpad_cursor_mode:
				# A new screen or window on the pad: point into it with the hand,
				# even if the free stick cursor was what clicked it open.
				if _shown:
					_hide_cursor()
				_reseed_pending = true
	if _reseed_pending:
		var cands := PadNav.targets(get_tree(), false)
		var seed: Control = _remembered(scope, cands)
		if seed == null:
			seed = PadNav.seed_target(get_viewport(), cands)
		if seed != null:
			_reseed_pending = false
			_snap_to(seed)
		elif scope == null:
			_reseed_pending = false

	if _return_frames > 0 and not holding:
		# A drop can rebuild its lists; give it a frame or two to settle.
		_return_frames -= 1
		if _return_frames == 0 and _snapped != null:
			var back := _nearest(PadNav.targets(get_tree(), false), _return_pos)
			if back != null:
				_snap_to(back)

	if _snapped != null:
		if not _is_live(_snapped):
			_snapped = null
			_lose_snap()
		else:
			# Scrolled out of its list (right stick): move onto what's still in
			# view rather than trailing it over the window's header or footer.
			# (Right stick only: a D-pad reveal lands a frame late, so its new
			# target briefly reads as scrolled out.)
			if not holding and _read_right_stick() != Vector2.ZERO \
					and PadNav.scrolled_out(_snapped):
				var inside := PadNav.nearest_in_view(_snapped, PadNav.targets(get_tree(), false))
				if inside != null:
					_snap_to(inside, false)
			# Follow it through scrolls, drop-in tweens and reflows.
			# A target scrolled out with nothing else in its list showing (a
			# detail page whose only targets sit further down) parks the hand
			# at the list's edge rather than off the window.
			var c := PadNav.park_in_scroll(_snapped, _snapped.get_global_rect()).get_center()
			if c.distance_to(_pos) > 0.5:
				_move_to(c)
			_place_hand(delta)

	if _nav_dir != Vector2.ZERO:
		if not _nav_still_held():
			_end_nav()
		else:
			_nav_held += delta
			_nav_repeat -= delta
			if _nav_repeat <= 0.0:
				if _on_slider_x(_nav_dir):
					var ramp := clampf((_nav_held - SLIDER_REPEAT_DELAY) / SLIDER_RAMP_TIME, 0.0, 1.0)
					_nav_repeat = lerpf(SLIDER_REPEAT_SLOW, SLIDER_REPEAT_FAST, ramp)
					var past := maxf(0.0, _nav_held - SLIDER_REPEAT_DELAY - SLIDER_RAMP_TIME)
					_step_slider(_nav_dir.x, 1 + int(past / SLIDER_STEPS_GROW_TIME))
				else:
					_nav_repeat = NAV_REPEAT_INTERVAL
					_nav_step(_nav_dir)


## The hand's target went (rebuilt, hidden or freed): re-find something nearby,
## or put the hand away when there's nothing left to point at.
func _lose_snap() -> void:
	var near := _nearest(PadNav.targets(get_tree(), holding), _pos)
	if near != null:
		_snap_to(near)
	else:
		_refresh_sprite()
		if not holding:
			_hide_cursor()


func _nav_step(dir: Vector2) -> void:
	if not _key_nav:
		_set_using_pad(true)
	if SceneManager.is_transitioning():
		return
	if _snapped == null or not _is_live(_snapped):
		# First press after free movement (stick cursor, mouse): bring the hand
		# out on whatever's nearest the pointer, so it picks up where the player
		# was rather than jumping to the screen's default.
		var cands := PadNav.targets(get_tree(), holding)
		var start: Control = _nearest_to_pointer(cands)
		if start == null and not holding:
			# Pressed while the screen is still fading its buttons in: point at
			# the first one as soon as it's there.
			_reseed_pending = true
		_snap_to(start)
		return
	if _snapped is Slider and dir.y == 0.0:
		_step_slider(dir.x, 1)
		return
	var cands := PadNav.targets(get_tree(), holding)
	if holding and _is_live(_pickup_source) and not cands.has(_pickup_source):
		cands.append(_pickup_source)
	# From where the hand is parked, not from the scrolled-out target.
	var from := PadNav.park_in_scroll(_snapped, PadNav.beam_rect(_snapped))
	var next := PadNav.pick(from, dir, cands, _snapped)
	if next != null:
		_snap_to(next)


## True while the hand is on a slider and `dir` is left/right, i.e. the press
## steps the slider instead of moving the hand.
func _on_slider_x(dir: Vector2) -> bool:
	return is_instance_valid(_snapped) and _snapped is Slider and dir.y == 0.0


func _step_slider(dir_x: float, steps: int) -> void:
	var s := _snapped as Slider
	var step := s.step if s.step > 0.0 else (s.max_value - s.min_value) * 0.01
	s.value += dir_x * step * steps


func _snap_to(target: Control, reveal := true) -> void:
	if target == null:
		return
	if reveal:
		PadNav.reveal(target)
	_snapped = target
	if _key_nav:
		# The hand stands in for the pointer, which the warp drags along anyway.
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if _last_scope_id != 0 and not holding:
		_scope_memory[_last_scope_id] = weakref(target)
	if not _shown:
		_shown = true
		_sprite.visible = false
	_idle = 0.0
	_hand_bob = 0.0
	_move_to(target.get_global_rect().get_center())
	_refresh_sprite()
	_place_hand(0.0)


func _remembered(scope: Control, cands: Array[Control]) -> Control:
	if scope == null:
		return null
	var ref: WeakRef = _scope_memory.get(scope.get_instance_id())
	var c := ref.get_ref() as Control if ref else null
	return c if c != null and cands.has(c) else null


func _unsnap() -> void:
	if _snapped == null:
		return
	_snapped = null
	_end_nav()
	_refresh_sprite()


## Just left of the target, vertically centred, fingertip at its edge, bobbing
## sideways. Kept on screen for targets hard against the left edge.
func _place_hand(delta: float) -> void:
	if _snapped == null:
		return
	_hand_bob += delta
	var bob := (1.0 - cos(_hand_bob * PI / HAND_BOB_TIME)) * 0.5 * HAND_BOB
	var rect := PadNav.park_in_scroll(_snapped, PadNav.nav_rect(_snapped))
	var p := Vector2(rect.position.x - HAND_SIZE.x - HAND_GAP - bob,
		rect.get_center().y - HAND_SIZE.y * 0.5)
	var vis := get_viewport().get_visible_rect()
	p = p.clamp(vis.position, vis.end - HAND_SIZE)
	_hand.position = p


## A target still worth pointing at. The hand keeps what it already points at
## (and the slot an item was lifted from) through a fade: a lifted slot sits at
## alpha 0 while held and while the item snaps back, but it's still the spot.
func _is_live(c: Control) -> bool:
	if c != null and (c == _snapped or c == _pickup_source) and is_instance_valid(c) \
			and c.is_inside_tree() and not c.is_queued_for_deletion() and c.is_visible_in_tree():
		return true
	return PadNav.is_target_live(c)


## Where the player was last pointing: the stick cursor while it's out, else
## the real mouse.
func _pointer_pos() -> Vector2:
	return _pos if _shown else _clamp(get_viewport().get_mouse_position())


## The target under the pointer (the smallest, when they nest), else the one
## whose centre is nearest it.
func _nearest_to_pointer(cands: Array[Control]) -> Control:
	var at := _pointer_pos()
	var under: Control = null
	var under_area := INF
	for c in cands:
		var r := c.get_global_rect()
		if r.has_point(at) and r.get_area() < under_area:
			under_area = r.get_area()
			under = c
	return under if under != null else _nearest(cands, at)


func _nearest(cands: Array[Control], at: Vector2) -> Control:
	var best: Control = null
	var best_d := INF
	for c in cands:
		var d := c.get_global_rect().get_center().distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = c
	return best


# --- Pad reads --------------------------------------------------------------------

func _pad_device() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else -1


func _read_stick() -> Vector2:
	var device := _pad_device()
	if device < 0:
		return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	var mag := v.length()
	if mag < STICK_DEADZONE:
		return Vector2.ZERO
	# Rescale past the deadzone, then square for fine control near the centre.
	var t := clampf((mag - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)
	return v / mag * t * t


func _read_right_stick() -> Vector2:
	if test_right_stick != Vector2.ZERO:
		return test_right_stick
	var device := _pad_device()
	if device < 0:
		return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	var mag := v.length()
	if mag < STICK_DEADZONE:
		return Vector2.ZERO
	var t := clampf((mag - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)
	return v / mag * t * t


func _cursor_speed() -> float:
	var cfg := SaveManager.global_config
	return cfg.pad_cursor_speed if cfg else 1.0


func _scroll_speed() -> float:
	var cfg := SaveManager.global_config
	return cfg.pad_scroll_speed if cfg else 1.0


## Right stick: wheel notches at the cursor (or wherever the pointer was left
## when it is hidden), one event per axis per frame with the fractional amount
## carried in the event's factor, so a slight tilt creeps and a full one pages.
func _scroll_with_right_stick(delta: float) -> void:
	var stick := _read_right_stick()
	if stick == Vector2.ZERO:
		_scroll_banked = Vector2.ZERO
		return
	_set_using_pad(true)
	var at := _pos if _shown else get_viewport().get_mouse_position()
	_scroll_banked += stick * SCROLL_NOTCHES_PER_SEC * _scroll_speed() * delta
	if _snapped != null and _scroll_snapped_list():
		return
	if absf(_scroll_banked.y) >= SCROLL_MIN_NOTCH:
		_emit_wheel(MOUSE_BUTTON_WHEEL_DOWN if _scroll_banked.y > 0.0 else MOUSE_BUTTON_WHEEL_UP,
				absf(_scroll_banked.y), at)
		_scroll_banked.y = 0.0
	if absf(_scroll_banked.x) >= SCROLL_MIN_NOTCH:
		_emit_wheel(MOUSE_BUTTON_WHEEL_RIGHT if _scroll_banked.x > 0.0 else MOUSE_BUTTON_WHEEL_LEFT,
				absf(_scroll_banked.x), at)
		_scroll_banked.x = 0.0


## With the hand on a target inside a scrollable list, scroll that list itself
## by the banked notches rather than sending wheel events at the hand. A wheel
## event goes wherever Godot's mouse state routes it, and after D-pad moves
## that wasn't always the list under the hand (moving the free cursor first
## fixed it). Each axis goes to the nearest enclosing ScrollContainer that can
## scroll that way. False when no list encloses the hand: the caller falls back
## to wheel events.
func _scroll_snapped_list() -> bool:
	var v_scroll := _enclosing_scroll(_snapped, true)
	var h_scroll := _enclosing_scroll(_snapped, false)
	if v_scroll == null and h_scroll == null:
		return false
	if absf(_scroll_banked.y) >= SCROLL_MIN_NOTCH:
		if v_scroll != null:
			var bar := v_scroll.get_v_scroll_bar()
			bar.value += bar.page * 0.125 * _scroll_banked.y
		_scroll_banked.y = 0.0
	if absf(_scroll_banked.x) >= SCROLL_MIN_NOTCH:
		if h_scroll != null:
			var bar := h_scroll.get_h_scroll_bar()
			bar.value += bar.page * 0.125 * _scroll_banked.x
		_scroll_banked.x = 0.0
	return true


## The nearest ScrollContainer above `c` with room to scroll vertically
## (`vertical`) or horizontally, or null.
static func _enclosing_scroll(c: Control, vertical: bool) -> ScrollContainer:
	var p := c.get_parent()
	while p != null:
		var sc := p as ScrollContainer
		if sc != null:
			var mode := sc.vertical_scroll_mode if vertical else sc.horizontal_scroll_mode
			var bar: ScrollBar = sc.get_v_scroll_bar() if vertical else sc.get_h_scroll_bar()
			if mode != ScrollContainer.SCROLL_MODE_DISABLED and bar.max_value - bar.page > 0.5:
				return sc
		p = p.get_parent()
	return null


func _read_dpad() -> Vector2:
	var device := _pad_device()
	if device < 0:
		return Vector2.ZERO
	var v := Vector2(
		float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT))
			- float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT)),
		float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN))
			- float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP)))
	return v.normalized()


# --- Synthesized events -------------------------------------------------------------

func _move_to(p: Vector2) -> void:
	var prev := _pos
	_pos = _clamp(p)
	_sprite.position = _pos
	if _pos == prev:
		return
	var ev := InputEventMouseMotion.new()
	ev.device = SYNTH_DEVICE
	ev.position = _to_window(_pos)
	ev.global_position = ev.position
	ev.relative = ev.position - _to_window(prev)
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if (holding or _a_down) else 0
	_push(ev)


func _emit_button(pressed: bool, at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.device = SYNTH_DEVICE
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _to_window(at)
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_push(ev)


## A wheel "click" is a press with no matching release in Godot's own handling
## (ScrollContainer scrolls on the press), but send the release too so anything
## tracking button state sees it go back up.
func _emit_wheel(button: MouseButton, factor: float, at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.device = SYNTH_DEVICE
		ev.button_index = button
		ev.pressed = pressed
		ev.factor = factor
		ev.position = _to_window(at)
		ev.global_position = ev.position
		_push(ev)


func _emit_action(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	_push(ev)


func _push(ev: InputEvent) -> void:
	if _queue.is_empty():
		_flush.call_deferred()
	_queue.append(ev)


func _flush() -> void:
	var events := _queue
	_queue = []
	for ev in events:
		if ev is InputEventMouseMotion:
			# Keep the real pointer under the drawn one, so code that polls
			# get_global_mouse_position() reads the cursor too.
			get_viewport().warp_mouse(_from_window((ev as InputEventMouseMotion).position))
			_last_warp_msec = Time.get_ticks_msec()
		Input.parse_input_event(ev)


## Root-viewport coordinates -> window pixels, the space injected events start in
## (the window applies the stretch transform on the way down, like a real mouse).
func _to_window(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


func _from_window(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform().affine_inverse() * p


func _clamp(p: Vector2) -> Vector2:
	var r := get_viewport().get_visible_rect()
	return p.clamp(r.position, r.end - Vector2.ONE)

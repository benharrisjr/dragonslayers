extends Node
## Focus seeding for menus, plus tracking whether the keyboard/gamepad or the
## pointer is driving focus (is_navigating).
##
## Movement, neighbor search, list wrap and slider adjustment are all handled by
## Godot's native focus system (ui_up/down/left/right + ui_accept/ui_cancel). This
## autoload only *seeds* focus when a screen opens. (It used to also draw an
## animated corner bracket around the focus owner; that overlay was removed.)
##
## Invariant relied on elsewhere: nothing holds focus unless a screen/window has
## called focus_first()/push_context(). So an accept press can't accidentally
## trigger a stray focused control when no menu is open.

## True while keyboard/gamepad drives focus; false under mouse/touch.
var _focus_active := false
## Remembered focus owners so closing a modal restores the opener's focus.
var _context_stack: Array[Control] = []


func _ready() -> void:
	# Keep tracking input mode while the SceneTree is paused (menus open over a
	# paused game).
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		# Pointer input. Focus is intentionally left intact so a subsequent key
		# press resumes on the same control.
		_focus_active = false
		return
	if event is InputEventKey and event.pressed and not event.echo and _is_nav_key(event):
		_focus_active = true
	elif event is InputEventJoypadButton and event.pressed:
		_focus_active = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_focus_active = true


func _is_nav_key(event: InputEventKey) -> bool:
	return event.is_action("ui_up") or event.is_action("ui_down") \
		or event.is_action("ui_left") or event.is_action("ui_right") \
		or event.is_action("ui_accept") or event.is_action("ui_cancel") \
		or event.is_action("ui_focus_next") or event.is_action("ui_focus_prev")


# --- Public API used by screens/windows -------------------------------------

## Grab focus on `ctrl`.
func focus_first(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	# Composite controls (e.g. PanelButton) forward focus to an inner node.
	var target: Control = ctrl.get_focus_target() if ctrl.has_method("get_focus_target") else ctrl
	if target and is_instance_valid(target):
		target.grab_focus()


## Focus the first focusable descendant of `root` (depth-first, tree order).
## Convenient for large code-built windows where naming a specific control is
## fiddly. Returns the control it focused, or null if none was found.
func focus_first_in(root: Control) -> Control:
	if root == null or not is_instance_valid(root):
		return null
	var target := _find_focusable(root)
	if target:
		target.grab_focus()
	return target


func _find_focusable(node: Node) -> Control:
	for child in node.get_children():
		var ctrl := child as Control
		if ctrl and ctrl.visible and ctrl.focus_mode == Control.FOCUS_ALL:
			return ctrl
		var found := _find_focusable(child)
		if found:
			return found
	return null


## Remember the current focus owner, then focus `first`. Pair with pop_context()
## when the window closes so focus returns to whatever opened it.
func push_context(first: Control) -> void:
	_context_stack.push_back(get_viewport().gui_get_focus_owner())
	focus_first(first)


func pop_context() -> void:
	if _context_stack.is_empty():
		return
	# Deliberately untyped: the opener can be freed while the window it opened is
	# still up (e.g. unlocking a class rebuilds the screen behind the popup), and
	# assigning a freed instance to a typed Control errors out before
	# is_instance_valid() ever gets to reject it.
	var prev = _context_stack.pop_back()
	if not is_instance_valid(prev):
		return
	var ctrl := prev as Control
	if ctrl and ctrl.is_visible_in_tree():
		ctrl.grab_focus()


## True when the player is actively driving a menu with the keyboard (focus mode
## on AND something is focused). In-game controls can check this to yield input
## while a menu/navbar owns it. Stays false in normal combat  a nav key flips
## focus mode on, but nothing is focused there  and false for focus left over
## from a mouse click (mouse input turns focus mode off).
func is_navigating() -> bool:
	return _focus_active and get_viewport().gui_get_focus_owner() != null


## Drop any remembered focus (e.g. returning to free play).
func clear() -> void:
	_context_stack.clear()
	var owner := get_viewport().gui_get_focus_owner()
	if owner:
		owner.release_focus()

class_name DragState
extends RefCounted
## Which hand-rolled item drags are live right now. Each screen that runs its
## own press-follow-release drag reports in here (through a setter on its own
## "dragging" flag: DragState.track(self, value)) so PadCursor
## can tell that an A press picked something up and must keep it held until
## the next A press — toggle pickup — instead of releasing it at once.

static var _owners: Dictionary = {}  # Object instance id -> true
## Object instance id -> Callable(Control) -> bool: which PadNav drop zones
## (group pad_drop) the owner's live drag can land on, so the pad's snap hand
## only visits drops that would take the held item.
static var _drop_filters: Dictionary = {}


## Register or clear `owner`'s drag. Called from each system's flag setter.
static func track(owner: Object, dragging: bool) -> void:
	if dragging:
		_owners[owner.get_instance_id()] = true
	else:
		_owners.erase(owner.get_instance_id())


## True while any system has a drag in progress (freed owners are pruned).
static func is_active() -> bool:
	for id in _owners.keys():
		if not is_instance_id_valid(id):
			_owners.erase(id)
	return not _owners.is_empty()


## Register `owner`'s drop filter: `filter.call(zone: Control) -> bool`.
## Pass a bound method, never a lambda — lambdas left in this static dict
## crash the engine on quit. Filters of freed owners are pruned here.
static func set_drop_filter(owner: Object, filter: Callable) -> void:
	for id in _drop_filters.keys():
		if not is_instance_id_valid(id):
			_drop_filters.erase(id)
	_drop_filters[owner.get_instance_id()] = filter


## Whether the live drag can land on drop zone `zone`. With no filter from any
## active owner, every zone is fair game.
static func accepts_drop(zone: Control) -> bool:
	for id in _owners.keys():
		var f: Callable = _drop_filters.get(id, Callable())
		if f.is_valid():
			return bool(f.call(zone))
	return true


## How far (px) a press may wander and still count as a click for Click to Drag.
const CLICK_SLOP := 10.0


## Click to Drag (Options): whether the real-mouse left release `mb` should keep
## the item held rather than drop it, because the press that lifted it at
## `press_pos` was a plain click. The owner then drops on the next left press.
## Pad / arrow-key presses (PadCursor's synthetic device) do their own toggle
## pickup and never qualify.
static func click_holds(mb: InputEventMouseButton, press_pos: Vector2) -> bool:
	if mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or mb.device == PadCursor.SYNTH_DEVICE:
		return false
	if SaveManager.global_config == null or not SaveManager.global_config.click_to_drag:
		return false
	return mb.global_position.distance_to(press_pos) <= CLICK_SLOP

class_name Keybinds
## Rebindable keyboard hotkeys and gamepad buttons, and their prompt icons.
##
## Keyboard: project.godot's [input] section holds the defaults; the player's
## overrides live in GlobalConfig.keybinds (action -> physical keycode) and are
## laid over the runtime InputMap at boot (apply_saved).
##
## Gamepad: no pad button is InputMap-bound. PadCursor routes every press through
## pad_action_for(), reading PAD_DEFAULTS overlaid with GlobalConfig.pad_binds.
## Buttons are stored by the letter printed on them (Xbox / Steam Deck names), so
## the Nintendo Layout option only changes the physical mapping
## (pad_physical_button), never a binding. Select defaults to Report Bug (left
## unbound it toggles PadCursor's D-pad cursor mode); the sticks' movement stays
## fixed, but their clicks (L3/R3) bind like any button. Every on-screen key icon
## resolves through hint_texture(action), so a rebind or the Key Hints toggle
## reaches all of them via SaveManager.keybinds_changed (also emitted when
## PadCursor switches between pad and keyboard/mouse, so the badges swap glyph
## sets).
##
## Adding a game action (say "jump"):
##   1. Add it to project.godot's input map with its default KEY (no pad events).
##   2. Add a REBINDABLE row: {"action": &"jump", "label": "Jump"}.
##   3. Give it a pad button in PAD_DEFAULTS: &"jump": JOY_BUTTON_X.
## It then shows in Options > Keybindings, works on the pad, and
## Keybinds.hint_texture(&"jump") draws its prompt for the current device.

## The pad's click / back-out actions. PadCursor gives these their hand
## behaviour (A clicks what the hand points at, B puts a carried item back).
const CONFIRM_ACTION := &"ui_accept"
const CANCEL_ACTION := &"ui_cancel"
## Actions that open a window: firing one leaves PadCursor's cursor where it is
## (any other hotkey tucks the free cursor away).
const MENU_ACTIONS: Array[StringName] = [&"open_menu", &"report_bug"]

## Display order of the Keybindings window. Every action here owns exactly one
## keyboard key and at most one pad input; rebind() / rebind_pad() swap on
## conflict so that stays true. Keys are unique per "context": rows that give a
## "context" (e.g. &"drag", hotkeys that only fire while an item is in hand) may
## share a key with a row in another context. "keyboard": false = a pad-only row
## (its key is shown but fixed).
const REBINDABLE: Array[Dictionary] = [
	{"action": &"open_menu",  "label": "Options"},
	{"action": &"report_bug", "label": "Report Bug"},
	{"action": &"ui_accept",  "label": "Confirm", "keyboard": false},
	{"action": &"ui_cancel",  "label": "Cancel",  "keyboard": false},
]

## Pad inputs, named by what's printed on the pad. The face buttons reuse the
## Xbox-position JoyButton ids as their LETTER (pad_physical_button applies the
## Nintendo swap); the triggers are axes, so they get ids of their own.
const PAD_NONE := -1
const PAD_LT := 100
const PAD_RT := 101
## Everything a pad binding may use, in the order the capture prompt accepts.
const PAD_INPUTS: Array[int] = [
	JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
	JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, PAD_LT, PAD_RT,
	JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT,
]
## Out-of-the-box pad map.
const PAD_DEFAULTS: Dictionary = {
	&"ui_accept": JOY_BUTTON_A,
	&"ui_cancel": JOY_BUTTON_B,
	&"open_menu": JOY_BUTTON_START,
	## Report Bug has no pad button: Select opens each player's gear panel during play. F7
	## still opens the report form.
}
## Actions that must always keep a pad input: without them the pad can't click
## or back out. A swap that would leave one unbound is refused.
const PAD_ESSENTIAL: Array[StringName] = [CONFIRM_ACTION, CANCEL_ACTION]

const _TILE_DIR := "res://art/icons/input-prompts-pixel-16/Tiles/tile_%04d.png"
const _TILEMAP := "res://art/icons/input-prompts-pixel-16/Tilemap/tilemap_packed.png"
const _TILEMAP_COLS := 34
const _TILE_PX := 16

## Single-tile keys: keycode -> tile index in the Kenney input-prompts sheet.
const _SINGLE_TILES: Dictionary = {
	KEY_ESCAPE: 17,
	KEY_F1: 18, KEY_F2: 19, KEY_F3: 20, KEY_F4: 21, KEY_F5: 22, KEY_F6: 23,
	KEY_F7: 24, KEY_F8: 25, KEY_F9: 26, KEY_F10: 27, KEY_F11: 28, KEY_F12: 29,
	KEY_1: 51, KEY_2: 52, KEY_3: 53, KEY_4: 54, KEY_5: 55,
	KEY_6: 56, KEY_7: 57, KEY_8: 58, KEY_9: 59, KEY_0: 60,
	KEY_MINUS: 61, KEY_EQUAL: 63,
	KEY_Q: 85, KEY_W: 86, KEY_E: 87, KEY_R: 88, KEY_T: 89,
	KEY_Y: 90, KEY_U: 91, KEY_I: 92, KEY_O: 93, KEY_P: 94,
	KEY_BRACKETLEFT: 95, KEY_BRACKETRIGHT: 96, KEY_BACKSLASH: 99,
	KEY_A: 120, KEY_S: 121, KEY_D: 122, KEY_F: 123, KEY_G: 124,
	KEY_H: 125, KEY_J: 126, KEY_K: 127, KEY_L: 128,
	KEY_APOSTROPHE: 129, KEY_SEMICOLON: 132,
	KEY_SPACE: 153,
	KEY_Z: 155, KEY_X: 156, KEY_C: 157, KEY_V: 158, KEY_B: 159, KEY_N: 160, KEY_M: 161,
	KEY_SLASH: 165,
	KEY_UP: 166, KEY_RIGHT: 167, KEY_DOWN: 168, KEY_LEFT: 169,
	KEY_PERIOD: 197, KEY_COMMA: 231,
}

## Two-tile (wide) keys: keycode -> index of the left tile; the right half is
## the next tile over, so they're cut from the packed tilemap as one region.
const _WIDE_TILES: Dictionary = {
	KEY_BACKSPACE: 66,
	KEY_ENTER: 134, KEY_KP_ENTER: 134,
	KEY_ALT: 187, KEY_TAB: 189, KEY_DELETE: 191, KEY_END: 193,
	KEY_CTRL: 221, KEY_CAPSLOCK: 223, KEY_HOME: 225,
	KEY_PAGEUP: 227, KEY_PAGEDOWN: 229,
	KEY_SHIFT: 255, KEY_INSERT: 257,
}

## Pad input -> prompt tile. Face buttons are drawn by letter, so the glyph
## holds under either layout (Options "Nintendo Layout").
const _PAD_INPUT_TILES: Dictionary = {
	JOY_BUTTON_A: 4, JOY_BUTTON_B: 5, JOY_BUTTON_X: 6, JOY_BUTTON_Y: 7,
	JOY_BUTTON_START: 617, JOY_BUTTON_BACK: 616,
	JOY_BUTTON_LEFT_STICK: 416, JOY_BUTTON_RIGHT_STICK: 484,
	JOY_BUTTON_DPAD_UP: 35, JOY_BUTTON_DPAD_RIGHT: 36,
	JOY_BUTTON_DPAD_DOWN: 37, JOY_BUTTON_DPAD_LEFT: 38,
	JOY_BUTTON_LEFT_SHOULDER: 553, JOY_BUTTON_RIGHT_SHOULDER: 554, PAD_LT: 551, PAD_RT: 552,
}
const _PAD_INPUT_NAMES: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Select",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "Up", JOY_BUTTON_DPAD_RIGHT: "Right",
	JOY_BUTTON_DPAD_DOWN: "Down", JOY_BUTTON_DPAD_LEFT: "Left",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", PAD_LT: "LT", PAD_RT: "RT",
}

## Effective pad map: action -> input. Seeded from PAD_DEFAULTS + saved overrides
## by apply_saved; rebind_pad / reset_defaults keep it current.
static var _pad_binds: Dictionary = PAD_DEFAULTS.duplicate()

## True while the Keybindings window is up: screens should ignore their hotkeys
## so a key pressed to rebind (or a stray hotkey) can't open windows underneath it.
static var suppress_hotkeys: bool = false

static var _tex_cache: Dictionary = {}


## Lay the saved overrides over the project defaults. Call once at boot, after
## SaveManager has loaded global_config (it calls this from its _ready).
static func apply_saved() -> void:
	var saved: Dictionary = SaveManager.global_config.keybinds if SaveManager.global_config else {}
	for entry in REBINDABLE:
		var action: StringName = entry["action"]
		if _has_keyboard(entry) and saved.has(action) and InputMap.has_action(action):
			_set_key(action, int(saved[action]))
	_pad_binds = PAD_DEFAULTS.duplicate()
	var pad_saved: Dictionary = SaveManager.global_config.pad_binds if SaveManager.global_config else {}
	for action in pad_saved:
		## Select belongs to the gear panel now; a saved binding that put Report Bug on it
		## (the old default) is ignored rather than left to open a form mid-fight.
		if int(pad_saved[action]) == JOY_BUTTON_BACK:
			continue
		_pad_binds[StringName(action)] = int(pad_saved[action])


## Bind `keycode` to `action`. When another rebindable action already owns that
## key, the two trade keys so no key ever fires two actions.
static func rebind(action: StringName, keycode: Key) -> void:
	var old_key := primary_keycode(action)
	if old_key == keycode:
		return
	var cfg := SaveManager.global_config
	for entry in REBINDABLE:
		var other: StringName = entry["action"]
		if _has_keyboard(entry) and other != action and primary_keycode(other) == keycode \
				and _context(entry) == _context_of(action):
			_set_key(other, old_key)
			cfg.keybinds[other] = int(old_key)
	_set_key(action, keycode)
	cfg.keybinds[action] = int(keycode)
	SaveManager.save_global_config()
	SaveManager.keybinds_changed.emit()


## Back to project.godot's bindings for every action.
static func reset_defaults() -> void:
	InputMap.load_from_project_settings()
	# The per-player gameplay actions are built at runtime, not in project.godot.
	PlayerBindings.reapply()
	SaveManager.apply_pad_layout()
	SaveManager.global_config.keybinds = {}
	SaveManager.global_config.pad_binds = {}
	_pad_binds = PAD_DEFAULTS.duplicate()
	SaveManager.save_global_config()
	SaveManager.keybinds_changed.emit()


static func set_hints_enabled(on: bool) -> void:
	SaveManager.global_config.show_key_hints = on
	SaveManager.save_global_config()
	SaveManager.keybinds_changed.emit()


static func hints_enabled() -> bool:
	if Platform.is_touch_device():
		return false
	return SaveManager.global_config == null or SaveManager.global_config.show_key_hints


## The first keyboard key bound to `action` (KEY_NONE if it has none).
static func primary_keycode(action: StringName) -> Key:
	if not InputMap.has_action(action):
		return KEY_NONE
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	return KEY_NONE


## Icon for an on-screen hotkey hint, or null when hints are off / unbound.
## Follows the last-used device: pad glyphs while PadCursor.using_pad (shown even
## with Key Hints off: the pad has no other way to learn its buttons).
static func hint_texture(action: StringName) -> Texture2D:
	if PadCursor.using_pad:
		return pad_texture(action)
	if not hints_enabled():
		return null
	return key_texture(primary_keycode(action))


## Pad-prompt art for `action`'s bound input (null when it has none).
static func pad_texture(action: StringName) -> Texture2D:
	return pad_input_texture(pad_input(action))


## Prompt art for one pad input (null for PAD_NONE / unknown).
static func pad_input_texture(input: int) -> Texture2D:
	if not _PAD_INPUT_TILES.has(input):
		return null
	return load(_TILE_DIR % int(_PAD_INPUT_TILES[input]))


static func pad_input_name(input: int) -> String:
	return _PAD_INPUT_NAMES.get(input, "—")


## The pad input bound to `action` (PAD_NONE if none).
static func pad_input(action: StringName) -> int:
	return int(_pad_binds.get(action, PAD_NONE))


## The action a pad input fires (&"" when it fires nothing).
static func pad_action_for(input: int) -> StringName:
	if input == PAD_NONE:
		return &""
	for action in _pad_binds:
		if int(_pad_binds[action]) == input:
			return action
	return &""


## Bind pad `input` to `action`. Another action already on it takes `action`'s
## old input (a swap), unless that would strip an essential action (confirm,
## cancel) of its only input  then nothing changes. True when it rebound.
static func rebind_pad(action: StringName, input: int) -> bool:
	if not PAD_INPUTS.has(input):
		return false
	var old := pad_input(action)
	if old == input:
		return true
	var other := pad_action_for(input)
	if other != &"" and old == PAD_NONE and PAD_ESSENTIAL.has(other):
		return false
	var cfg := SaveManager.global_config
	if other != &"":
		_pad_binds[other] = old
		cfg.pad_binds[other] = old
	_pad_binds[action] = input
	cfg.pad_binds[action] = input
	SaveManager.save_global_config()
	SaveManager.keybinds_changed.emit()
	return true


## Letter -> physical JoyButton. Godot's ids are positional (Xbox: A bottom,
## B right, X left, Y top); the Nintendo layout prints A on the right and X on
## top, so A<->B and X<->Y swap. Its own inverse, so it also maps physical ->
## letter (pad_letter_button).
static func pad_physical_button(input: int, nintendo: bool) -> int:
	if not nintendo:
		return input
	match input:
		JOY_BUTTON_A: return JOY_BUTTON_B
		JOY_BUTTON_B: return JOY_BUTTON_A
		JOY_BUTTON_X: return JOY_BUTTON_Y
		JOY_BUTTON_Y: return JOY_BUTTON_X
	return input


static func pad_letter_button(physical: int, nintendo: bool) -> int:
	return pad_physical_button(physical, nintendo)


## Which key-uniqueness group a row belongs to (&"" = the always-live hotkeys).
static func _context(entry: Dictionary) -> StringName:
	return entry.get("context", &"")


static func _context_of(action: StringName) -> StringName:
	for entry in REBINDABLE:
		if entry["action"] == action:
			return _context(entry)
	return &""


## Actions with a keyboard binding in the window (every row but pad-only ones).
static func _has_keyboard(entry: Dictionary) -> bool:
	return entry.get("keyboard", true)


## Key-prompt art for a keycode (null for keys the sheet doesn't draw).
static func key_texture(keycode: Key) -> Texture2D:
	if keycode == KEY_NONE:
		return null
	if _tex_cache.has(keycode):
		return _tex_cache[keycode]
	var tex: Texture2D = null
	if _SINGLE_TILES.has(keycode):
		tex = load(_TILE_DIR % int(_SINGLE_TILES[keycode]))
	elif _WIDE_TILES.has(keycode):
		var idx: int = _WIDE_TILES[keycode]
		var atlas := AtlasTexture.new()
		atlas.atlas = load(_TILEMAP)
		atlas.region = Rect2((idx % _TILEMAP_COLS) * _TILE_PX, (idx / _TILEMAP_COLS) * _TILE_PX,
				_TILE_PX * 2, _TILE_PX)
		tex = atlas
	_tex_cache[keycode] = tex
	return tex


## Readable key name, for keys without prompt art.
static func key_name(keycode: Key) -> String:
	if keycode == KEY_NONE:
		return "—"
	return OS.get_keycode_string(keycode)


## Replace `action`'s keyboard events with a single `keycode`, keeping its pad
## events. KEY_NONE just clears the keyboard binding.
static func _set_key(action: StringName, keycode: Key) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	if keycode == KEY_NONE:
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

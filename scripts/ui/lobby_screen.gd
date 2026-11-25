class_name LobbyScreen
extends Control

## Local, host or join -- then everyone on this couch takes a seat and picks a hero.
##
## Seats are claimed rather than detected. "How many controllers are plugged in" is a bad proxy
## for "how many friends are sitting down", and it says nothing about who wants the keyboard.
## So the join step listens for A on any gamepad and Space on the keyboard, hands out player
## slots in the order people press, and the resulting device list is what PlayerBindings turns
## into each player's controls.
##
## The seat step is also the character select. Each seat's card shows its hero in 3D, passing
## the time (HeroPreview). Up and down -- D-pad, left stick, or W / S and the arrows -- step
## through the heroes; Confirm again locks the pick in, and Cancel takes it back. Two players
## may pick the same hero online, but not in a local or hosted world, where each hero is one
## saved character. Once every seated player is ready, Start (or Enter) begins.
##
## A local or hosted game first picks a world (the WORLD step): a saved one, whose heroes come
## back with what they found, or a new one. Joining plays in the host's world, so skips it.
##
## Every step is an ordinary menu driven by the template's pad cursor and its pointing hand. The
## join step additionally reads raw events ahead of that cursor, because it has to know *which*
## pad pressed Confirm -- the cursor flattens every pad into one. A pad that has not joined yet
## joins; one that has is passed through, so its Confirm clicks whatever the hand is on.
##
## Confirm and Cancel are whatever the template says they are (PadCursor.confirm_button), so the
## Options "Nintendo Layout" switch and any rebinding apply here too.

## `devices` is one entry per joined player, each a list of device ids for PlayerBindings.
## `heroes` is the hero each of those players picked, in the same order. `world_id` is the saved
## world to play (SaveManager.load_world), NEW_WORLD for a fresh one, or NO_WORLD when joining.
signal start_requested(mode: String, address: String, devices: Array, heroes: Array,
		world_id: int)
## The host pressed Start in the waiting room.
signal begin_requested
## Left the lobby altogether.
signal back_requested
## Backed out of hosting or joining; the session should be dropped.
signal cancel_requested

enum Step { MODE, ADDRESS, WORLD, SEATS, WAIT }

const NEW_WORLD := 0
const NO_WORLD := -1
## How many saved worlds the page lists, newest first.
const WORLDS_SHOWN := 6

const BUTTON_SIZE := Vector2(520, 56)
const KEYPAD: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "<"]
const CARD_SIZE := Vector2(300, 470)
## How far the left stick has to be pushed to step to the next hero, and how far back it has
## to come before it steps again.
const STICK_STEP := 0.6
const STICK_REARM := 0.3
## Presses are ignored this long after the seat step opens, so the A that chose the mode is
## not also read as "join".
const SEAT_INPUT_DELAY_MSEC := 250

var _step: Step = Step.MODE
var _mode: String = "offline"
## Device ids in the order they joined; index is the player slot.
var _seats: Array[int] = []
## The hero each seat has on its card, and whether that player has locked it in.
var _heroes: Array[StringName] = []
var _locked: Array[bool] = []
## Joypads whose left stick has stepped and not yet come back towards centre.
var _stick_held: Dictionary = {}
var _seats_opened_msec: int = 0
## Pad presses this screen took, as "device:button", so their releases are taken too rather
## than reaching the pad cursor as a release with no press.
var _taken_presses: Dictionary = {}

var _pages: Dictionary = {}
var _first_focus: Dictionary = {}
var _address_field: LineEdit
var _seat_cards: Array[Dictionary] = []
var _seat_hint: Label
var _seat_start: PanelButton
var _wait_status: Label
var _wait_start: PanelButton
var _mode_status: Label
var _world_list: VBoxContainer
var _world_new: PanelButton
## The world picked on the WORLD step: its id, NEW_WORLD, or NO_WORLD (joining). `_world` is the
## loaded save, for the seat cards to show each hero's kit; null for a new world or a join.
var _world_id: int = NO_WORLD
var _world: WorldSave = null
## The world whose Delete was pressed once; a second press deletes it.
var _confirm_delete: int = NO_WORLD


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(PadNav.SCOPE_GROUP)
	_build()
	NetworkManager.connection_changed.connect(_on_connection_changed)
	show_step(Step.MODE)


# --- construction -------------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.08, 0.1, 0.12)
	add_child(background)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var stack := VBoxContainer.new()
	centre.add_child(stack)

	_pages[Step.MODE] = _build_mode_page()
	_pages[Step.ADDRESS] = _build_address_page()
	_pages[Step.WORLD] = _build_world_page()
	_pages[Step.SEATS] = _build_seats_page()
	_pages[Step.WAIT] = _build_wait_page()
	for page: Control in _pages.values():
		stack.add_child(page)


func _build_mode_page() -> Control:
	var page := _page("Choose a hunt")
	_first_focus[Step.MODE] = _button(page, "Local game", func() -> void: _choose_mode("offline"))
	_button(page, "Host online game", func() -> void: _choose_mode("host"))
	_button(page, "Join online game", func() -> void: show_step(Step.ADDRESS))
	_button(page, "Back", func() -> void: back_requested.emit())
	_mode_status = _label(page, "", FontSizes.BODY, Color(0.9, 0.6, 0.4))
	return page


func _build_address_page() -> Control:
	var page := _page("Host address")

	_address_field = LineEdit.new()
	_address_field.text = SaveManager.global_config.last_join_address
	_address_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_address_field.custom_minimum_size = Vector2(BUTTON_SIZE.x, 56)
	FontSizes.apply(_address_field, FontSizes.BODY_LARGE)
	page.add_child(_address_field)

	## A number pad the gamepad can walk: an IP address is the one thing in the game that would
	## otherwise need a keyboard.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	page.add_child(grid)
	for key in KEYPAD:
		var button := PanelButton.new()
		button.text = "Del" if key == "<" else key
		button.custom_minimum_size = Vector2(120, 56)
		FontSizes.apply(button, FontSizes.BODY_LARGE)
		button.pressed.connect(_on_keypad.bind(key))
		grid.add_child(button)

	_first_focus[Step.ADDRESS] = _button(page, "Join", func() -> void: _choose_mode("join"))
	_button(page, "Back", func() -> void: show_step(Step.MODE))
	return page


## The list is filled in each time the page opens (_fill_worlds), since worlds come and go.
func _build_world_page() -> Control:
	var page := _page("Choose a world")
	_world_list = VBoxContainer.new()
	_world_list.add_theme_constant_override("separation", 10)
	page.add_child(_world_list)
	_world_new = _button(page, "New world", func() -> void: _choose_world(NEW_WORLD))
	_first_focus[Step.WORLD] = _world_new
	_button(page, "Back", func() -> void: show_step(Step.MODE))
	return page


func _fill_worlds() -> void:
	for child in _world_list.get_children():
		_world_list.remove_child(child)
		child.queue_free()
	var worlds := SaveManager.list_worlds()
	var first: Control = null
	for index in mini(worlds.size(), WORLDS_SHOWN):
		var world: WorldSave = worlds[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_world_list.add_child(row)
		var pick := _button(row, "%s   ·   %s" % [world.name, world.summary()],
				_choose_world.bind(world.id))
		pick.custom_minimum_size = Vector2(BUTTON_SIZE.x + 120.0, BUTTON_SIZE.y)
		var sure := _confirm_delete == world.id
		var delete := _small_button(row, "Sure? Delete" if sure else "Delete",
				_delete_world.bind(world.id))
		delete.custom_minimum_size = Vector2(200, BUTTON_SIZE.y)
		if first == null:
			first = delete if sure else pick
	SelectionReticle.focus_first.call_deferred(first if first != null else _world_new)


## Delete asks twice: the first press turns the button into "Sure? Delete".
func _delete_world(id: int) -> void:
	if _confirm_delete != id:
		_confirm_delete = id
	else:
		SaveManager.delete_world(id)
		_confirm_delete = NO_WORLD
	_fill_worlds()


func _choose_world(id: int) -> void:
	_world_id = id
	_world = SaveManager.load_world(id) if id != NEW_WORLD else null
	show_step(Step.SEATS)


func world_id() -> int:
	return _world_id


func _build_seats_page() -> Control:
	var page := _page("Choose your heroes")
	_seat_hint = _label(page, "", FontSizes.BODY, UiTheme.TEXT_MUTED)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(row)
	for slot in PlayerRegistry.MAX_LOCAL_SLOTS:
		var card := PanelContainer.new()
		card.custom_minimum_size = CARD_SIZE
		row.add_child(card)
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 6)
		card.add_child(column)
		var seat := _label(column, "Player %d" % (slot + 1), FontSizes.BODY, UiTheme.TEXT_MUTED)
		var up := _label(column, "▲", FontSizes.BODY, UiTheme.TEXT_MUTED)
		## The preview keeps its space while the seat is empty, so the cards do not jump about
		## as people join.
		var stage := Control.new()
		stage.custom_minimum_size = Vector2(260, 250)
		stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(stage)
		var preview := HeroPreview.new()
		stage.add_child(preview)
		var down := _label(column, "▼", FontSizes.BODY, UiTheme.TEXT_MUTED)
		var hero := _label(column, "", FontSizes.HEADING_SMALL, Color.WHITE)
		var blurb := _label(column, "", FontSizes.BODY, UiTheme.TEXT_MUTED)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		## Two lines' room whatever the hero, so every card lines up.
		blurb.custom_minimum_size = Vector2(CARD_SIZE.x - 30.0, 76.0)
		blurb.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		## What this world remembers of the hero: "New hero", or what they carry.
		var saved := _label(column, "", FontSizes.BODY, Color(0.95, 0.85, 0.5))
		saved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		saved.custom_minimum_size = Vector2(CARD_SIZE.x - 30.0, 0.0)
		var status := _label(column, "", FontSizes.BODY, Color.WHITE)
		var device := _label(column, "", FontSizes.BODY, Color.WHITE)
		_seat_cards.append({"card": card, "seat": seat, "up": up, "down": down,
				"preview": preview, "hero": hero, "blurb": blurb, "saved": saved,
				"status": status, "device": device})

	## No keyboard focus on these: Space means "join" here and would press a focused button by
	## accident. The pad's hand and the mouse click them; the keyboard uses Enter and Escape.
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	page.add_child(buttons)
	var back := _small_button(buttons, "Back", _leave_seats)
	back.button_focus_mode = Control.FOCUS_NONE
	_seat_start = _small_button(buttons, "Start", _confirm_seats)
	_seat_start.button_focus_mode = Control.FOCUS_NONE
	return page


func _build_wait_page() -> Control:
	var page := _page("Lobby")
	_wait_status = _label(page, "", FontSizes.BODY_LARGE, Color.WHITE)
	_wait_start = _button(page, "Start the hunt", func() -> void: begin_requested.emit())
	_first_focus[Step.WAIT] = _button(page, "Cancel", func() -> void:
		cancel_requested.emit()
		show_step(Step.MODE))
	return page


func _page(title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	_label(page, title, FontSizes.HEADING_LARGE, UiTheme.TEXT_HEADING)
	return page


func _label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	FontSizes.apply(label, font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> PanelButton:
	var button := PanelButton.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	FontSizes.apply(button, FontSizes.BODY_LARGE)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _small_button(parent: Control, text: String, action: Callable) -> PanelButton:
	var button := _button(parent, text, action)
	button.custom_minimum_size = Vector2(220, 56)
	return button


# --- steps --------------------------------------------------------------------------------

func show_step(step: Step) -> void:
	_step = step
	for key: Step in _pages:
		(_pages[key] as Control).visible = key == step
	_taken_presses.clear()
	if step == Step.WORLD:
		_confirm_delete = NO_WORLD
		_fill_worlds()
		return
	if step == Step.SEATS:
		_seats.clear()
		_heroes.clear()
		_locked.clear()
		_stick_held.clear()
		_seats_opened_msec = Time.get_ticks_msec()
		_refresh_seats()
		var owner_of_focus := get_viewport().gui_get_focus_owner()
		if owner_of_focus != null:
			owner_of_focus.release_focus()
	elif _first_focus.has(step):
		SelectionReticle.focus_first.call_deferred(_first_focus[step])


## Back to the first page with a message, e.g. after a failed join.
func show_message(text: String) -> void:
	visible = true
	show_step(Step.MODE)
	_mode_status.text = text


## The waiting room shown after hosting or while connecting. Only a host gets a Start button.
func show_wait(text: String, can_start: bool) -> void:
	visible = true
	_wait_status.text = text
	_wait_start.visible = can_start
	show_step(Step.WAIT)
	if can_start:
		SelectionReticle.focus_first.call_deferred(_wait_start)


func set_status(text: String) -> void:
	_wait_status.text = text
	_mode_status.text = text


func _choose_mode(mode: String) -> void:
	_mode = mode
	_mode_status.text = ""
	if mode == "join":
		SaveManager.global_config.last_join_address = _address_field.text.strip_edges()
		SaveManager.save_global_config()
		_world_id = NO_WORLD
		_world = null
		show_step(Step.SEATS)
		return
	show_step(Step.WORLD)


func _on_keypad(key: String) -> void:
	if key == "<":
		_address_field.text = _address_field.text.left(-1)
	else:
		_address_field.text += key


# --- claiming seats -----------------------------------------------------------------------

## _input rather than _unhandled_input: scene nodes are offered events before the pad cursor
## autoload, which would otherwise turn every pad's Confirm into the same anonymous click.
func _input(event: InputEvent) -> void:
	if _step != Step.SEATS or not is_visible_in_tree():
		return
	var button := event as InputEventJoypadButton
	var motion := event as InputEventJoypadMotion
	var key := event as InputEventKey
	if button != null:
		_on_seat_button(button)
	elif motion != null:
		_on_seat_stick(motion)
	elif key != null and key.pressed and not key.echo and _seats_open():
		_on_seat_key(key)


func _seats_open() -> bool:
	return Time.get_ticks_msec() - _seats_opened_msec >= SEAT_INPUT_DELAY_MSEC


func _on_seat_button(button: InputEventJoypadButton) -> void:
	var press_id := "%d:%d" % [button.device, button.button_index]
	if not button.pressed:
		if _taken_presses.erase(press_id):
			get_viewport().set_input_as_handled()
		return
	if not _seats_open():
		return
	var device := button.device
	var joined := _seats.has(device)
	var taken := true
	if button.button_index == PadCursor.confirm_button():
		if joined:
			set_ready(device, true)
		else:
			claim_seat(device)
	elif button.button_index == PadCursor.cancel_button():
		_back_out(device)
	elif button.button_index == JOY_BUTTON_START and joined:
		_confirm_seats()
	elif joined and button.button_index == JOY_BUTTON_DPAD_UP:
		step_hero(device, -1)
	elif joined and button.button_index == JOY_BUTTON_DPAD_DOWN:
		step_hero(device, 1)
	else:
		## Everything else -- left and right on the D-pad, and anything from a pad that has not
		## joined -- is the pad cursor's: it moves the hand and clicks what it points at.
		taken = false
	if taken:
		_taken_presses[press_id] = true
		get_viewport().set_input_as_handled()


## The left stick steps through heroes like the D-pad: one step per push, re-armed once the
## stick comes most of the way back.
func _on_seat_stick(motion: InputEventJoypadMotion) -> void:
	if motion.axis != JOY_AXIS_LEFT_Y or not _seats.has(motion.device):
		return
	get_viewport().set_input_as_handled()
	var value := motion.axis_value
	if _stick_held.get(motion.device, false):
		if absf(value) < STICK_REARM:
			_stick_held[motion.device] = false
		return
	if absf(value) >= STICK_STEP and _seats_open():
		_stick_held[motion.device] = true
		step_hero(motion.device, 1 if value > 0.0 else -1)


func _on_seat_key(key: InputEventKey) -> void:
	var device := PlayerBindings.KEYBOARD
	var joined := _seats.has(device)
	match key.physical_keycode:
		KEY_SPACE:
			if joined:
				set_ready(device, true)
			else:
				claim_seat(device)
		KEY_ESCAPE:
			_back_out(device)
		KEY_W, KEY_UP:
			if not joined:
				return
			step_hero(device, -1)
		KEY_S, KEY_DOWN:
			if not joined:
				return
			step_hero(device, 1)
		KEY_ENTER, KEY_KP_ENTER:
			if joined:
				_confirm_seats()
		_:
			return
	get_viewport().set_input_as_handled()


## Cancel, one layer at a time: a locked-in pick is unlocked, then the seat is given up, then
## (with nobody seated) the step itself is left.
func _back_out(device: int) -> void:
	var seat := _seats.find(device)
	if seat >= 0 and _locked[seat]:
		set_ready(device, false)
	elif seat >= 0:
		release_seat(device)
	elif _seats.is_empty():
		_leave_seats()


func claim_seat(device: int) -> void:
	if _seats.has(device) or _seats.size() >= PlayerRegistry.MAX_LOCAL_SLOTS:
		return
	_seats.append(device)
	## Each new seat starts on the next hero along, so a couch that just mashes A gets a mix --
	## in a world, the next one nobody else has.
	var seat := _seats.size() - 1
	_heroes.append(ArchetypeDB.default_for_slot(seat))
	if not _hero_free(_heroes[seat], seat):
		_heroes[seat] = _next_free(_heroes[seat], 1, seat)
	_locked.append(false)
	_refresh_seats()


func release_seat(device: int) -> void:
	var seat := _seats.find(device)
	if seat < 0:
		return
	_seats.remove_at(seat)
	_heroes.remove_at(seat)
	_locked.remove_at(seat)
	_refresh_seats()


## Moves a seated, undecided player `steps` heroes along.
func step_hero(device: int, steps: int) -> void:
	var seat := _seats.find(device)
	if seat < 0 or _locked[seat]:
		return
	_heroes[seat] = _next_free(_heroes[seat], steps, seat)
	_refresh_seats()


## Whether `hero` may sit on `seat`: anywhere when joining someone, but in a local or hosted
## world each hero is one saved character, so no two seats may hold the same one.
func _hero_free(hero: StringName, seat: int) -> bool:
	if _world_id == NO_WORLD:
		return true
	for other in _heroes.size():
		if other != seat and _heroes[other] == hero:
			return false
	return true


## The hero `steps` along from `from` (one way or the other), skipping any another seat holds.
func _next_free(from: StringName, steps: int, seat: int) -> StringName:
	var hero := from
	for attempt in ArchetypeDB.ORDER.size():
		hero = ArchetypeDB.step(hero, steps)
		if _hero_free(hero, seat):
			return hero
		steps = signi(steps)
	return from


func set_ready(device: int, locked: bool) -> void:
	var seat := _seats.find(device)
	if seat < 0 or _locked[seat] == locked:
		return
	_locked[seat] = locked
	if locked:
		(_seat_cards[seat]["preview"] as HeroPreview).cheer()
	_refresh_seats()


func seats() -> Array[int]:
	return _seats


func heroes() -> Array[StringName]:
	return _heroes


func is_ready(device: int) -> bool:
	var seat := _seats.find(device)
	return seat >= 0 and _locked[seat]


## Somebody is seated and everybody seated has locked in.
func all_ready() -> bool:
	return not _seats.is_empty() and not _locked.has(false)


func _refresh_seats() -> void:
	for slot in _seat_cards.size():
		var card: Dictionary = _seat_cards[slot]
		var taken := slot < _seats.size()
		var locked := taken and _locked[slot]
		var preview := card["preview"] as HeroPreview
		preview.visible = taken
		var archetype := ArchetypeDB.get_archetype(_heroes[slot]) if taken else null
		var device := card["device"] as Label
		var hero := card["hero"] as Label
		var status := card["status"] as Label
		if archetype != null:
			preview.show_hero(archetype.id)
			hero.text = archetype.display_name
			hero.add_theme_color_override("font_color", archetype.color)
			(card["blurb"] as Label).text = archetype.blurb
			(card["saved"] as Label).text = _saved_line(archetype.id)
			device.text = PlayerBindings.device_label(_seats[slot])
			status.text = "Ready!" if locked else "Choose, then A / Space"
			status.add_theme_color_override("font_color",
					Color(0.6, 1.0, 0.55) if locked else Color.WHITE)
		else:
			hero.text = ""
			(card["blurb"] as Label).text = ""
			(card["saved"] as Label).text = ""
			device.text = ""
			status.text = "Press A or Space to join"
			status.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		## The arrows say the pick can still change; once it is locked they go.
		(card["up"] as Label).modulate.a = 1.0 if taken and not locked else 0.0
		(card["down"] as Label).modulate.a = 1.0 if taken and not locked else 0.0
		var colour: Color = archetype.color if archetype != null else UiTheme.TEXT_DISABLED
		(card["card"] as PanelContainer).add_theme_stylebox_override("panel",
				UiTheme.slot_style(colour if locked else colour.darkened(0.45) if taken \
						else UiTheme.TEXT_DISABLED))
	_seat_start.disabled = not all_ready()
	if _seats.is_empty():
		_seat_hint.text = "Press A on a gamepad or Space on the keyboard to join"
	elif all_ready():
		_seat_hint.text = "Everyone is ready  ·  Start / Enter to begin   ·   B / Esc to change your mind"
	else:
		_seat_hint.text = "Up / Down: choose a hero   ·   A / Space: ready   ·   B / Esc: back"


## What the chosen world remembers of `hero`, for their card: "New hero" or their kit.
func _saved_line(hero: StringName) -> String:
	if _world_id == NO_WORLD:
		return ""
	var state := WorldPersistence.character_for(_world, hero)
	if state.is_empty():
		return "New hero"
	var parts: Array[String] = []
	parts.append("%d hearts" % (int(state.get("max_health", 0)) / Combatant.POINTS_PER_HEART))
	var found: Array[String] = []
	var archetype := ArchetypeDB.get_archetype(hero)
	for id in state.get("gear", []):
		var item := StringName(str(id))
		if ItemDB.exists(item) and (archetype == null or not archetype.starting_gear.has(item)):
			found.append(ItemDB.display_name(item).to_lower())
	if not found.is_empty():
		parts.append(", ".join(found))
	if int(state.get("armor_level", 0)) > 0:
		parts.append("armour %d" % int(state["armor_level"]))
	return "Saved: " + "  ·  ".join(parts)


func _leave_seats() -> void:
	show_step(Step.ADDRESS if _mode == "join" else Step.WORLD)


func _confirm_seats() -> void:
	if not all_ready():
		return
	var devices: Array = []
	for device in _seats:
		devices.append([device])
	start_requested.emit(_mode, _address_field.text.strip_edges(), devices, _heroes.duplicate(),
			_world_id)


func _on_connection_changed() -> void:
	if NetworkManager.mode == NetworkManager.Mode.HOST and visible and _step == Step.WAIT:
		_wait_status.text = "Hosting on port %d  ·  %d player(s) in the lobby" % [
			Transport.DEFAULT_PORT, PlayerRegistry.roster.size()]

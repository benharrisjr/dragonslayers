class_name LobbyScreen
extends Control

## Local, host or join -- then everyone on this couch presses a button to take a seat.
##
## Seats are claimed rather than detected. "How many controllers are plugged in" is a bad proxy
## for "how many friends are sitting down", and it says nothing about who wants the keyboard.
## So the join step listens for A on any gamepad and Space on the keyboard, hands out player
## slots in the order people press, and the resulting device list is what PlayerBindings turns
## into each player's controls.
##
## Every step is an ordinary menu driven by the template's pad cursor and its pointing hand. The
## join step additionally reads raw events ahead of that cursor, because it has to know *which*
## pad pressed Confirm -- the cursor flattens every pad into one. A pad that has not joined yet
## joins; one that has is passed through, so its Confirm clicks whatever the hand is on.
##
## Confirm and Cancel are whatever the template says they are (PadCursor.confirm_button), so the
## Options "Nintendo Layout" switch and any rebinding apply here too.

## `devices` is one entry per joined player, each a list of device ids for PlayerBindings.
signal start_requested(mode: String, address: String, devices: Array)
## The host pressed Start in the waiting room.
signal begin_requested
## Left the lobby altogether.
signal back_requested
## Backed out of hosting or joining; the session should be dropped.
signal cancel_requested

enum Step { MODE, ADDRESS, SEATS, WAIT }

const BUTTON_SIZE := Vector2(520, 56)
const KEYPAD: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "<"]
const CARD_SIZE := Vector2(300, 220)
## Presses are ignored this long after the seat step opens, so the A that chose the mode is
## not also read as "join".
const SEAT_INPUT_DELAY_MSEC := 250

var _step: Step = Step.MODE
var _mode: String = "offline"
## Device ids in the order they joined; index is the player slot.
var _seats: Array[int] = []
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


func _build_seats_page() -> Control:
	var page := _page("Who is playing?")
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
		column.add_theme_constant_override("separation", 10)
		card.add_child(column)
		var archetype := ArchetypeDB.get_archetype(ArchetypeDB.default_for_slot(slot))
		var seat := _label(column, "Player %d" % (slot + 1), FontSizes.BODY, UiTheme.TEXT_MUTED)
		var hero := _label(column, archetype.display_name, FontSizes.HEADING_SMALL, archetype.color)
		var device := _label(column, "", FontSizes.BODY, Color.WHITE)
		_seat_cards.append({"card": card, "seat": seat, "hero": hero, "device": device,
				"color": archetype.color})

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
	if step == Step.SEATS:
		_seats.clear()
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
	show_step(Step.SEATS)


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
	var key := event as InputEventKey
	if button != null:
		_on_seat_button(button)
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
	if button.button_index == PadCursor.confirm_button() and not joined:
		claim_seat(device)
	elif button.button_index == PadCursor.cancel_button():
		if joined:
			release_seat(device)
		elif _seats.is_empty():
			_leave_seats()
	elif button.button_index == JOY_BUTTON_START and joined:
		_confirm_seats()
	else:
		## Everything else -- the D-pad, and Confirm from someone already seated -- is the
		## pad cursor's: it moves the hand and clicks what it points at.
		taken = false
	if taken:
		_taken_presses[press_id] = true
		get_viewport().set_input_as_handled()


func _on_seat_key(key: InputEventKey) -> void:
	var device := PlayerBindings.KEYBOARD
	match key.physical_keycode:
		KEY_SPACE:
			claim_seat(device)
		KEY_ESCAPE:
			if _seats.has(device):
				release_seat(device)
			elif _seats.is_empty():
				_leave_seats()
		KEY_ENTER, KEY_KP_ENTER:
			if _seats.has(device):
				_confirm_seats()
		_:
			return
	get_viewport().set_input_as_handled()


func claim_seat(device: int) -> void:
	if _seats.has(device) or _seats.size() >= PlayerRegistry.MAX_LOCAL_SLOTS:
		return
	_seats.append(device)
	_refresh_seats()
	## Put the hand on Start, so the same button pressed again begins the hunt.
	if device != PlayerBindings.KEYBOARD:
		PadCursor.point_at.call_deferred(_seat_start.get_focus_target())


func release_seat(device: int) -> void:
	_seats.erase(device)
	_refresh_seats()


func seats() -> Array[int]:
	return _seats


func _refresh_seats() -> void:
	for slot in _seat_cards.size():
		var card: Dictionary = _seat_cards[slot]
		var taken := slot < _seats.size()
		(card["device"] as Label).text = PlayerBindings.device_label(_seats[slot]) if taken \
				else "Press A or Space"
		(card["device"] as Label).modulate = Color.WHITE if taken else Color(1, 1, 1, 0.45)
		(card["hero"] as Label).modulate = Color.WHITE if taken else Color(1, 1, 1, 0.35)
		(card["card"] as PanelContainer).add_theme_stylebox_override("panel",
				UiTheme.slot_style(card["color"] if taken else UiTheme.TEXT_DISABLED))
	_seat_start.disabled = _seats.is_empty()
	_seat_hint.text = "A / Space to join   ·   B / Esc to leave   ·   A on Start, or Enter, to begin" \
			if not _seats.is_empty() else "Press A on a gamepad or Space on the keyboard to join"


func _leave_seats() -> void:
	show_step(Step.ADDRESS if _mode == "join" else Step.MODE)


func _confirm_seats() -> void:
	if _seats.is_empty():
		return
	var devices: Array = []
	for device in _seats:
		devices.append([device])
	start_requested.emit(_mode, _address_field.text.strip_edges(), devices)


func _on_connection_changed() -> void:
	if NetworkManager.mode == NetworkManager.Mode.HOST and visible and _step == Step.WAIT:
		_wait_status.text = "Hosting on port %d  ·  %d player(s) in the lobby" % [
			Transport.DEFAULT_PORT, PlayerRegistry.roster.size()]

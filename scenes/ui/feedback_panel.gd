class_name FeedbackPanel extends ModalPanel
## The report_bug form (FeedbackReporter opens it on its own CanvasLayer): pick
## Bug / Feedback, type a message, optionally keep the screenshot taken
## just before it opened, Send. Game version, report context and the log tail ride
## along automatically (FeedbackReporter.build_context / read_log_tail).

const _CATEGORY_LABELS := {&"bug": "Bug", &"feedback": "Feedback"}
const _THUMB_SIZE := Vector2(256, 144)
## How long the "Thanks!" status stays up before the form closes itself.
const _CLOSE_AFTER_SEC := 1.5

## Set by FeedbackReporter before the panel enters the tree.
var screenshot: Image = null
## Crash mode (FeedbackReporter.offer_crash_report): asks whether to send the
## last session's crash log. Always a bug, no screenshot, the note is optional.
var crash_report: bool = false

var _category: StringName = &"bug"
var _category_buttons: Dictionary = {}  # StringName -> PanelButton
var _message: TextEdit
var _shot_check: CheckBox
var _count_label: Label
var _status: Label
var _send_btn: PanelButton
var _cancel_btn: PanelButton
var _sending: bool = false
var _prev_suppress: bool = false


func _init() -> void:
	z_index = 5
	drop_in = true
	panel_margin = 24
	content_separation = 12
	panel_min_size = Vector2(720, 0)


func _build_content() -> void:
	# Hotkeys (items, abilities, Options) must not fire while typing.
	_prev_suppress = Keybinds.suppress_hotkeys
	Keybinds.suppress_hotkeys = true
	tree_exiting.connect(func() -> void: Keybinds.suppress_hotkeys = _prev_suppress)

	var title := Label.new()
	title.text = "The Game Closed Unexpectedly" if crash_report else "Report a Bug / Send Feedback"
	FontSizes.apply(title, FontSizes.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	content.add_child(title)

	content.add_child(HSeparator.new())

	if crash_report:
		var ask := Label.new()
		var n := FeedbackReporter.crash_error_count()
		ask.text = "Your last session ended without closing normally%s. Send a crash report so it can be fixed?" \
				% (" (%d error%s logged)" % [n, "" if n == 1 else "s"] if n > 0 else "")
		ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		FontSizes.apply(ask, FontSizes.BODY_LARGE)
		content.add_child(ask)

	var cat_row := HBoxContainer.new()
	cat_row.visible = not crash_report
	cat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cat_row.add_theme_constant_override("separation", 12)
	content.add_child(cat_row)
	for cat in FeedbackReporter.CATEGORIES:
		var btn := PanelButton.new()
		btn.text = _CATEGORY_LABELS[cat]
		btn.custom_minimum_size = Vector2(150, 40)
		FontSizes.apply(btn, FontSizes.BODY_LARGE)
		btn.pressed.connect(_select_category.bind(cat))
		cat_row.add_child(btn)
		_category_buttons[cat] = btn
	_select_category(_category)

	_message = TextEdit.new()
	_message.placeholder_text = "What were you doing when it closed? (optional)" if crash_report \
			else "What happened? What did you expect?"
	_message.custom_minimum_size = Vector2(0, 170)
	_message.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	FontSizes.apply(_message, FontSizes.BODY)
	_message.text_changed.connect(_on_text_changed)
	_message.focus_entered.connect(_on_message_focused)
	# The pad hand can point at it; clicking it focuses it (and on a Deck,
	# raises the Steam keyboard).
	_message.add_to_group(PadNav.TARGET_GROUP)
	content.add_child(_message)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	FontSizes.apply(_count_label, FontSizes.BODY)
	_count_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	content.add_child(_count_label)

	var shot_row := HBoxContainer.new()
	shot_row.visible = not crash_report
	shot_row.add_theme_constant_override("separation", 16)
	content.add_child(shot_row)
	if screenshot:
		var thumb := TextureRect.new()
		thumb.texture = ImageTexture.create_from_image(screenshot)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.custom_minimum_size = _THUMB_SIZE
		shot_row.add_child(thumb)
	var shot_col := VBoxContainer.new()
	shot_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shot_col.alignment = BoxContainer.ALIGNMENT_CENTER
	shot_row.add_child(shot_col)
	_shot_check = CheckBox.new()
	_shot_check.text = "Include screenshot"
	_shot_check.button_pressed = screenshot != null
	_shot_check.disabled = screenshot == null
	FontSizes.apply(_shot_check, FontSizes.BODY_LARGE)
	shot_col.add_child(_shot_check)
	var note := Label.new()
	note.text = "Also sends the game version, a few game details and a recent log."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	FontSizes.apply(note, FontSizes.BODY)
	note.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	if crash_report:
		note.text = "Sends the game version, your system info and the last session's log."
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(note)
	else:
		shot_col.add_child(note)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	FontSizes.apply(_status, FontSizes.BODY_LARGE)
	content.add_child(_status)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	content.add_child(footer)
	_cancel_btn = PanelButton.new()
	_cancel_btn.text = "No Thanks" if crash_report else "Cancel"
	_cancel_btn.custom_minimum_size = Vector2(130, 40)
	FontSizes.apply(_cancel_btn, FontSizes.BODY_LARGE)
	_cancel_btn.pressed.connect(_on_back)
	footer.add_child(_cancel_btn)
	_send_btn = PanelButton.new()
	_send_btn.text = "Send Report" if crash_report else "Send"
	_send_btn.texture = PanelButton.GREEN_TEX
	_send_btn.custom_minimum_size = Vector2(130, 40)
	FontSizes.apply(_send_btn, FontSizes.BODY_LARGE)
	_send_btn.pressed.connect(_on_send)
	footer.add_child(_send_btn)

	FeedbackReporter.submitted.connect(_on_submitted)
	if not FeedbackReporter.is_configured():
		_set_status("Feedback isn't configured in this build.", false)
	_refresh()


func _first_focus() -> Control:
	# The crash note is optional: land on Send rather than raise a keyboard.
	return _send_btn if crash_report else _message


func _on_back() -> void:
	# The request finishes on its own; closing just stops showing its result.
	request_close()


func _select_category(cat: StringName) -> void:
	_category = cat
	for c in _category_buttons:
		# The chosen category is the green tile; the rest keep the stock one.
		(_category_buttons[c] as PanelButton).texture = PanelButton.GREEN_TEX if c == cat else null


func _on_text_changed() -> void:
	if _message.text.length() > FeedbackReporter.MAX_MESSAGE_CHARS:
		var caret := _message.get_caret_column()
		_message.text = _message.text.left(FeedbackReporter.MAX_MESSAGE_CHARS)
		_message.set_caret_line(_message.get_line_count() - 1)
		_message.set_caret_column(mini(caret, _message.get_line(_message.get_line_count() - 1).length()))
	_refresh()


func _on_message_focused() -> void:
	if PadCursor.using_pad:
		# Steam wants window pixels, not the stretched canvas's.
		SteamManager.show_text_input(
				get_viewport().get_screen_transform() * _message.get_global_rect(), true)


func _refresh() -> void:
	var n := _message.text.strip_edges().length()
	_count_label.text = "%d / %d" % [n, FeedbackReporter.MAX_MESSAGE_CHARS]
	_send_btn.disabled = _sending or (n == 0 and not crash_report) or not FeedbackReporter.is_configured()


func _on_send() -> void:
	if _sending or _send_btn.disabled:
		return
	_sending = true
	_set_status("Sending…", true)
	_refresh()
	if crash_report:
		FeedbackReporter.submit_crash(_message.text)
	else:
		FeedbackReporter.submit(_category, _message.text,
				screenshot if _shot_check.button_pressed else null)


func _on_submitted(ok: bool, message: String) -> void:
	_sending = false
	_set_status(message, ok)
	_refresh()
	if ok:
		_send_btn.disabled = true
		get_tree().create_timer(_CLOSE_AFTER_SEC, true).timeout.connect(func() -> void:
			if is_inside_tree():
				request_close())


func _set_status(text: String, ok: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color",
			Color(0.6, 1.0, 0.6) if ok else Color(1.0, 0.6, 0.5))

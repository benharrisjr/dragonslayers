class_name PatchNotesPanel extends ModalPanel
## Patch notes browser (PatchNotes). Opened from the main menu's version button, or
## automatically once after an update. Previous / Next page through every release
## that has notes; `start_version` picks the entry it opens on (newest if unset).

var start_version: String = ""

var _entries: Array[Dictionary] = []
var _index: int = 0
var _version_lbl: Label
var _scroll: ScrollContainer
var _body: RichTextLabel
var _older_btn: PanelButton
var _newer_btn: PanelButton
var _close_btn: PanelButton


func _first_focus() -> Control:
	return _close_btn


func _init() -> void:
	z_index = 20
	backdrop_alpha = 0.6  # dimmed: the panel's frame is see-through and the menu buttons fought the text
	panel_margin = 28
	content_separation = 14
	panel_min_size = Vector2(620, 560)


## Re-point an already built panel at `version` (newest when empty).
func show_version(version: String) -> void:
	start_version = version
	_entries = PatchNotes.released()
	_index = 0
	for i in _entries.size():
		if PatchNotes.compare(_entries[i]["version"], version) == 0:
			_index = i
	if _body != null:
		_refresh()


func _build_content() -> void:
	var title := Label.new()
	title.text = "Patch Notes"
	FontSizes.apply(title, FontSizes.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.TEXT_HEADING)
	content.add_child(title)

	_version_lbl = Label.new()
	FontSizes.apply(_version_lbl, FontSizes.BODY_LARGE)
	# Atkinson: version numbers must stay legible whatever the game font is.
	_version_lbl.add_theme_font_override("font", UIFont.READABLE_FILE)
	_version_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	content.add_child(_version_lbl)

	content.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 360)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.clip_contents = false  # tall pixel-font glyphs (see FontSizes notes)
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", FontSizes.size_of(FontSizes.BODY))
	_body.add_theme_color_override("default_color", Color(0.88, 0.88, 0.88))
	_body.add_theme_constant_override("line_separation", 4)
	_scroll.add_child(_body)

	_older_btn = _make_button("< Previous")
	_older_btn.pressed.connect(func() -> void: _step(1))
	_close_btn = _make_button("Close", PanelButton.RED_TEX)
	_close_btn.pressed.connect(request_close)
	_newer_btn = _make_button("Next >")
	_newer_btn.pressed.connect(func() -> void: _step(-1))

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	content.add_child(footer)
	footer.add_child(_older_btn)
	footer.add_child(_close_btn)
	footer.add_child(_newer_btn)

	show_version(start_version)


func _make_button(label: String, tex: Texture2D = null) -> PanelButton:
	var btn := PanelButton.new()
	btn.text = label
	if tex != null:
		btn.texture = tex
	btn.custom_minimum_size = Vector2(130, 40)
	FontSizes.apply(btn, FontSizes.BODY_LARGE)
	return btn


## `delta` +1 = one release older (NOTES is newest first), -1 = newer.
func _step(delta: int) -> void:
	var next := clampi(_index + delta, 0, maxi(0, _entries.size() - 1))
	if next == _index:
		return
	_index = next
	_refresh()


func _refresh() -> void:
	if _entries.is_empty():
		_version_lbl.text = "Version " + PatchNotes.current_version()
		_body.text = "No patch notes yet."
	else:
		var entry: Dictionary = _entries[_index]
		_version_lbl.text = "Version " + str(entry["version"])
		_body.text = PatchNotes.to_bbcode(entry["text"])
	_older_btn.visible = _index < _entries.size() - 1
	_newer_btn.visible = _index > 0
	# Paging can hide the button the hand was on; land it on Close instead.
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != null and not focused.is_visible_in_tree():
		_close_btn.grab_focus()
	_scroll.scroll_vertical = 0

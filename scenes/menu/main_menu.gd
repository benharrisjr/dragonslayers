extends Control

## The main menu: title, Play / Options / Achievements, a secondary row (Save
## Slots, Links, Credits, Quit) and the version button that opens patch notes.
## Built in code; main_menu.tscn only carries the exports below.

## Drawn behind everything. Swap for the game's own backdrop scene.
@export var background_scene: PackedScene
## The game's logo. Empty = the project name as text.
@export var title_logo: Texture2D
## Looping menu music, if any.
@export var music: AudioStream

const MAIN_BUTTON_SIZE := Vector2(280, 64)
const SIDE_BUTTON_SIZE := Vector2(150, 48)
const SIDE_GAP := 12
const TITLE_TOP := 140.0
const TITLE_LOGO_MAX_SIZE := Vector2(720, 300)
const BUTTONS_TOP := 420.0

# Save-slot rows: a floor height, plus the vertical padding the stacked slot
# name / detail labels need inside their inner margins.
const SLOT_ROW_MIN_HEIGHT := 60.0
const SLOT_ROW_PADDING := 16.0
const CURRENT_SLOT_ICON := preload("res://art/icons/individual_32x32/icon016.png")

var _play_button: PanelButton = null
## Lazily built windows, by name. Each is hidden (not freed) when closed.
var _panels: Dictionary = {}
## Code-built overlays (save slots, confirms) that aren't ModalPanels; tracked
## so ui_cancel can dismiss the topmost one.
var _transient_overlays: Array[Control] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(PadNav.SCOPE_GROUP)  # D-pad hand navigation (PadNav)
	if background_scene:
		add_child(background_scene.instantiate())
	_build_title()
	_build_buttons()
	_add_version_button()

	if music:
		SoundManager.play_music(music)
	else:
		SoundManager.stop_music()
	SoundManager.stop_ambience()

	# Seed keyboard/gamepad focus so navigation has a starting element. Deferred
	# so every button is in the tree first.
	SelectionReticle.call_deferred("focus_first", _play_button)
	_after_intro.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _transient_overlays.is_empty():
		get_viewport().set_input_as_handled()
		_transient_overlays.back().queue_free()
		return
	# The menu hotkey (Escape / Start by default) toggles Options. An open
	# window's own ui_cancel handler runs first (it's a child), so this only
	# sees the key when nothing else took it.
	if event.is_action_pressed("open_menu") and not Keybinds.suppress_hotkeys:
		var options: ModalPanel = _panels.get(&"options")
		if options and options.visible:
			get_viewport().set_input_as_handled()
			options.request_close()
		elif not _any_window_open():
			get_viewport().set_input_as_handled()
			_on_options()


func _any_window_open() -> bool:
	if not _transient_overlays.is_empty():
		return true
	for p: ModalPanel in _panels.values():
		if is_instance_valid(p) and p.visible:
			return true
	return false


# --- Layout ----------------------------------------------------------------------

func _build_title() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = TITLE_TOP
	holder.offset_bottom = TITLE_TOP + TITLE_LOGO_MAX_SIZE.y
	add_child(holder)
	if title_logo:
		var tex := TextureRect.new()
		tex.texture = title_logo
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(tex)
	else:
		var title := Label.new()
		title.text = str(ProjectSettings.get_setting("application/config/name", "Game"))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		FontSizes.apply(title, FontSizes.SPLASH)
		holder.add_child(title)


func _build_buttons() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = BUTTONS_TOP
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	_play_button = _add_main_button(column, "Play", _on_play)
	_play_button.texture = PanelButton.GREEN_TEX
	_add_main_button(column, "Options", _on_options)
	if FeatureFlags.ACHIEVEMENTS:
		_add_main_button(column, "Achievements", _on_achievements)

	# Secondary buttons sit in one row under the main column.
	var side_row := HBoxContainer.new()
	side_row.add_theme_constant_override("separation", SIDE_GAP)
	side_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(side_row)
	_add_side_button(side_row, "Save Slots", _show_save_slots)
	_add_side_button(side_row, "Links", _on_links)
	_add_side_button(side_row, "Credits", _on_credits)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		_add_side_button(side_row, "Quit", _on_quit)


func _add_main_button(column: VBoxContainer, label: String, on_pressed: Callable) -> PanelButton:
	var btn := PanelButton.new()
	btn.text = label
	btn.custom_minimum_size = MAIN_BUTTON_SIZE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	FontSizes.apply(btn, FontSizes.BODY_LARGE)
	btn.pressed.connect(on_pressed)
	column.add_child(btn)
	return btn


func _add_side_button(row: HBoxContainer, label: String, on_pressed: Callable) -> void:
	var btn := PanelButton.new()
	btn.text = label
	btn.custom_minimum_size = SIDE_BUTTON_SIZE
	FontSizes.apply(btn, FontSizes.BODY)
	btn.pressed.connect(on_pressed)
	row.add_child(btn)


## Build version in the top-left corner, as a button that opens the patch notes
## browser. The number comes from Project Settings > Application > Config >
## Version (project.godot `config/version`), the one place to bump it.
func _add_version_button() -> void:
	var btn := PanelButton.new()
	btn.name = "VersionButton"
	btn.text = "v" + PatchNotes.current_version()
	btn.custom_minimum_size = Vector2(110, 44)
	FontSizes.apply(btn, FontSizes.BODY)
	btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	btn.position = Vector2(12, 12)
	btn.pressed.connect(func() -> void: _show_patch_notes(""))
	add_child(btn)


# --- Things that pop on arrival ----------------------------------------------------

func _after_intro() -> void:
	await _maybe_show_patch_notes()
	if not is_inside_tree():
		return
	# A crash last session: offer to report it.
	FeedbackReporter.offer_crash_report()


## After an update: the notes for every release since the last build this
## install launched pop once (newest first), then the marker moves to this
## build. A build without notes just moves the marker.
func _maybe_show_patch_notes() -> void:
	var cfg := SaveManager.global_config
	var current := PatchNotes.current_version()
	if PatchNotes.compare(current, cfg.last_seen_version) <= 0:
		return
	var unseen := PatchNotes.unseen_since(cfg.last_seen_version, current)
	cfg.last_seen_version = current
	SaveManager.save_global_config()
	if unseen.is_empty():
		return
	var panel := _show_patch_notes(unseen[0]["version"])
	await panel.closed


# --- Buttons -----------------------------------------------------------------------

func _on_play() -> void:
	SceneManager.change_scene(ProjectConfig.GAME_SCENE)


## Show the window registered under `key`, building it with `make` the first time.
func _open_panel(key: StringName, make: Callable) -> ModalPanel:
	var p: ModalPanel = _panels.get(key)
	if p == null:
		p = make.call()
		p.closed.connect(func() -> void: p.visible = false)
		add_child(p)
		_panels[key] = p
	p.visible = true
	return p


func _on_options() -> void:
	_open_panel(&"options", func() -> ModalPanel: return OptionsScreen.new())


func _on_achievements() -> void:
	# Rebuilt each time so it always shows the current unlock state.
	var old: ModalPanel = _panels.get(&"achievements")
	if old:
		_panels.erase(&"achievements")
		old.queue_free()
	_open_panel(&"achievements", func() -> ModalPanel: return AchievementsPanel.new())


func _on_links() -> void:
	_open_panel(&"links", func() -> ModalPanel: return LinksPanel.new())


func _on_credits() -> void:
	_open_panel(&"credits", func() -> ModalPanel: return CreditsScreen.new())


func _show_patch_notes(version: String) -> ModalPanel:
	var existing: PatchNotesPanel = _panels.get(&"patch_notes")
	if existing:
		existing.show_version(version)
	return _open_panel(&"patch_notes", func() -> ModalPanel:
		var p := PatchNotesPanel.new()
		p.start_version = version
		return p)


func _on_quit() -> void:
	var existing: ModalPanel = _panels.get(&"quit")
	if existing == null:
		var quit := QuitConfirmPanel.new()
		quit.cancelled.connect(func() -> void: quit.visible = false)
		add_child(quit)
		_panels[&"quit"] = quit
		existing = quit
	existing.visible = true


# --- Save slots --------------------------------------------------------------------

func _show_save_slots() -> void:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 10
	overlay.add_to_group(PadNav.SCOPE_GROUP)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -360.0; panel.offset_right = 360.0
	# Height is set from the built content further down.
	UiTheme.apply_panel_ninepatch(panel)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "Save Slots"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	FontSizes.apply(title_lbl, FontSizes.HEADING_SMALL)
	title_lbl.add_theme_color_override("font_color", UiTheme.TEXT_HEADING)
	vbox.add_child(title_lbl)

	# Each row's content sits in an anchored overlay, which can't drive the
	# button's minimum size, so the rows are measured and grown once the panel
	# is in the tree (see the sizing pass after add_child below).
	var slot_rows: Array[Array] = []

	for i in SaveManager.SLOT_COUNT:
		var summary := SaveManager.get_slot_summary(i)
		var is_current := i == SaveManager.current_slot
		var is_empty := summary.is_empty()

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		vbox.add_child(line)

		var row := PanelButton.new()
		row.custom_minimum_size = Vector2(0, SLOT_ROW_MIN_HEIGHT)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(row)

		var inner := MarginContainer.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			inner.add_theme_constant_override("margin_" + side, 8)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(inner)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(hbox)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(28, 28)
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if is_current:
			icon_rect.texture = CURRENT_SLOT_ICON
		hbox.add_child(icon_rect)

		var text_vbox := VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text_vbox.add_theme_constant_override("separation", 2)
		text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(text_vbox)

		var slot_lbl := Label.new()
		slot_lbl.text = "Slot %d%s" % [i + 1, "  (current)" if is_current else ""]
		FontSizes.apply(slot_lbl, FontSizes.HEADING_SMALL)
		slot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_vbox.add_child(slot_lbl)

		var detail_lbl := Label.new()
		detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		FontSizes.apply(detail_lbl, FontSizes.SMALL)
		detail_lbl.text = "Empty" if is_empty else _slot_detail(summary)
		detail_lbl.modulate.a = 0.5 if is_empty else 0.8
		text_vbox.add_child(detail_lbl)

		slot_rows.append([row, text_vbox])

		if is_current:
			row.disabled = true
		else:
			row.pressed.connect(func() -> void:
				overlay.queue_free()
				SaveManager.save_game()
				if SaveManager.has_save_at(i):
					SaveManager.load_game(i)
				else:
					SaveManager.new_game_at(i)
				SceneManager.change_scene(ProjectConfig.MAIN_MENU_SCENE))

		if not is_empty:
			var del_btn := PanelButton.new()
			del_btn.text = "Delete"
			del_btn.texture = PanelButton.RED_TEX
			del_btn.custom_minimum_size = Vector2(90, 40)
			del_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			FontSizes.apply(del_btn, FontSizes.SMALL)
			del_btn.pressed.connect(func() -> void: _confirm_delete_slot(i, overlay))
			line.add_child(del_btn)

	var cancel_btn := PanelButton.new()
	cancel_btn.text = "Close"
	cancel_btn.custom_minimum_size = Vector2(0, 40)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func() -> void: overlay.queue_free())
	vbox.add_child(cancel_btn)

	add_child(overlay)
	# Now that the theme font is resolved, grow each row to fit its two stacked
	# labels, so they stay legible if the font or its size changes.
	for entry in slot_rows:
		var slot_row: PanelButton = entry[0]
		var slot_text: VBoxContainer = entry[1]
		slot_row.custom_minimum_size.y = maxf(
			SLOT_ROW_MIN_HEIGHT,
			slot_text.get_combined_minimum_size().y + SLOT_ROW_PADDING)

	# Fit the panel to the content rather than a fixed box.
	var panel_h: float = panel.get_combined_minimum_size().y
	panel.offset_top = -panel_h * 0.5
	panel.offset_bottom = panel_h * 0.5
	_track_overlay(overlay)


## The second line of a slot row. Extend alongside SaveManager.get_slot_summary.
func _slot_detail(summary: Dictionary) -> String:
	var parts: PackedStringArray = ["Played " + Platform.format_play_time(summary.get("play_time_seconds", 0.0))]
	var saved: int = summary.get("last_saved_unix", 0)
	if saved > 0:
		var d := Time.get_datetime_dict_from_unix_time(saved + _utc_offset_seconds())
		parts.append("Saved %04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute])
	return "   ".join(parts)


func _utc_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _confirm_delete_slot(slot: int, parent_overlay: Control) -> void:
	_show_confirm("Delete Save Slot %d?" % (slot + 1), "This cannot be undone.", "Delete",
		func() -> void:
			SaveManager.delete_save_slot(slot)
			if slot == SaveManager.current_slot:
				SaveManager.new_game_at(slot)
			parent_overlay.queue_free()
			_show_save_slots())


## Modal yes/no over the menu: `title_text`, a `body` line, Cancel and a red
## `confirm_text` button that closes the modal and runs `on_confirm`.
func _show_confirm(title_text: String, body: String, confirm_text: String, on_confirm: Callable) -> void:
	var confirm := Control.new()
	confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm.z_index = 20
	confirm.add_to_group(PadNav.SCOPE_GROUP)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	UiTheme.apply_panel_ninepatch(panel)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	FontSizes.apply(title, FontSizes.HEADING_SMALL)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = body
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	FontSizes.apply(sub, FontSizes.SMALL)
	sub.modulate.a = 0.75
	vbox.add_child(sub)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var cancel_btn := PanelButton.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.custom_minimum_size = Vector2(0, 40)
	cancel_btn.pressed.connect(func() -> void: confirm.queue_free())
	btn_row.add_child(cancel_btn)

	var ok_btn := PanelButton.new()
	ok_btn.text = confirm_text
	ok_btn.texture = PanelButton.RED_TEX
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_btn.custom_minimum_size = Vector2(0, 40)
	ok_btn.pressed.connect(func() -> void:
		confirm.queue_free()
		on_confirm.call())
	btn_row.add_child(ok_btn)

	add_child(confirm)
	_track_overlay(confirm)


## Track a code-built overlay so ui_cancel closes the topmost one, and seed
## keyboard/gamepad focus on its first control.
func _track_overlay(overlay: Control) -> void:
	_transient_overlays.append(overlay)
	overlay.tree_exiting.connect(func() -> void: _transient_overlays.erase(overlay))
	SelectionReticle.call_deferred("focus_first_in", overlay)

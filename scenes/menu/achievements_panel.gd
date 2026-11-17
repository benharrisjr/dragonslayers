class_name AchievementsPanel extends ModalPanel
## The achievement list, opened from the main menu:
##
##     var panel := AchievementsPanel.new()
##     panel.closed.connect(panel.queue_free)
##     add_child(panel)
##
## Earned first (newest at the top), then the locked ones in sort_order. Hidden
## achievements stay masked until earned. It rebuilds itself when one unlocks
## while it is open.

const ICON_SIZE := 48
const UNLOCKED_COLOR := Color(1.0, 0.9, 0.6)
const LOCKED_COLOR := Color(0.5, 0.5, 0.6)
const DESC_COLOR := Color(0.6, 0.7, 0.8)
const DONE_COLOR := Color(0.4, 0.9, 0.5)
const BLANK_ICON_COLOR := Color(1, 1, 1, 0.08)

var _focus_target: Control = null
var _count_label: Label = null
var _rows: VBoxContainer = null


func _first_focus() -> Control:
	return _focus_target


func _init() -> void:
	z_index = 20
	backdrop_alpha = 0.0  # floating panel, the menu stays visible behind
	panel_margin = 28
	content_separation = 18
	panel_min_size = Vector2(760, 620)


func _build_content() -> void:
	var title := Label.new()
	title.text = "Achievements"
	FontSizes.apply(title, FontSizes.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	content.add_child(title)

	_count_label = Label.new()
	FontSizes.apply(_count_label, FontSizes.SMALL)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_color_override("font_color", DESC_COLOR)
	content.add_child(_count_label)

	content.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 14)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	content.add_child(footer)

	# Only where the overlay can actually open: Steam up, on a desktop build.
	if SteamManager.is_available():
		var steam_btn := PanelButton.new()
		steam_btn.text = "View on Steam"
		steam_btn.custom_minimum_size = Vector2(230, 40)
		FontSizes.apply(steam_btn, FontSizes.BODY_LARGE)
		steam_btn.pressed.connect(SteamManager.open_overlay_to_achievements)
		footer.add_child(steam_btn)

	var close_btn := PanelButton.new()
	close_btn.text = "Close"
	close_btn.texture = PanelButton.RED_TEX
	close_btn.custom_minimum_size = Vector2(130, 40)
	FontSizes.apply(close_btn, FontSizes.BODY_LARGE)
	close_btn.pressed.connect(func() -> void: closed.emit())
	footer.add_child(close_btn)
	_focus_target = close_btn

	_populate()
	Achievements.achievement_unlocked.connect(_on_unlocked)


func _on_unlocked(_ach: AchievementData) -> void:
	_populate()


func _populate() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	var defs := Achievements.get_all_defs()
	_count_label.text = "%d / %d unlocked" % [Achievements.get_unlocked_count(), defs.size()]
	if defs.is_empty():
		var empty := Label.new()
		empty.text = "No achievements yet."
		FontSizes.apply(empty, FontSizes.BODY)
		empty.add_theme_color_override("font_color", LOCKED_COLOR)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(empty)
		return

	var sorted: Array[AchievementData] = defs.duplicate()
	sorted.sort_custom(func(a: AchievementData, b: AchievementData) -> bool:
		var a_on := Achievements.is_unlocked(a.id)
		var b_on := Achievements.is_unlocked(b.id)
		if a_on != b_on:
			return a_on
		if a_on:
			return Achievements.get_unlock_time(a.id) > Achievements.get_unlock_time(b.id)
		return a.sort_order < b.sort_order)

	for ach in sorted:
		_rows.add_child(_build_row(ach))


func _build_row(ach: AchievementData) -> Control:
	var unlocked := Achievements.is_unlocked(ach.id)
	# Hidden achievements stay masked until earned, including their progress,
	# which would otherwise leak the condition.
	var masked := ach.hidden and not unlocked

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	row.add_child(_build_icon(null if masked else ach.icon, unlocked))

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 2)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_box)

	var name_lbl := Label.new()
	name_lbl.text = "???" if masked else ach.display_name
	FontSizes.apply(name_lbl, FontSizes.BODY)
	name_lbl.add_theme_color_override("font_color", UNLOCKED_COLOR if unlocked else LOCKED_COLOR)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = "Hidden achievement" if masked else ach.description
	FontSizes.apply(desc_lbl, FontSizes.SMALL)
	desc_lbl.add_theme_color_override("font_color", DESC_COLOR)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(desc_lbl)

	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 2)
	status.custom_minimum_size = Vector2(190, 0)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status)

	if unlocked:
		status.add_child(_status_label("Unlocked", DONE_COLOR))
		var when := Achievements.get_unlock_time(ach.id)
		if when > 0:
			# Local date: the stored time is UTC unix seconds.
			var bias: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
			status.add_child(_status_label(
					Time.get_date_string_from_unix_time(when + bias), DESC_COLOR))
		return row

	var progress := Vector2i.ZERO if masked else Achievements.get_progress(ach)
	if progress.y > 0:
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = progress.y
		bar.value = progress.x
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status.add_child(bar)
		status.add_child(_status_label("%d / %d" % [progress.x, progress.y], Color(0.75, 0.85, 1.0)))
	else:
		status.add_child(_status_label("Locked", LOCKED_COLOR))
	return row


## The achievement's icon, dimmed while locked; a blank square when it has none
## (or is masked) so every row keeps the same left edge.
func _build_icon(tex: Texture2D, unlocked: bool) -> Control:
	if tex == null:
		var blank := ColorRect.new()
		blank.color = BLANK_ICON_COLOR
		blank.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		blank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return blank
	var icon_rect := TextureRect.new()
	icon_rect.texture = tex
	icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		icon_rect.modulate = Color(1, 1, 1, 0.35)
	return icon_rect


func _status_label(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	FontSizes.apply(lbl, FontSizes.SMALL)
	lbl.add_theme_color_override("font_color", color)
	return lbl

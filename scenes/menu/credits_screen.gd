class_name CreditsScreen extends ModalPanel

## Scrolling credits. Edit CREDITS: one dictionary per section. The entries
## below are the template's own (studio, plus the third-party assets it still
## ships); keep the asset lines for as long as those files are in the project.
const CREDITS: Array[Dictionary] = [
	{"section": "A Game By", "entries": ["VGMRX"]},
	{"section": "Art", "entries": [
		"Characters, skeletons, weapons and props by Kay Lousberg (kaylousberg.com)",
		"Environment kits by Kenney (kenney.nl)",
		"Input prompts and cursors by Kenney (kenney.nl)",
	]},
	{"section": "Music", "entries": []},
	{"section": "Sound Effects", "entries": [
		"UI sounds by LEOHPAZ",
	]},
	{"section": "Fonts", "entries": [
		"Atkinson Hyperlegible by the Braille Institute -- License: SIL Open Font License 1.1",
		"Kenney Pixel by Kenney (kenney.nl)",
	]},
	{"section": "Tools", "entries": [
		"Made with Godot Engine (godotengine.org)",
		"GodotSteam by GP Garcia and contributors",
	]},
]


var _focus_target: Control = null


func _first_focus() -> Control:
	return _focus_target


func _init() -> void:
	z_index = 20
	backdrop_alpha = 0.0  # floating panel, the menu stays visible behind
	panel_margin = 28
	content_separation = 18
	panel_min_size = Vector2(520, 560)


func _build_content() -> void:
	var title := Label.new()
	title.text = "Credits"
	FontSizes.apply(title, FontSizes.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.TEXT_HEADING)
	content.add_child(title)

	content.add_child(HSeparator.new())

	# The section list is taller than the panel; scroll it so it doesn't
	# overflow the panel bounds.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	var sections := VBoxContainer.new()
	sections.add_theme_constant_override("separation", 18)
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sections)

	for section_data in CREDITS:
		if (section_data["entries"] as Array).is_empty():
			continue
		var section_lbl := Label.new()
		section_lbl.text = section_data["section"]
		FontSizes.apply(section_lbl, FontSizes.BODY_LARGE)
		section_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
		sections.add_child(section_lbl)

		for entry in section_data["entries"]:
			var entry_lbl := Label.new()
			entry_lbl.text = "  " + entry
			entry_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			FontSizes.apply(entry_lbl, FontSizes.BODY)
			entry_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
			sections.add_child(entry_lbl)

		sections.add_child(HSeparator.new())

	var close_btn := PanelButton.new()
	close_btn.text = "Close"
	close_btn.texture = PanelButton.RED_TEX
	close_btn.custom_minimum_size = Vector2(130, 40)
	FontSizes.apply(close_btn, FontSizes.BODY_LARGE)
	close_btn.pressed.connect(func() -> void: closed.emit())
	_focus_target = close_btn

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(footer)
	footer.add_child(close_btn)

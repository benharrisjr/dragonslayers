class_name LinksPanel extends ModalPanel

## External links (Discord, website, store page). URLs come from ProjectConfig;
## an empty URL leaves its button out.

const DISCORD_ICON := preload("res://art/icons/discord_symbol_white.png")

var _focus_target: Control = null


func _first_focus() -> Control:
	return _focus_target


func _init() -> void:
	z_index = 20
	backdrop_alpha = 0.0  # floating panel, the menu stays visible behind
	panel_margin = 28
	content_separation = 18
	panel_min_size = Vector2(360, 260)


func _build_content() -> void:
	var title := Label.new()
	title.text = "Links"
	FontSizes.apply(title, FontSizes.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.TEXT_HEADING)
	content.add_child(title)

	content.add_child(HSeparator.new())

	if ProjectConfig.DISCORD_URL != "":
		var discord_btn := _add_link("Discord", ProjectConfig.DISCORD_URL)
		discord_btn.icon = DISCORD_ICON
	if ProjectConfig.WEBSITE_URL != "":
		_add_link("Website", ProjectConfig.WEBSITE_URL)
	if ProjectConfig.STORE_URL != "":
		_add_link("Store Page", ProjectConfig.STORE_URL)

	var close_btn := PanelButton.new()
	close_btn.text = "Close"
	close_btn.texture = PanelButton.RED_TEX
	close_btn.custom_minimum_size = Vector2(130, 40)
	FontSizes.apply(close_btn, FontSizes.BODY_LARGE)
	close_btn.pressed.connect(func() -> void: closed.emit())
	if _focus_target == null:
		_focus_target = close_btn

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(footer)
	footer.add_child(close_btn)


func _add_link(label: String, url: String) -> PanelButton:
	var btn := PanelButton.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 44)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	FontSizes.apply(btn, FontSizes.BODY_LARGE)
	btn.pressed.connect(func() -> void: OS.shell_open(url))
	content.add_child(btn)
	if _focus_target == null:
		_focus_target = btn
	return btn

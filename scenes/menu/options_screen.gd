class_name OptionsScreen extends ModalPanel

## The Options window: a Settings tab (volumes, pad speeds, graphics), a Toggles
## tab (every checkbox) and a Keybindings button that opens KeybindsPanel.
## Everything here is device-level and lives in GlobalConfig (shared by every
## save slot) or GraphicsQuality's per-machine file.
##
## Adding a game option: put the field in GlobalConfig, then one _add_check_row
## or _add_choice_row call in _build_content.

## The in-game footer's "Main Menu" button (see show_ingame_buttons).
signal main_menu_requested

## GraphicsQuality.Mode order: AUTO, HIGH, LOW.
const GRAPHICS_LABELS: Array[String] = ["Auto", "High", "Low"]
## GraphicsQuality.WindowPreset order: DEFAULT, STEAM_DECK.
const RESOLUTION_LABELS: Array[String] = ["Default", "Steam Deck"]

## Tab order in the tab row (Keybindings sits after them as a plain button).
enum Tab { SETTINGS, TOGGLES }
const TAB_LABELS: Array[String] = ["Settings", "Toggles"]

const _SLIDER_LABEL_W := 200.0
## Floor for the label column of choice rows; _align_choice_labels widens it to
## the widest label in the current font.
const _CHOICE_LABEL_W := 200.0

var _first_slider: HSlider = null
var _choice_labels: Array[Label] = []
var _footer: HBoxContainer = null
var _keybinds_panel: KeybindsPanel = null
var _tab_buttons: Array[PanelButton] = []
var _pages: Array[VBoxContainer] = []
var _page_holder: VBoxContainer = null
var _config_dirty := false


func _init() -> void:
	z_index = 20
	drop_in = true
	panel_margin = 24
	content_separation = 16
	# Width only: the height follows the content, and the page area is pinned
	# to the taller tab's page (see _size_pages) so switching tabs doesn't jump.
	panel_min_size = Vector2(700, 0)


func _build_content() -> void:
	var root := content
	var cfg := SaveManager.global_config

	var title := Label.new()
	title.text = "Options"
	FontSizes.apply(title, FontSizes.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.TEXT_HEADING)
	root.add_child(title)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	root.add_child(tab_row)
	for i in TAB_LABELS.size():
		var tab_btn := _make_button(TAB_LABELS[i], Vector2(0, 40))
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.pressed.connect(_select_tab.bind(i))
		tab_row.add_child(tab_btn)
		_tab_buttons.append(tab_btn)
	var keys_btn := _make_button("Keybindings", Vector2(0, 40))
	keys_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys_btn.pressed.connect(_on_keybindings)
	tab_row.add_child(keys_btn)

	root.add_child(HSeparator.new())

	_page_holder = VBoxContainer.new()
	root.add_child(_page_holder)
	for i in TAB_LABELS.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", content_separation)
		_page_holder.add_child(page)
		_pages.append(page)

	# ── Settings page ──
	var vbox := _pages[Tab.SETTINGS]
	_first_slider = _add_slider_row(vbox, "Master", cfg.master_volume, 0.0, 1.0,
			func(v: float) -> void:
				cfg.master_volume = v
				SoundManager.set_master_volume(v))
	_add_slider_row(vbox, "Music", cfg.music_volume, 0.0, 1.0,
			func(v: float) -> void:
				cfg.music_volume = v
				SoundManager.set_music_volume(v))
	_add_slider_row(vbox, "Sound Effects", cfg.sfx_volume, 0.0, 1.0,
			func(v: float) -> void:
				cfg.sfx_volume = v
				SoundManager.set_sfx_volume(v))
	_add_slider_row(vbox, "Ambience", cfg.ambience_volume, 0.0, 1.0,
			func(v: float) -> void:
				cfg.ambience_volume = v
				SoundManager.set_ambience_volume(v))
	vbox.add_child(HSeparator.new())

	# Gamepad sensitivity: how fast the left stick moves the pad cursor and how
	# fast the right stick scrolls.
	_add_slider_row(vbox, "Pad Cursor", cfg.pad_cursor_speed, GlobalConfig.PAD_SPEED_MIN, GlobalConfig.PAD_SPEED_MAX,
			func(v: float) -> void: cfg.pad_cursor_speed = v)
	_add_slider_row(vbox, "Pad Scroll", cfg.pad_scroll_speed, GlobalConfig.PAD_SPEED_MIN, GlobalConfig.PAD_SPEED_MAX,
			func(v: float) -> void: cfg.pad_scroll_speed = v)
	vbox.add_child(HSeparator.new())

	# Graphics: GraphicsQuality's tier, saved per machine on the spot. Auto picks
	# Low on weak integrated GPUs.
	_add_choice_row(vbox, "Graphics", GRAPHICS_LABELS, GraphicsQuality.get_mode(),
			func(idx: int) -> void: GraphicsQuality.set_mode(idx as GraphicsQuality.Mode))
	# Resolution: Steam Deck previews the Deck's 16:10 frame. Desktop only.
	if GraphicsQuality.supports_fullscreen():
		_add_choice_row(vbox, "Resolution", RESOLUTION_LABELS, GraphicsQuality.get_window_preset(),
				func(idx: int) -> void: GraphicsQuality.set_window_preset(idx as GraphicsQuality.WindowPreset))

	# ── Toggles page ──
	vbox = _pages[Tab.TOGGLES]
	if GraphicsQuality.supports_fullscreen():
		_add_check_row(vbox, "Fullscreen", GraphicsQuality.is_fullscreen(), GraphicsQuality.set_fullscreen)
	# Whole-screen jolts and colour flashes; the game checks these before playing one.
	_add_check_row(vbox, "Screen Shake", cfg.screen_shake_enabled,
			func(on: bool) -> void:
				cfg.screen_shake_enabled = on
				_config_dirty = true)
	_add_check_row(vbox, "Screen Flash", cfg.screen_flash_enabled,
			func(on: bool) -> void:
				cfg.screen_flash_enabled = on
				_config_dirty = true)
	# Atkinson Hyperlegible in place of the game font.
	_add_check_row(vbox, "Readable Font", UIFont.readable(), UIFont.set_readable)
	# The key-prompt badges on every hotkeyed button.
	_add_check_row(vbox, "Key Hints", cfg.show_key_hints, Keybinds.set_hints_enabled)
	# A click picks an item up, the next click drops it (the pad's pickup, on the mouse).
	_add_check_row(vbox, "Click to Drag", cfg.click_to_drag,
			func(on: bool) -> void:
				cfg.click_to_drag = on
				_config_dirty = true)
	# A on the right face button (Switch) instead of the bottom (Xbox / Deck).
	_add_check_row(vbox, "Nintendo Layout", cfg.nintendo_layout, _set_nintendo_layout)

	root.add_child(HSeparator.new())

	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.add_theme_constant_override("separation", 12)
	root.add_child(_footer)

	var close_btn := _make_button("Close", Vector2(130, 40))
	close_btn.texture = PanelButton.RED_TEX
	close_btn.pressed.connect(_on_close)
	_footer.add_child(close_btn)

	_align_choice_labels()
	# Toggling Readable Font right here re-measures the column for the new font
	# (deferred: the theme change reaches the labels after the toggle returns).
	UIFont.follow(self, func() -> void: _align_choice_labels.call_deferred())
	_size_pages()
	_select_tab(Tab.SETTINGS)


## In-game footer: adds "Main Menu" (emits main_menu_requested) before Close.
## Call once, right after adding the panel to the tree.
func show_ingame_buttons() -> void:
	if not _footer:
		return
	var main_menu_btn := _make_button("Main Menu", Vector2(130, 40))
	main_menu_btn.pressed.connect(func() -> void: main_menu_requested.emit())
	_footer.add_child(main_menu_btn)
	_footer.move_child(main_menu_btn, 0)


func _make_button(label: String, min_size: Vector2) -> PanelButton:
	var btn := PanelButton.new()
	btn.text = label
	btn.custom_minimum_size = min_size
	FontSizes.apply(btn, FontSizes.BODY_LARGE)
	return btn


## A labelled slider with a percentage readout. Applies live through
## `on_changed`; GlobalConfig is written when the panel closes.
func _add_slider_row(vbox: VBoxContainer, label: String, value: float, min_v: float, max_v: float,
		on_changed: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(_SLIDER_LABEL_W, 0)
	FontSizes.apply(lbl, FontSizes.BODY_LARGE)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 28)
	row.add_child(slider)
	var pct := Label.new()
	pct.text = "%d%%" % roundi(value * 100.0)
	pct.custom_minimum_size = Vector2(56, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	FontSizes.apply(pct, FontSizes.BODY)
	row.add_child(pct)
	slider.value_changed.connect(func(v: float) -> void:
		on_changed.call(v)
		_config_dirty = true
		pct.text = "%d%%" % roundi(v * 100.0))
	return slider


## A label and one button per choice; the selected one is highlighted.
## `on_selected` receives the index.
func _add_choice_row(vbox: VBoxContainer, label: String, choices: Array[String], current: int,
		on_selected: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(_CHOICE_LABEL_W, 0)
	_choice_labels.append(lbl)
	FontSizes.apply(lbl, FontSizes.BODY_LARGE)
	row.add_child(lbl)
	var buttons: Array[PanelButton] = []
	for i in choices.size():
		var btn := PanelButton.new()
		btn.text = choices[i]
		btn.custom_minimum_size = Vector2(72, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # share the row's width
		btn.pressed.connect(func() -> void:
			on_selected.call(i)
			_mark_choice(buttons, i))
		row.add_child(btn)
		buttons.append(btn)
	_mark_choice(buttons, current)


func _add_check_row(vbox: VBoxContainer, label: String, pressed: bool, on_toggled: Callable) -> CheckBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	FontSizes.apply(lbl, FontSizes.BODY_LARGE)
	row.add_child(lbl)
	var check := CheckBox.new()
	check.button_pressed = pressed
	check.toggled.connect(on_toggled)
	row.add_child(check)
	_link_label(lbl, check)
	return check


## Like an HTML <label for>: a click on the row's name flips its checkbox too
## (through button_pressed, so `toggled` fires exactly as a box click would).
static func _link_label(lbl: Label, check: CheckBox) -> void:
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	lbl.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		lbl.accept_event()
		if not check.disabled:
			check.button_pressed = not check.button_pressed)


## Give every choice-row label the widest one's width so their buttons line up.
func _align_choice_labels() -> void:
	var w := _CHOICE_LABEL_W
	for lbl in _choice_labels:
		lbl.custom_minimum_size.x = 0.0
		w = maxf(w, lbl.get_minimum_size().x)
	for lbl in _choice_labels:
		lbl.custom_minimum_size.x = w


## Pin the page area to the taller page so the window keeps one size across tabs.
func _size_pages() -> void:
	var h := 0.0
	for page in _pages:
		page.visible = true
		h = maxf(h, page.get_combined_minimum_size().y)
	_page_holder.custom_minimum_size.y = h


func _select_tab(idx: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == idx
	_mark_choice(_tab_buttons, idx)


## The selected button in a tab or choice row wears the green style.
func _mark_choice(buttons: Array, idx: int) -> void:
	for i in buttons.size():
		(buttons[i] as PanelButton).texture = PanelButton.GREEN_TEX if i == idx else null


func _set_nintendo_layout(on: bool) -> void:
	SaveManager.global_config.nintendo_layout = on
	SaveManager.save_global_config()
	SaveManager.apply_pad_layout()
	SaveManager.keybinds_changed.emit()


func _exit_tree() -> void:
	_flush()


func _flush() -> void:
	if _config_dirty:
		_config_dirty = false
		SaveManager.save_global_config()


func _first_focus() -> Control:
	return _first_slider


func _on_keybindings() -> void:
	if _keybinds_panel == null:
		_keybinds_panel = KeybindsPanel.new()
		_keybinds_panel.closed.connect(func() -> void: _keybinds_panel.visible = false)
		add_child(_keybinds_panel)
	_keybinds_panel.visible = true


func _on_close() -> void:
	_flush()
	request_close()


func _on_back() -> void:
	_on_close()

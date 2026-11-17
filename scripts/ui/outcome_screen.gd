class_name OutcomeScreen
extends Control

## The end of a run: the dragon is dead and the party has won.
##
## Deliberately a full-screen overlay rather than a per-pane one -- the run ends for everybody
## at once, and four separate victory banners in four quarters would read as four results.

signal rematch_requested
signal main_menu_requested

var _title: Label
var _detail: Label
var _rematch: PanelButton
var _waiting: Label
var _menu_button: PanelButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Lets the gamepad's hand walk the two buttons while this is the top screen.
	add_to_group(PadNav.SCOPE_GROUP)
	visible = false
	_build()
	GameState.phase_changed.connect(_on_phase_changed)


func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.04, 0.06, 0.05, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(column)

	_title = Label.new()
	_title.text = "THE DRAGON IS SLAIN"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	FontSizes.apply(_title, FontSizes.OVERLAY)
	_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 10)
	column.add_child(_title)

	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	FontSizes.apply(_detail, FontSizes.BODY_LARGE)
	_detail.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	column.add_child(_detail)

	_rematch = _button(column, "Hunt again", func() -> void: rematch_requested.emit())
	## Only the host can start a match, so everyone else is told to wait rather than shown a
	## button that would do nothing.
	_waiting = Label.new()
	_waiting.text = "Waiting for the host to start another hunt"
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	FontSizes.apply(_waiting, FontSizes.BODY)
	_waiting.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	column.add_child(_waiting)
	_menu_button = _button(column, "Main menu", func() -> void: main_menu_requested.emit())


func _button(parent: Control, text: String, action: Callable) -> PanelButton:
	var button := PanelButton.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 56)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	FontSizes.apply(button, FontSizes.BODY_LARGE)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase != GameState.Phase.VICTORY:
		visible = false
		return
	var party := PlayerRegistry.roster.size()
	_detail.text = "%d slayer%s  ·  %d gold earned" % [
		party, "" if party == 1 else "s", GameState.gold]
	_rematch.visible = NetworkManager.is_host()
	_waiting.visible = not NetworkManager.is_host()
	visible = true
	SelectionReticle.focus_first.call_deferred(
			_rematch if _rematch.visible else _menu_button)

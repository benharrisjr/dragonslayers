class_name QuitConfirmPanel extends ModalPanel

signal cancelled

var _no_btn: PanelButton = null


func _init() -> void:
	z_index = 100
	panel_margin = 32
	content_separation = 24


func _build_content() -> void:
	var label := Label.new()
	label.text = "Are you sure you want to quit?"
	FontSizes.apply(label, FontSizes.HEADING_SMALL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(btn_row)

	var no_btn := PanelButton.new()
	no_btn.text = "No"
	no_btn.custom_minimum_size = Vector2(110, 44)
	FontSizes.apply(no_btn, FontSizes.BODY_LARGE)
	no_btn.pressed.connect(func() -> void: cancelled.emit())
	btn_row.add_child(no_btn)
	_no_btn = no_btn

	var yes_btn := PanelButton.new()
	yes_btn.text = "Yes"
	yes_btn.custom_minimum_size = Vector2(110, 44)
	FontSizes.apply(yes_btn, FontSizes.BODY_LARGE)
	yes_btn.pressed.connect(func() -> void: SaveManager.request_quit())
	btn_row.add_child(yes_btn)


func _first_focus() -> Control:
	return _no_btn


func _on_back() -> void:
	cancelled.emit()

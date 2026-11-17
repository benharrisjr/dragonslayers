class_name ConfirmPanel extends ModalPanel
## Reusable confirm dialog: a message with Confirm/Cancel PanelButtons. Set
## `message` / `confirm_label` / `cancel_label` before add_child (content is
## built on _ready). Emits `confirmed` or `cancelled`; the opener owns freeing
## the panel in both handlers.

signal confirmed
signal cancelled

var message: String = "Are you sure?"
var confirm_label: String = "Confirm"
var cancel_label: String = "Cancel"
## False drops the Cancel button (a one-button notice); Back still emits
## `cancelled`.
var show_cancel: bool = true
## Above 0, the message wraps at this width instead of sizing the panel.
var message_width: float = 0.0

var _cancel_btn: PanelButton = null
var _confirm_btn: PanelButton = null


func _init() -> void:
	z_index = 100
	panel_margin = 32
	content_separation = 24


func _build_content() -> void:
	var label := Label.new()
	label.text = message
	FontSizes.apply(label, FontSizes.HEADING_SMALL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if message_width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = message_width
	content.add_child(label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(btn_row)

	var cancel_btn := PanelButton.new()
	cancel_btn.text = cancel_label
	cancel_btn.custom_minimum_size = Vector2(130, 44)
	FontSizes.apply(cancel_btn, FontSizes.BODY_LARGE)
	cancel_btn.pressed.connect(func() -> void: cancelled.emit())
	if show_cancel:
		btn_row.add_child(cancel_btn)
		_cancel_btn = cancel_btn
	else:
		cancel_btn.queue_free()

	var confirm_btn := PanelButton.new()
	confirm_btn.text = confirm_label
	confirm_btn.custom_minimum_size = Vector2(130, 44)
	FontSizes.apply(confirm_btn, FontSizes.BODY_LARGE)
	confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	confirm_btn.pressed.connect(func() -> void: confirmed.emit())
	btn_row.add_child(confirm_btn)
	_confirm_btn = confirm_btn


func _first_focus() -> Control:
	return _cancel_btn if _cancel_btn else _confirm_btn


func _on_back() -> void:
	cancelled.emit()

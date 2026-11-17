class_name ModalPanel extends Control
## Shared shell for code-built modal dialogs: optional dimming backdrop, centered
## nine-patched panel, margins, and a `content` VBox. Subclasses set the knobs in
## _init(), build their UI in _build_content(), and override _on_back() when
## dismissal needs side effects. Subclasses must NOT define _ready().

signal closed

# Shell knobs  set in subclass _init() before this node enters the tree.
var backdrop_alpha: float = 0.6      # 0 disables the backdrop entirely (floating panel)
var backdrop_color: Color = Color.BLACK  # tint of the dimming backdrop (alpha comes from backdrop_alpha)
var panel_margin: int = 28
var content_separation: int = 16
var panel_min_size: Vector2 = Vector2.ZERO
## Shop-style entrance: the panel drops in from below the viewport when shown
## and slides back out on request_close(), with the backdrop fading alongside.
## Off by default so confirm dialogs and popups still appear in place.
var drop_in: bool = false

var backdrop: ColorRect = null  # null when backdrop_alpha is 0
var center: CenterContainer
var panel: PanelContainer
var content: VBoxContainer

# True while this panel currently owns a pushed focus context (guards against
# double-push/pop from repeated visibility toggles and tree-exit cleanup).
var _context_pushed: bool = false
var _drop_tween: Tween = null
# True from request_close() until the slide-out lands, so a second request
# (Close button then Escape) doesn't restart the animation or emit twice.
var _closing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The pad's D-pad hand drives whichever window is on top (PadNav).
	add_to_group(PadNav.SCOPE_GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if backdrop_alpha > 0.0:
		backdrop = ColorRect.new()
		backdrop.color = Color(backdrop_color, backdrop_alpha)
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(backdrop)

	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	panel = PanelContainer.new()
	UiTheme.apply_panel_ninepatch(panel)
	if panel_min_size != Vector2.ZERO:
		panel.custom_minimum_size = panel_min_size
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, panel_margin)
	panel.add_child(margin)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", content_separation)
	margin.add_child(content)

	_build_content()

	# Keyboard/gamepad focus: grab an initial control when shown, restore the
	# opener's focus when hidden. Subclasses supply the target via _first_focus().
	visibility_changed.connect(_on_visibility_changed)
	# A panel freed while still visible (queue_free without hiding first) never
	# fires visibility_changed, so balance the context stack on tree exit too.
	tree_exiting.connect(func() -> void:
		if _context_pushed:
			_context_pushed = false
			SelectionReticle.pop_context())
	if visible:
		_on_visibility_changed()


func _build_content() -> void:
	pass


## Subclasses override to return the control that should receive focus when the
## panel opens (e.g. the primary/confirm button). Return null to focus nothing.
func _first_focus() -> Control:
	return null


func _on_visibility_changed() -> void:
	if visible and not _context_pushed:
		_context_pushed = true
		SelectionReticle.push_context(_first_focus())
		if drop_in:
			_animate_open()
	elif not visible and _context_pushed:
		_context_pushed = false
		SelectionReticle.pop_context()


## Dismisses the panel, emitting `closed` once it is off screen. Panels without
## `drop_in` close immediately, as they always have.
func request_close() -> void:
	if not drop_in:
		closed.emit()
		return
	if _closing:
		return
	_closing = true
	if _drop_tween:
		_drop_tween.kill()
	_drop_tween = DropIn.close(center)
	DropIn.fade_backdrop(_drop_tween, backdrop, 0.0)
	_drop_tween.chain().tween_callback(func() -> void:
		_closing = false
		closed.emit())


func _animate_open() -> void:
	_closing = false
	if _drop_tween:
		_drop_tween.kill()
	if backdrop:
		backdrop.modulate.a = 0.0
	_drop_tween = DropIn.open(center, 0.0)
	DropIn.fade_backdrop(_drop_tween, backdrop, 1.0)


# Gamepad A / keyboard Escape (ui_cancel) dismisses the dialog.
func _on_back() -> void:
	request_close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

class_name UiTheme
## The one style file. Every code-built panel, button, tooltip and icon slot
## draws from the colours and metrics below with StyleBoxFlat, so a game
## restyles the whole UI by editing these constants (or by swapping the
## *_style() functions for its own art). FontSizes (autoload) holds the type
## scale and UIFont the font choice.

## ─── Colours ─────────────────────────────────────────────────────────────────
## Screen clear / menu backdrop.
const BACKGROUND := Color(0.07, 0.08, 0.10)
## Windows (ModalPanel, GamePanel).
const PANEL := Color(0.12, 0.13, 0.16, 0.98)
const PANEL_BORDER := Color(0.34, 0.37, 0.44)
## Buttons (PanelButton) per state.
const BUTTON := Color(0.19, 0.21, 0.26)
const BUTTON_HOVER := Color(0.26, 0.29, 0.36)
const BUTTON_PRESSED := Color(0.14, 0.15, 0.19)
const BUTTON_DISABLED := Color(0.15, 0.16, 0.18)
const BUTTON_BORDER := Color(0.42, 0.46, 0.55)
## Button variants: a tinted button blends its fill toward one of these and
## wears it as its border (PanelButton.tint).
const ACCENT := Color(0.33, 0.58, 0.95)    ## secondary / selected / links
const CONFIRM := Color(0.36, 0.76, 0.45)   ## go, start, selected tab
const DANGER := Color(0.88, 0.34, 0.33)    ## close, delete, quit
## Keyboard / pad focus ring.
const FOCUS := Color(1.0, 0.86, 0.42)
const TEXT := Color(0.93, 0.94, 0.96)
const TEXT_MUTED := Color(0.60, 0.63, 0.70)
const TEXT_HEADING := Color(1.0, 0.90, 0.60)
const TEXT_DISABLED := Color(0.48, 0.50, 0.55)
## Translucent fill for HUD panels that sit over gameplay, so the scene still
## shows through a little.
const PANEL_BACKING_COLOR := Color(0.04, 0.04, 0.06, 0.65)
## Tooltip card (InfoPopup).
const TOOLTIP := Color(0.08, 0.10, 0.14, 0.97)
const TOOLTIP_BORDER := Color(0.40, 0.45, 0.55)
## Drop shadow under windows and buttons.
const SHADOW := Color(0, 0, 0, 0.45)

## ─── Metrics (px on the 1920x1080 canvas) ────────────────────────────────────
const CORNER_RADIUS := 6
const BORDER_WIDTH := 2
## Border width of window frames. (Named for the pixel-frame scale it replaced.)
const PANEL_FRAME_SCALE := 3
## How strongly a variant colour tints a button's fill (0 = none, 1 = solid).
const TINT_STRENGTH := 0.32

## Sentinel for "no variant": the plain button colours.
const NO_TINT := Color(0, 0, 0, 0)


## Window style. `tint` multiplies the border (WHITE = PANEL_BORDER as is).
static func panel_style(tint: Color = Color.WHITE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = PANEL_BORDER * tint
	sb.set_border_width_all(PANEL_FRAME_SCALE)
	sb.set_corner_radius_all(CORNER_RADIUS + 2)
	sb.shadow_color = SHADOW
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	return sb


## HUD panel style: PANEL_BACKING_COLOR fill, thin border, no shadow.
static func hud_panel_style(border: Color = PANEL_BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BACKING_COLOR
	sb.border_color = border
	sb.set_border_width_all(BORDER_WIDTH)
	sb.set_corner_radius_all(CORNER_RADIUS)
	return sb


## Give a PanelContainer the window style. (The name predates the flat look;
## kept so callers don't change.)
static func apply_panel_ninepatch(panel: PanelContainer, tint: Color = Color.WHITE) -> void:
	panel.add_theme_stylebox_override("panel", panel_style(tint))


## Button style for `state` (&"normal", &"hover", &"pressed", &"disabled").
## `tint` is a variant colour (ACCENT / CONFIRM / DANGER / any), NO_TINT for the
## plain button; `focused` swaps the border for the FOCUS ring.
static func button_style(state: StringName = &"normal", tint: Color = NO_TINT,
		focused: bool = false) -> StyleBoxFlat:
	var fill := BUTTON
	match state:
		&"hover": fill = BUTTON_HOVER
		&"pressed": fill = BUTTON_PRESSED
		&"disabled": fill = BUTTON_DISABLED
	var border := BUTTON_BORDER
	if tint.a > 0.0:
		var solid := Color(tint, 1.0)
		fill = fill.lerp(solid, TINT_STRENGTH)
		border = solid
	if state == &"disabled":
		border = border.darkened(0.45)
	if focused and state != &"disabled":
		border = FOCUS
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(BORDER_WIDTH)
	sb.set_corner_radius_all(CORNER_RADIUS)
	if state != &"pressed" and state != &"disabled":
		sb.shadow_color = SHADOW
		sb.shadow_size = 2
		sb.shadow_offset = Vector2(0, 3)
	return sb


## Hollow frame for icon slots (IconPanel): `fill` behind, `border` around.
static func slot_style(border: Color = BUTTON_BORDER, fill: Color = Color.TRANSPARENT,
		border_width: int = BORDER_WIDTH) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.draw_center = fill.a > 0.0
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(CORNER_RADIUS)
	return sb


## Tooltip card style (InfoPopup).
static func tooltip_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TOOLTIP
	sb.border_color = TOOLTIP_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	return sb


## ─── Project theme touches ───────────────────────────────────────────────────
## Called once at boot (SaveManager._ready). The engine's stock CheckBox icons
## are near-black and vanish on the dark panels, so draw a matching set here.

const _CHECK_PX := 22

static func apply_to_project_theme() -> void:
	var theme := ThemeDB.get_project_theme()
	if theme == null:
		return
	theme.set_icon(&"unchecked", &"CheckBox", _check_icon(false, TEXT_MUTED))
	theme.set_icon(&"checked", &"CheckBox", _check_icon(true, TEXT))
	theme.set_icon(&"unchecked_disabled", &"CheckBox", _check_icon(false, TEXT_DISABLED))
	theme.set_icon(&"checked_disabled", &"CheckBox", _check_icon(true, TEXT_DISABLED))


## A square outline, with a filled inner square when `on`.
static func _check_icon(on: bool, color: Color) -> ImageTexture:
	var img := Image.create(_CHECK_PX, _CHECK_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var last := _CHECK_PX - 1
	for i in _CHECK_PX:
		for t in 2:
			img.set_pixel(i, t, color)
			img.set_pixel(i, last - t, color)
			img.set_pixel(t, i, color)
			img.set_pixel(last - t, i, color)
	if on:
		img.fill_rect(Rect2i(5, 5, _CHECK_PX - 10, _CHECK_PX - 10), color)
	return ImageTexture.create_from_image(img)

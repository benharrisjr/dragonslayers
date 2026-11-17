class_name UIFont
## Options "Readable Font" (GlobalConfig.readable_font): swaps the project
## theme's default font for Atkinson Hyperlegible. The theme's default_font
## carries almost every Label / Button, so swapping it covers them without
## per-node work.
##
## The template ships with no game font: DEFAULT is null, which means the
## engine's built-in font. A game sets DEFAULT to its own font (a preload) and
## every Control picks it up. Anything that measured text listens to
## SaveManager.ui_font_changed (see follow) and re-measures.

## The game's normal font, or null for the engine default.
const DEFAULT: Font = null
const READABLE_FILE: Font = preload("res://art/fonts/AtkinsonHyperlegible-Regular.ttf")


static func readable() -> bool:
	return SaveManager.global_config != null and SaveManager.global_config.readable_font


static func is_readable() -> bool:
	return readable()


static func set_readable(on: bool) -> void:
	if SaveManager.global_config == null or SaveManager.global_config.readable_font == on:
		return
	SaveManager.global_config.readable_font = on
	SaveManager.save_global_config()
	apply()
	SaveManager.ui_font_changed.emit()


## Point the project theme at the chosen font. Controls re-resolve their theme
## font through NOTIFICATION_THEME_CHANGED, so live screens follow.
static func apply() -> void:
	var theme := ThemeDB.get_project_theme()
	if theme == null:
		return
	var font := body()
	if theme.default_font != font:
		theme.default_font = font


## The font for ordinary text (what the theme hands every Control). Null means
## the engine default; use `control.get_theme_default_font()` to measure with it.
static func body() -> Font:
	return READABLE_FILE if readable() else DEFAULT


## Run `callback` whenever the font changes, for as long as `owner` lives (the
## follower is its child, so the connection dies with it).
static func follow(owner: Node, callback: Callable) -> void:
	var follower := _Follower.new()
	follower.on_change = callback
	owner.add_child(follower)


class _Follower extends Node:
	var on_change: Callable

	func _ready() -> void:
		SaveManager.ui_font_changed.connect(_on_changed)

	func _on_changed() -> void:
		if on_change.is_valid():
			on_change.call()

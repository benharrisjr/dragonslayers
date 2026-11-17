extends Node

# Semantic font size constants. Values are the desktop-baseline size (scale = 1.0).
# Use FontSizes.apply(control, FontSizes.BODY) instead of add_theme_font_size_override.
const BADGE          := 15
const CAPTION        := 20
const SMALL          := 22
const BODY           := 24
const BODY_LARGE     := 28
const HEADING_SMALL  := 30
const HEADING        := 38
const HEADING_LARGE  := 52
const OVERLAY        := 64
const SPLASH         := 128

const BASE_WIDTH    := 1280.0
const BASE_HEIGHT   := 720.0
const MIN_SCALE     := 0.85
const MAX_SCALE     := 2.0

# Fixed at 1.0: the project's canvas_items stretch already scales the whole UI
# uniformly with the window, so per-element font scaling only ever desynced
# text from its fixed-size containers (clipped buttons/bars on mobile).
var scale: float = 1.0

func size_of(base: int) -> int:
	return int(round(base * scale))


func apply(control: Control, base: int) -> void:
	control.add_theme_font_size_override("font_size", size_of(base))

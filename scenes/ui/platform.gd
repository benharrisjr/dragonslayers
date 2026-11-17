class_name Platform extends RefCounted

## Device checks and small formatting helpers with no state of their own.

## True on touch-primary devices (mobile/tablet). Key hints are hidden there.
static func is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available()


## True on phone/tablet builds (native or in a mobile browser), where the GPU
## budget is a fraction of a desktop's. GraphicsQuality's AUTO tier keys off it.
static func is_mobile_gpu() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## H:MM:SS for play-time readouts (save slots).
static func format_play_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


## HH:MM:SS.SS, for a speedrun-style clock.
static func format_clock(seconds: float) -> String:
	var total_centis := int(floor(maxf(seconds, 0.0) * 100.0))
	var total_secs := total_centis / 100
	return "%02d:%02d:%02d.%02d" % [total_secs / 3600, (total_secs / 60) % 60, total_secs % 60, total_centis % 100]

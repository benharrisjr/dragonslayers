class_name GraphicsQuality
## The Options "Graphics" setting (a quality tier), plus fullscreen and the
## window preset. A static helper, not an autoload.
##
## The tier is only a switch: the game decides what LOW means. Read is_low()
## wherever an expensive effect is built (post-processing, shadows, particle
## counts) and build the cheaper version when it is true. AUTO resolves to LOW
## on mobile and on weak integrated GPUs (see _detect_low).
##
## The mode lives in this machine's local settings (see _local). set_mode()
## takes effect the next time something reads is_low().

enum Mode { AUTO, HIGH, LOW }

static var _auto_resolved := false
static var _auto_low := false


## ─── Local (per-machine) display settings ────────────────────────────────────
## Graphics tier, fullscreen and window preset describe this machine, not the
## player, so they live in local_settings.cfg beside the saves. Steam Auto-Cloud
## syncs only *.tres (see steam/README.md), so this .cfg never travels: a
## windowed desktop setup can't follow the account onto a Steam Deck.
const LOCAL_SETTINGS_FILE := "local_settings.cfg"
const _SECTION := "display"

static var _local: ConfigFile = null


static func local_settings_path() -> String:
	return SaveManager.save_root + LOCAL_SETTINGS_FILE


static func _settings() -> ConfigFile:
	if _local != null:
		return _local
	var cfg := ConfigFile.new()
	if cfg.load(local_settings_path()) == OK:
		_local = cfg
		return _local
	# First boot on this machine: defaults.
	_local = cfg
	# Steam Deck: a 1920x1080 window overhangs its 1280x800 screen, and the pad
	# cursor's pointer warp gets clamped at the screen edge. Start full.
	if OS.get_environment("SteamDeck") == "1":
		_local.set_value(_SECTION, "fullscreen", true)
	_local.save(local_settings_path())
	return _local


static func _get_local(key: String, default: Variant) -> Variant:
	return _settings().get_value(_SECTION, key, default)


## Store `value` and write the file; false when it was already that.
static func _set_local(key: String, value: Variant) -> bool:
	var cfg := _settings()
	if cfg.get_value(_SECTION, key, null) == value:
		return false
	cfg.set_value(_SECTION, key, value)
	cfg.save(local_settings_path())
	return true


## Tests: drop the cached file so the next read reloads (or re-seeds) it.
static func reset_local_settings_cache() -> void:
	_local = null


static func get_mode() -> Mode:
	return clampi(int(_get_local("graphics_mode", Mode.AUTO)), Mode.AUTO, Mode.LOW) as Mode


static func set_mode(mode: Mode) -> void:
	_set_local("graphics_mode", int(mode))


static func is_low() -> bool:
	var forced := _cmdline_mode()
	if forced != Mode.AUTO:
		return forced == Mode.LOW
	match get_mode():
		Mode.HIGH:
			return Platform.is_mobile_gpu()
		Mode.LOW:
			return true
	return auto_is_low()


## Launch override, for testing a tier on any machine (and as a Steam launch
## option): `-- --graphics=low` or `-- --graphics=high` beats the saved mode.
static var _cmdline_resolved := false
static var _cmdline_value := Mode.AUTO

static func _cmdline_mode() -> Mode:
	if not _cmdline_resolved:
		_cmdline_resolved = true
		for arg in OS.get_cmdline_user_args():
			if arg == "--graphics=low":
				_cmdline_value = Mode.LOW
			elif arg == "--graphics=high":
				_cmdline_value = Mode.HIGH
	return _cmdline_value


## What AUTO resolves to on this machine.
static func auto_is_low() -> bool:
	if not _auto_resolved:
		_auto_low = Platform.is_mobile_gpu() or _detect_low()
		_auto_resolved = true
	return _auto_low


# Intel integrated graphics (HD / UHD / Iris; Arc is a discrete card) and any
# machine Godot moved onto ANGLE because its OpenGL driver is on the known-bad
# list. Both describe the laptops the full desktop path is too heavy for.
static func _detect_low() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	if adapter.contains("intel") and not adapter.contains("arc"):
		return true
	return RenderingServer.get_current_rendering_driver_name().contains("angle")


## Whether this platform has a window to fullscreen. Mobile is always full
## screen and the web build leaves it to the browser.
static func supports_fullscreen() -> bool:
	return OS.has_feature("pc") and DisplayServer.get_name() != "headless"


## The window's actual state, so Options reflects an OS-level change too (the
## macOS green button) rather than a stale saved flag.
static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func set_fullscreen(on: bool) -> void:
	_set_local("fullscreen", on)
	_write_window_override(on)
	_apply_window_mode(on)


## Boot: put the window in the saved mode.
static func apply_saved_window_mode() -> void:
	var on := bool(_get_local("fullscreen", false))
	_write_window_override(on)
	_apply_frame(get_window_preset())
	if on:
		_apply_window_mode(true)
	elif get_window_preset() == WindowPreset.STEAM_DECK:
		_apply_window_preset(WindowPreset.STEAM_DECK)
	else:
		_fit_window_to_screen()


## Options "Resolution": preview the Steam Deck's screen. STEAM_DECK pins the
## game's frame to the Deck's 16:10 canvas (1920x1200 logical, letterboxed in
## whatever window it's in  fullscreen and the editor's embedded Game tab
## included), and when windowed also sizes the window to 1280x800. DEFAULT is the
## project's own frame (expanding to fill the window) at its own window size.
enum WindowPreset { DEFAULT, STEAM_DECK }
const STEAM_DECK_SIZE := Vector2i(1280, 800)
const STEAM_DECK_FRAME := Vector2i(1920, 1200)


static func get_window_preset() -> WindowPreset:
	return clampi(int(_get_local("window_preset", WindowPreset.DEFAULT)),
			WindowPreset.DEFAULT, WindowPreset.STEAM_DECK) as WindowPreset


static func set_window_preset(preset: WindowPreset) -> void:
	_set_local("window_preset", int(preset))
	_apply_frame(preset)
	if not Engine.is_embedded_in_editor():
		_apply_window_preset.call_deferred(preset)


## The root window's content frame: the Deck's fixed 16:10 canvas (KEEP, so
## any other window shape letterboxes it), or the project's expanding default.
static func _apply_frame(preset: WindowPreset) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var root := tree.root
	if preset == WindowPreset.STEAM_DECK:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = STEAM_DECK_FRAME
	else:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.content_scale_size = _project_size()


static func _project_size() -> Vector2i:
	return Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width")),
			int(ProjectSettings.get_setting("display/window/size/viewport_height")))


static func _apply_window_preset(preset: WindowPreset) -> void:
	if not supports_fullscreen() or is_fullscreen():
		return
	var size := STEAM_DECK_SIZE if preset == WindowPreset.STEAM_DECK else _project_size()
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
	# Still too big for this screen (the default on a small display): shrink to fit.
	_fit_window_to_screen()


## The engine opens the window from project settings before any script runs, so
## a saved fullscreen used to show a windowed 1920x1080 frame (title bar, splash)
## and then animate into fullscreen once SaveManager loaded. project.godot points
## application/config/project_settings_override at this file, which the engine
## reads at startup (exports and F5 runs, not the editor), so the next launch
## opens straight in the saved mode.
const WINDOW_OVERRIDE_PATH := "user://window_override.cfg"

static func _write_window_override(on: bool) -> void:
	if not supports_fullscreen():
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	var cfg := ConfigFile.new()
	if cfg.load(WINDOW_OVERRIDE_PATH) == OK \
			and int(cfg.get_value("display", "window/size/mode", -1)) == mode:
		return
	cfg.set_value("display", "window/size/mode", mode)
	cfg.save(WINDOW_OVERRIDE_PATH)


# Borderless fullscreen rather than exclusive: alt-tabbing out stays instant.
static func _apply_window_mode(on: bool) -> void:
	if not supports_fullscreen() or on == is_fullscreen():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on
		else DisplayServer.WINDOW_MODE_WINDOWED)
	if not on:
		if get_window_preset() == WindowPreset.STEAM_DECK:
			_apply_window_preset.call_deferred(WindowPreset.STEAM_DECK)
		else:
			_fit_window_to_screen.call_deferred()


## A windowed game bigger than its screen (the 1920x1080 default on a 1280x800
## Steam Deck) overhangs it, and the OS clamps the pad cursor's pointer warps at
## the screen edge  drags then stall two-thirds of the way across. Shrink it to
## the usable area at the project's aspect and centre it.
static func _fit_window_to_screen() -> void:
	if not supports_fullscreen() or is_fullscreen():
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var size := DisplayServer.window_get_size()
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	if size.x <= usable.size.x and size.y <= usable.size.y:
		return
	var scale := minf(float(usable.size.x) / size.x, float(usable.size.y) / size.y)
	var fitted := Vector2i((Vector2(size) * scale).floor())
	DisplayServer.window_set_size(fitted)
	DisplayServer.window_set_position(usable.position + (usable.size - fitted) / 2)

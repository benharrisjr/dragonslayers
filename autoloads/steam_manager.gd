extends Node
## Optional, defensive wrapper around the GodotSteam GDExtension
## (addons/godotsteam, v4.22-gde / Steamworks SDK 1.65).
##
## Everything here goes through Engine.get_singleton(&"Steam") rather than the
## bare `Steam` identifier, and that is not stylistic: `Steam` is resolved by the
## GDScript *parser*, so a single bare reference turns "addon not installed" from
## a graceful no-op into a project-wide parse failure that takes the autoloads
## with it. Never write `Steam.` anywhere in this codebase  this file is the one
## place that talks to the extension, and it does so by name.
##
## When the extension is absent (Web, mobile, or a clone without addons/) every
## method below no-ops and returns false, and is_available() stays false forever.
## The achievement layer reads that as "queue it for later"  see
## autoloads/achievement_service.gd.

signal availability_changed(available: bool)
## Emitted once Steam has handed us the account's current achievement state.
signal stats_ready

## Steamworks App ID, set in data/project_config.gd. The template default, 480, is
## Valve's public Spacewar test app, which has real registered achievements
## (ACH_WIN_ONE_GAME, ACH_WIN_100_GAMES) and is the right sandbox for proving the
## toast path before the game has its own app.
const APP_ID: int = ProjectConfig.STEAM_APP_ID

const SINGLETON_NAME := &"Steam"

var _steam: Object = null
var _available: bool = false
var _stats_ready: bool = false
var _status_text: String = "not initialised"


func is_available() -> bool:
	return _available


## True once achievement state is safe to read and write. set_achievement() before
## this point is unreliable, so every push waits on it.
func is_stats_ready() -> bool:
	return _available and _stats_ready


## Human-readable reason we are or aren't connected. Shown by tests/steam_check.gd.
func get_status_text() -> String:
	return _status_text


func _ready() -> void:
	# Callbacks must keep pumping while the tree is paused: a stalled callback
	# queue stalls the overlay.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	if not FeatureFlags.STEAM_INTEGRATION:
		_status_text = "disabled by FeatureFlags.STEAM_INTEGRATION"
		return
	if OS.has_feature("web") or OS.has_feature("mobile"):
		_status_text = "Steam is desktop-only on this build"
		return
	# Headless test runs boot every autoload against the developer's real saves;
	# with Steam up, AchievementService would grant real account achievements
	# from them. Windowed runs (editor F5, shot harnesses) still connect.
	if DisplayServer.get_name() == "headless":
		_status_text = "skipped under the headless display server"
		return
	if APP_ID <= 0:
		_status_text = "STEAM_APP_ID not set in data/project_config.gd"
		print("Steam: %s  achievements stay local." % _status_text)
		return
	if not Engine.has_singleton(SINGLETON_NAME):
		_status_text = "GodotSteam extension not loaded (addons/godotsteam missing)"
		print("Steam: %s  achievements stay local." % _status_text)
		return
	_steam = Engine.get_singleton(SINGLETON_NAME)
	_init_steam()


## The Steam client sets SteamAppId when it launches us, and steamInitEx would
## overwrite it with whatever we pass. Honour it so the demo app (its own App ID)
## initialises as the demo; editor/dev runs without it fall back to APP_ID.
func _launch_app_id() -> int:
	var env_id: String = OS.get_environment("SteamAppId")
	if env_id.is_valid_int() and int(env_id) > 0:
		return int(env_id)
	return APP_ID


func _init_steam() -> void:
	# GodotSteam 4.x: steamInitEx(app_id, embed_callbacks) -> {status: int, verbal: String},
	# status 0 == STEAM_API_INIT_RESULT_OK. This signature has drifted across
	# GodotSteam majors (older builds took a leading retrieve_stats bool), so read
	# the result defensively rather than trusting its shape.
	var app_id: int = _launch_app_id()
	var result: Variant = _steam.call(&"steamInitEx", app_id, false)
	if typeof(result) != TYPE_DICTIONARY:
		_status_text = "steamInitEx returned %s, expected Dictionary" % type_string(typeof(result))
		push_warning("Steam: %s" % _status_text)
		return
	var info: Dictionary = result
	var status: int = int(info.get("status", -1))
	_status_text = str(info.get("verbal", "unknown"))
	if status != 0:
		print("Steam: init failed (%d)  %s" % [status, _status_text])
		return

	_available = true
	set_process(true)

	# Steamworks SDK 1.61+ syncs the local user's stats at client boot, and
	# GodotSteam dropped requestCurrentStats in 4.12. Older addons still need the
	# explicit request, so ask for it only if this build still has it.
	if _steam.has_method(&"requestCurrentStats"):
		if _steam.has_signal(&"current_stats_received"):
			_steam.connect(&"current_stats_received", _on_current_stats_received)
		_steam.call(&"requestCurrentStats")
	else:
		_stats_ready = true

	print("Steam: ready (app %d, user %d)" % [app_id, get_steam_id()])
	print("Steam: %s" % cloud_summary())
	availability_changed.emit(true)
	if _stats_ready:
		stats_ready.emit()


func _process(_delta: float) -> void:
	_steam.call(&"run_callbacks")


func _on_current_stats_received(_game_id: int, _result: int, _user_id: int) -> void:
	if _stats_ready:
		return
	_stats_ready = true
	stats_ready.emit()


## ─── Achievements (every call is a no-op returning false when Steam is down) ──

func set_achievement(api_name: String) -> bool:
	if not is_stats_ready() or api_name.is_empty():
		return false
	return bool(_steam.call(&"setAchievement", api_name))


## Dev/testing only. Steam achievements are sticky per account, so without this
## you get exactly one shot at watching each toast.
func clear_achievement(api_name: String) -> bool:
	if not is_stats_ready() or api_name.is_empty():
		return false
	return bool(_steam.call(&"clearAchievement", api_name))


## True only when Steam's own copy already records this achievement. Used to
## repair a wiped local mirror (fresh install, cloud rollback) from the
## authoritative server state.
func is_achievement_set(api_name: String) -> bool:
	if not is_stats_ready() or api_name.is_empty():
		return false
	var info: Variant = _steam.call(&"getAchievement", api_name)
	if typeof(info) != TYPE_DICTIONARY:
		return false
	return bool((info as Dictionary).get("achieved", false))


## Commits pending set_achievement() calls and fires the overlay toast. Steam rate
## limits this, so call it once per evaluation batch  never once per achievement.
func store_stats() -> bool:
	if not is_stats_ready():
		return false
	return bool(_steam.call(&"storeStats"))


func get_steam_id() -> int:
	if not _available:
		return 0
	return int(_steam.call(&"getSteamID"))


func get_persona_name() -> String:
	if not _available:
		return ""
	return str(_steam.call(&"getPersonaName"))


## ─── Steam Cloud (diagnostics only) ──────────────────────────────────────────
## Saves reach the cloud through Steam Auto-Cloud (partner-site config, see
## steam/README.md), not through this API: Steam uploads the matching user://
## files after the process exits. This only reports what Steam sees.

## {account: bool, app: bool, files: [{name, size}], total: int, available: int}.
## Empty when Steam is down.
func get_cloud_status() -> Dictionary:
	if not _available:
		return {}
	var files: Array[Dictionary] = []
	for i in int(_steam.call(&"getFileCount")):
		var info: Variant = _steam.call(&"getFileNameAndSize", i)
		if typeof(info) == TYPE_DICTIONARY:
			files.append({"name": str(info.get("name", "")), "size": int(info.get("size", 0))})
	var quota: Variant = _steam.call(&"getQuota")
	var q: Dictionary = quota if typeof(quota) == TYPE_DICTIONARY else {}
	return {
		"account": bool(_steam.call(&"isCloudEnabledForAccount")),
		"app": bool(_steam.call(&"isCloudEnabledForApp")),
		"files": files,
		"total": int(q.get("total_bytes", 0)),
		"available": int(q.get("available_bytes", 0)),
	}


## One line for the boot log, e.g. "Cloud: account on, app on, 4 files".
func cloud_summary() -> String:
	var st := get_cloud_status()
	if st.is_empty():
		return "Cloud: Steam not available"
	return "Cloud: account %s, app %s, %d files" % [
		"on" if st["account"] else "OFF", "on" if st["app"] else "OFF",
		(st["files"] as Array).size()]


## Raises Steam's floating on-screen keyboard over `rect` (a text field's
## global rect), on a Steam Deck or in Big Picture only; its keystrokes arrive
## as ordinary key events. Returns false when there's no Deck/Steam to ask.
func show_text_input(rect: Rect2, multiline: bool = false) -> bool:
	if not _available or not _wants_floating_keyboard():
		return false
	# FloatingGamepadTextInputMode: 0 single line, 1 multiple lines.
	return bool(_steam.call(&"showFloatingGamepadTextInput", 1 if multiline else 0,
			int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)))


## Our GodotSteam build (4.22-gde) doesn't bind isSteamRunningOnSteamDeck, so
## the Deck is detected by the SteamDeck=1 env var Steam sets there; Big Picture
## covers a pad on desktop. Every name is checked before it's called.
func _wants_floating_keyboard() -> bool:
	if OS.get_environment("SteamDeck") == "1":
		return true
	for method: StringName in [&"isSteamRunningOnSteamDeck", &"isSteamInBigPictureMode"]:
		if _steam.has_method(method) and bool(_steam.call(method)):
			return true
	return false


func open_overlay_to_achievements() -> void:
	if not _available:
		return
	_steam.call(&"activateGameOverlay", "Achievements")


## Called from SaveManager.request_quit() so the API closes down before the process
## exits and Steam's cloud sync starts.
func shutdown() -> void:
	if not _available:
		return
	set_process(false)
	_steam.call(&"steamShutdown")
	_available = false
	_stats_ready = false
	availability_changed.emit(false)

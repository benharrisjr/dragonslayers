extends Node
## Headless check for the Steam + achievements groundwork. Runs with no Steam
## client and no addons/godotsteam present, which is exactly the degraded path
## every non-desktop export takes  so a green run here is the proof that a clone
## without the addon still boots.
##
## It also checks the roster is coherent (ids and API names unique, each
## condition reading a value of the right kind) and walks the sample
## achievements through evaluate() and grant(). Extend the evaluation half as
## the game adds achievements.
##
##   Godot --headless --path <project> tests/steam_check.tscn

var failures := 0


func _check(label: String, got, want) -> void:
	if got == want:
		print("PASS %s -> %s" % [label, got])
	else:
		print("FAIL %s -> got %s want %s" % [label, got, want])
		failures += 1


## SaveData's real property list: name -> Variant.Type. Built once, and used
## instead of sd.get(name) because get() on a missing property returns null *and*
## pushes an error, which would bury the actual failures in noise.
func _save_data_props() -> Dictionary:
	var props: Dictionary = {}
	for p in SaveData.new().get_property_list():
		props[StringName(p["name"])] = int(p["type"])
	return props


## Steam API Names accept only [A-Za-z0-9_]. Note is_valid_identifier() is the
## wrong tool per-character: it rejects a lone digit, so it would fail a perfectly
## legal name like ACH_100_WINS.
func _is_api_name_safe(api_name: String) -> bool:
	if api_name != api_name.strip_edges() or api_name.is_empty():
		return false
	for c in api_name:
		var ok := c == "_" or (c >= "0" and c <= "9") \
			or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")
		if not ok:
			return false
	return true


## The Variant types a SaveData *field* may have for a condition kind. (A name
## that is not a SaveData field is a stats / flags key and has no type to check.)
func _expected_types(condition: int) -> Array:
	match condition:
		AchievementData.ConditionType.BOOL_FLAG:
			return [TYPE_BOOL]
		AchievementData.ConditionType.STAT_AT_LEAST:
			return [TYPE_INT, TYPE_FLOAT]
		AchievementData.ConditionType.DICT_ENTRY_AT_LEAST, \
		AchievementData.ConditionType.DICT_KEY_TRUE, \
		AchievementData.ConditionType.DICT_TRUE_COUNT_AT_LEAST, \
		AchievementData.ConditionType.DICT_MAX_AT_LEAST:
			return [TYPE_DICTIONARY]
		AchievementData.ConditionType.ARRAY_CONTAINS, \
		AchievementData.ConditionType.ARRAY_SIZE_AT_LEAST:
			return [TYPE_ARRAY]
	return []


## Kinds that can read a bare stats / flags key instead of a SaveData field.
const _KEYED_KINDS := [
	AchievementData.ConditionType.BOOL_FLAG,
	AchievementData.ConditionType.STAT_AT_LEAST,
]


func _ready() -> void:
	print("INFO ACHIEVEMENTS flag: %s" % FeatureFlags.ACHIEVEMENTS)

	# --- Roster integrity ---
	var defs := Achievements.get_all_defs()
	_check("roster loaded", defs.size() > 0, true)

	var seen_ids: Dictionary = {}
	var seen_api: Dictionary = {}
	var props := _save_data_props()
	for ach in defs:
		var tag := String(ach.id) if ach.id != &"" else "<empty id>"
		_check("%s has id" % tag, ach.id != &"", true)
		_check("%s id unique" % tag, not seen_ids.has(ach.id), true)
		seen_ids[ach.id] = true
		_check("%s has display_name" % tag, not ach.display_name.is_empty(), true)
		_check("%s required_count >= 1" % tag, ach.required_count >= 1, true)

		if not ach.steam_api_name.is_empty():
			_check("%s api name unique" % tag, not seen_api.has(ach.steam_api_name), true)
			seen_api[ach.steam_api_name] = true
			_check("%s api name is ascii-safe" % tag, _is_api_name_safe(ach.steam_api_name), true)

		if ach.condition == AchievementData.ConditionType.MANUAL:
			_check("%s MANUAL has no save_field" % tag, ach.save_field, &"")
		else:
			_check("%s has save_field" % tag, ach.save_field != &"", true)
			if props.has(ach.save_field):
				_check("%s save_field type" % tag,
					_expected_types(ach.condition).has(int(props[ach.save_field])), true)
			else:
				# Not a SaveData field, so it must be a stats / flags key, which
				# only the scalar kinds can read.
				_check("%s reads a stats/flags key" % tag, _KEYED_KINDS.has(ach.condition), true)

	# --- SteamManager degrades instead of erroring ---
	_check("steam unavailable headless", SteamManager.is_available(), false)
	_check("steam stats not ready", SteamManager.is_stats_ready(), false)
	_check("set_achievement no-ops", SteamManager.set_achievement("ACH_DRAGON_SLAIN"), false)
	_check("store_stats no-ops", SteamManager.store_stats(), false)
	_check("is_achievement_set no-ops", SteamManager.is_achievement_set("ACH_DRAGON_SLAIN"), false)
	_check("steam id is zero", SteamManager.get_steam_id(), 0)
	_check("cloud status empty", SteamManager.get_cloud_status().is_empty(), true)
	print("INFO steam %s" % SteamManager.cloud_summary())
	SteamManager.open_overlay_to_achievements()   # must not crash
	SteamManager.shutdown()                        # must not crash
	print("INFO steam status: %s" % SteamManager.get_status_text())

	# --- Evaluation, without touching the developer's real save state ---
	# Swap in a blank SaveData: the counts below must not depend on what the
	# sandbox save happens to hold.
	Achievements.persist_enabled = false
	SaveManager.save_data = SaveData.new()
	SaveManager.save_data.stats = {}
	SaveManager.save_data.flags = {}
	var cfg := SaveManager.global_config
	cfg.achievements_unlocked.clear()
	cfg.achievement_unlock_times.clear()
	cfg.achievements_pending_steam = []

	# Flag off: evaluation and grant() must be inert (nothing earned, nothing
	# queued for Steam) and the rest of this suite doesn't apply.
	if not FeatureFlags.ACHIEVEMENTS:
		SaveManager.add_stat(&"dragons_slain", 10)
		Achievements.evaluate()
		Achievements.grant(&"dragon_slain")
		_check("flag off: nothing earned", Achievements.get_unlocked_count(), 0)
		_check("flag off: nothing queued for steam", cfg.achievements_pending_steam.is_empty(), true)
		print("STEAM CHECK COMPLETE: %d failures" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return

	# The sample roster: `veteran_slayer` is STAT_AT_LEAST on the stats key "dragons_slain",
	# `dragon_slain` is MANUAL.
	Achievements.evaluate()
	_check("blank save earns nothing", Achievements.get_unlocked_count(), 0)
	SaveManager.add_stat(&"dragons_slain", 6)
	Achievements.evaluate()
	_check("6 kills isn't 10", Achievements.is_unlocked(&"veteran_slayer"), false)
	_check("progress mid-way", Achievements.get_progress(Achievements.get_def(&"veteran_slayer")),
		Vector2i(6, 10))
	SaveManager.add_stat(&"dragons_slain", 4)
	Achievements.evaluate()
	_check("veteran_slayer unlocked", Achievements.is_unlocked(&"veteran_slayer"), true)
	_check("veteran_slayer queued for steam", cfg.achievements_pending_steam.has(&"veteran_slayer"), true)
	_check("unlock time recorded", Achievements.get_unlock_time(&"veteran_slayer") > 0, true)
	_check("MANUAL not auto-granted", Achievements.is_unlocked(&"dragon_slain"), false)
	_check("unlocked count", Achievements.get_unlocked_count(), 1)
	_check("MANUAL has no progress",
		Achievements.get_progress(Achievements.get_def(&"dragon_slain")), Vector2i.ZERO)

	# grant() is idempotent, and an unknown id is a warning, not a crash.
	Achievements.grant(&"dragon_slain")
	var t := Achievements.get_unlock_time(&"dragon_slain")
	Achievements.grant(&"dragon_slain")
	_check("dragon_slain granted", Achievements.is_unlocked(&"dragon_slain"), true)
	_check("grant is idempotent", Achievements.get_unlock_time(&"dragon_slain"), t)
	Achievements.grant(&"no_such_achievement")
	_check("unknown id earns nothing", Achievements.get_unlocked_count(), 2)

	# flush_pending() without Steam keeps the queue for a later boot.
	Achievements.flush_pending()
	_check("queue kept while steam is down", cfg.achievements_pending_steam.size(), 2)

	cfg.achievements_unlocked.clear()
	cfg.achievement_unlock_times.clear()
	cfg.achievements_pending_steam = []

	print("STEAM CHECK COMPLETE: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)

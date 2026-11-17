extends Node
## Achievement evaluation and persistence.
##
## Most achievements are declarative (AchievementData names a SaveData field or a
## key in save_data.stats / save_data.flags plus a condition), so evaluate() walks
## every definition, skips the already-earned, marks what is now satisfied, and
## persists once at the end. Call evaluate() after the game changes a counter;
## call grant(id) for event-shaped MANUAL ones. "Earned" lives cross-slot in
## SaveManager.global_config, because Steam achievements belong to the account.
##
## Steam is optional here. Everything works with the extension absent; unlocks
## simply queue in global_config.achievements_pending_steam until a boot where
## SteamManager is up.

signal achievement_unlocked(ach: AchievementData)

const ROSTER: AchievementListData = preload("res://data/achievements/achievements.tres")

## Set false by tests/steam_check.gd so evaluation never writes into the
## developer's real user://global_config.tres.
var persist_enabled: bool = true

## The roster .tres types its array by script path, which GDScript does not unify
## with the AchievementData class_name at parse time. Copying through a declared
## Array[AchievementData] once gives the rest of the file a properly typed view.
var _defs_cache: Array[AchievementData] = []


func _ready() -> void:
	if not FeatureFlags.ACHIEVEMENTS:
		return
	# Autoload order puts this after SaveManager, so save_data and global_config
	# are both live by now. SaveManager can't call us during its own _ready (this
	# node doesn't exist yet), hence the signal rather than a direct call.
	SaveManager.save_loaded.connect(_on_save_loaded)
	SteamManager.stats_ready.connect(_on_steam_stats_ready)
	_on_save_loaded()
	# SteamManager sits earlier in the autoload order, and a GodotSteam that syncs
	# stats at client boot (no requestCurrentStats) emits stats_ready from inside
	# its own _ready()  before the connect above. Catch up on that missed signal,
	# or achievements queued while Steam was down would never reach it.
	if SteamManager.is_stats_ready():
		_on_steam_stats_ready()


func _on_save_loaded() -> void:
	# Retro-grant: a save that already satisfies a newly shipped achievement earns
	# it on the first boot after it lands.
	evaluate()



func _on_steam_stats_ready() -> void:
	_reconcile_from_steam()
	flush_pending()


## ─── Queries ─────────────────────────────────────────────────────────────────

func get_all_defs() -> Array[AchievementData]:
	if _defs_cache.is_empty():
		for ach in ROSTER.achievements:
			if ach != null:
				_defs_cache.append(ach)
	return _defs_cache


func get_def(achievement_id: StringName) -> AchievementData:
	for ach in get_all_defs():
		if ach.id == achievement_id:
			return ach
	return null


func is_unlocked(achievement_id: StringName) -> bool:
	if SaveManager.global_config == null:
		return false
	return bool(SaveManager.global_config.achievements_unlocked.get(achievement_id, false))


func get_unlock_time(achievement_id: StringName) -> int:
	if SaveManager.global_config == null:
		return 0
	return int(SaveManager.global_config.achievement_unlock_times.get(achievement_id, 0))


func get_unlocked_count() -> int:
	var n := 0
	for ach in get_all_defs():
		if is_unlocked(ach.id):
			n += 1
	return n


## (current, required) for the Achievements panel's progress readout. Zero when
## the achievement has no meaningful progress figure.
func get_progress(ach: AchievementData) -> Vector2i:
	if ach == null or not ach.has_progress() or SaveManager.save_data == null:
		return Vector2i.ZERO
	return Vector2i(mini(_progress_value(ach), ach.required_count), ach.required_count)



## ─── Granting ────────────────────────────────────────────────────────────────

## The MANUAL escape hatch, for unlocks no persisted counter describes. Idempotent.
func grant(achievement_id: StringName) -> void:
	if not FeatureFlags.ACHIEVEMENTS:
		return
	if SaveManager.global_config == null:
		return
	if is_unlocked(achievement_id):
		return
	var ach := get_def(achievement_id)
	if ach == null:
		push_warning("Achievements.grant: no definition for '%s'" % achievement_id)
		return
	_mark_unlocked(ach)
	if _push_to_steam(ach):
		SteamManager.store_stats()
	_persist()


## Full declarative sweep. Cheap (the roster is small), so it is safe to call
## from frequent chokepoints: every time a tracked counter changes.
func evaluate() -> void:
	if not FeatureFlags.ACHIEVEMENTS:
		return
	if SaveManager.save_data == null or SaveManager.global_config == null:
		return
	var changed := false
	var pushed := false
	for ach in get_all_defs():
		if ach.condition == AchievementData.ConditionType.MANUAL:
			continue
		if is_unlocked(ach.id):
			continue
		if not _condition_met(ach):
			continue
		_mark_unlocked(ach)
		changed = true
		pushed = _push_to_steam(ach) or pushed
	if pushed:
		SteamManager.store_stats()
	if changed:
		_persist()



## Push everything earned while Steam was down, then clear the queue.
func flush_pending() -> void:
	var cfg := SaveManager.global_config
	if cfg == null or cfg.achievements_pending_steam.is_empty():
		return
	if not SteamManager.is_stats_ready():
		return
	var still_pending: Array[StringName] = []
	var pushed := false
	for achievement_id in cfg.achievements_pending_steam:
		var ach := get_def(achievement_id)
		# A definition removed since it was queued, or a local-only one: drop it.
		if ach == null or ach.steam_api_name.is_empty():
			continue
		if SteamManager.set_achievement(ach.steam_api_name):
			pushed = true
		else:
			still_pending.append(achievement_id)
	cfg.achievements_pending_steam = still_pending
	if pushed:
		SteamManager.store_stats()
	_persist()


## ─── Internals ───────────────────────────────────────────────────────────────

func _mark_unlocked(ach: AchievementData) -> void:
	var cfg := SaveManager.global_config
	cfg.achievements_unlocked[ach.id] = true
	cfg.achievement_unlock_times[ach.id] = int(Time.get_unix_time_from_system())
	achievement_unlocked.emit(ach)


## True when the push reached Steam. Otherwise the id is queued for a later boot.
func _push_to_steam(ach: AchievementData) -> bool:
	if ach.steam_api_name.is_empty():
		return false
	if SteamManager.set_achievement(ach.steam_api_name):
		return true
	var cfg := SaveManager.global_config
	if not cfg.achievements_pending_steam.has(ach.id):
		cfg.achievements_pending_steam.append(ach.id)
	return false


## Steam's server copy is authoritative. Without this, a fresh install or a cloud
## rollback leaves the panel showing achievements the player already owns as locked,
## permanently  evaluate() only ever moves locked -> unlocked from local counters,
## and those counters may have been reset with the save.
func _reconcile_from_steam() -> void:
	var cfg := SaveManager.global_config
	if cfg == null or not SteamManager.is_stats_ready():
		return
	var changed := false
	for ach in get_all_defs():
		if ach.steam_api_name.is_empty():
			continue
		if is_unlocked(ach.id):
			continue
		if SteamManager.is_achievement_set(ach.steam_api_name):
			cfg.achievements_unlocked[ach.id] = true
			if not cfg.achievement_unlock_times.has(ach.id):
				cfg.achievement_unlock_times[ach.id] = int(Time.get_unix_time_from_system())
			changed = true
	if changed:
		_persist()


func _persist() -> void:
	if persist_enabled:
		SaveManager.save_global_config()


## The value a field-based condition reads: a SaveData property of that name if
## there is one, else the entry in save_data.flags (BOOL_FLAG) or save_data.stats
## (everything else). Null when nothing by that name exists yet.
func _field_value(ach: AchievementData) -> Variant:
	var save := SaveManager.save_data
	if save == null or ach.save_field == &"":
		return null
	if ach.save_field in save:
		return save.get(ach.save_field)
	if ach.condition == AchievementData.ConditionType.BOOL_FLAG:
		return save.flags.get(ach.save_field)
	return save.stats.get(ach.save_field)


func _condition_met(ach: AchievementData) -> bool:
	var value: Variant = _field_value(ach)
	if value == null:
		return false
	match ach.condition:
		AchievementData.ConditionType.BOOL_FLAG:
			return bool(value)
		AchievementData.ConditionType.STAT_AT_LEAST:
			return int(value) >= ach.required_count
		AchievementData.ConditionType.DICT_ENTRY_AT_LEAST:
			return value is Dictionary and int(value.get(ach.target_key, 0)) >= ach.required_count
		AchievementData.ConditionType.DICT_KEY_TRUE:
			return value is Dictionary and bool(value.get(ach.target_key, false))
		AchievementData.ConditionType.DICT_TRUE_COUNT_AT_LEAST:
			return value is Dictionary and _true_count(value) >= ach.required_count
		AchievementData.ConditionType.ARRAY_CONTAINS:
			return value is Array and value.has(ach.target_key)
		AchievementData.ConditionType.ARRAY_SIZE_AT_LEAST:
			return value is Array and value.size() >= ach.required_count
		AchievementData.ConditionType.DICT_MAX_AT_LEAST:
			return value is Dictionary and _max_value(value) >= ach.required_count
	return false


func _progress_value(ach: AchievementData) -> int:
	var value: Variant = _field_value(ach)
	if value == null:
		return 0
	match ach.condition:
		AchievementData.ConditionType.STAT_AT_LEAST:
			return int(value)
		AchievementData.ConditionType.DICT_ENTRY_AT_LEAST:
			return int(value.get(ach.target_key, 0)) if value is Dictionary else 0
		AchievementData.ConditionType.DICT_TRUE_COUNT_AT_LEAST:
			return _true_count(value) if value is Dictionary else 0
		AchievementData.ConditionType.ARRAY_SIZE_AT_LEAST:
			return value.size() if value is Array else 0
		AchievementData.ConditionType.DICT_MAX_AT_LEAST:
			return _max_value(value) if value is Dictionary else 0
	return 0



func _max_value(d: Dictionary) -> int:
	var best := 0
	for k in d:
		best = maxi(best, int(d[k]))
	return best


func _true_count(d: Dictionary) -> int:
	var n := 0
	for k in d:
		if d[k]:
			n += 1
	return n

class_name AchievementData extends Resource

## One achievement. Most are declarative (a condition kind plus the name of the
## value it reads), so adding one is a .tres edit with no code. MANUAL is the
## escape hatch for event-shaped unlocks no persisted counter describes; those
## are granted by an explicit Achievements.grant(id) call.
##
## `save_field` is looked up as an @export property of SaveData first. When
## SaveData has no property of that name it is a key in save_data.flags
## (BOOL_FLAG) or save_data.stats (every other kind), so a counter kept with
## SaveManager.add_stat(&"clicks") needs no SaveData field of its own.

enum ConditionType {
	MANUAL,                   ## Never auto-evaluated. Granted via Achievements.grant().
	BOOL_FLAG,                ## the value is true (a bool field, or a flags entry).
	STAT_AT_LEAST,            ## the value is a number >= required_count (a field, or a stats entry).
	DICT_ENTRY_AT_LEAST,      ## value[target_key] >= required_count.
	DICT_KEY_TRUE,            ## value[target_key] is true.
	DICT_TRUE_COUNT_AT_LEAST, ## number of true values in the dictionary >= required_count.
	ARRAY_CONTAINS,           ## the array has target_key.
	ARRAY_SIZE_AT_LEAST,      ## array.size() >= required_count.
	DICT_MAX_AT_LEAST,        ## largest value in the dictionary >= required_count.
}

## Stable internal id. Never rename or reuse  it keys achievements_unlocked in
## user://global_config.tres, so changing it silently re-locks it for everyone.
@export var id: StringName = &""
## Steamworks API Name, matched character-for-character (convention:
## ACH_SCREAMING_SNAKE). Empty = a local-only achievement that never reaches Steam.
@export var steam_api_name: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null
## Masked to "???" in the Achievements panel until earned. Mirror this on the
## Steamworks partner site so the two agree.
@export var hidden: bool = false

@export var condition: ConditionType = ConditionType.MANUAL
## Name of the SaveData field, or the stats / flags key, this reads (see the
## note at the top). A typo here ships an achievement that can never fire.
@export var save_field: StringName = &""
## Dictionary/Array key, for the DICT_ENTRY_/DICT_KEY_/ARRAY_CONTAINS kinds.
@export var target_key: StringName = &""
@export var required_count: int = 1
## Show a current / required figure in the Achievements panel. Meaningless for the boolean kinds.
@export var show_progress: bool = true
## Ascending display order within the locked group.
@export var sort_order: int = 0


## True when this achievement's condition can show a "current / required" figure.
func has_progress() -> bool:
	if not show_progress:
		return false
	if required_count <= 1:
		return false
	match condition:
		ConditionType.STAT_AT_LEAST, ConditionType.DICT_ENTRY_AT_LEAST, \
		ConditionType.DICT_TRUE_COUNT_AT_LEAST, ConditionType.ARRAY_SIZE_AT_LEAST, \
		ConditionType.DICT_MAX_AT_LEAST:
			return true
	return false

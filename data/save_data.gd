class_name SaveData extends Resource

## One save slot (user://save_slot_N.tres). Add the game's own @export fields
## here. Anything that should be shared by every slot (settings, achievements)
## belongs in GlobalConfig instead.
##
## Godot shares @export Array/Dictionary defaults between Resource instances, so
## every container field must be re-bound in SaveManager.new_game (see the note
## there) or a fresh slot inherits another slot's contents.

## Bump when a field changes meaning, and convert old saves in
## SaveManager._migrate. A save written before a field existed simply loads with
## that field's default, so adding fields needs no bump.
const CURRENT_VERSION := 1
@export var version: int = CURRENT_VERSION

## Seconds played in this slot (SaveManager counts while the game runs).
@export var play_time_seconds: float = 0.0
## Unix time of the last write, for the slot picker.
@export var last_saved_unix: int = 0

## Free-form counters and switches, keyed by StringName. Achievements can read
## either with no code (AchievementData STAT_AT_LEAST / BOOL_FLAG look a name up
## here when it isn't a field of its own). See SaveManager.add_stat / set_flag.
@export var stats: Dictionary = {}
@export var flags: Dictionary = {}

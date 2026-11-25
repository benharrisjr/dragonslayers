class_name WorldSave extends Resource

## One saved world (user://worlds/world_<id>.tres): the seed it grows from, plus the progress
## made in it. Everything else -- terrain, monsters, scenery, the dragon -- comes back from the
## seed on every load, so a load is a fresh adventure in a world the party has already been
## through: the chests they opened stay open, and their heroes keep what they found.
##
## Written and read by SaveManager (save_world / load_world); filled in from a live match and
## laid back over one by WorldPersistence.

const CURRENT_VERSION := 1
@export var version: int = CURRENT_VERSION

@export var id: int = 0
@export var name: String = ""
@export var world_seed: int = 0
@export var created_unix: int = 0
@export var last_played_unix: int = 0
@export var play_time_seconds: float = 0.0

## The party's shared purse (GameState.gold).
@export var gold: int = 0
## The time of day (DayNight): 0 sunrise, 0.25 noon, 0.5 sunset. A world saved before there was one
## picks up in the morning.
@export var time_of_day: float = 0.06
## How many times this world's dragon has been slain. It is back on every load regardless.
@export var dragons_slain: int = 0
## Chests already opened, by node name (Chest_<chunk>_<NN>, which the seed decides).
@export var opened_chests: PackedStringArray = PackedStringArray()
## Gear lying on the ground when the world was saved -- left in an opened chest's pile, or
## dropped by someone who died -- as {"item": String, "position": Vector3}. Coins and hearts
## are not kept, but losing the only feather to a reload would strand the party.
@export var loose_gear: Array = []
## Dungeon entrances found so far that start hidden (Entrance_<id>): the desert's stairwell, the
## tree's door and the cracked wall.
@export var revealed_entrances: PackedStringArray = PackedStringArray()
## Dungeons' big chests whose guardian has been beaten, but which are still shut. (Guardians come
## back on every load, like the dragon; a chest they guarded stays unlocked.)
@export var unlocked_chests: PackedStringArray = PackedStringArray()
## The world's heroes, one per hero id (String): what PlayerCharacter.save_state returns.
@export var characters: Dictionary = {}


## A short line for the world picker: "3 heroes · dragon slain ×1 · 1h 20m".
func summary() -> String:
	var parts: Array[String] = []
	var heroes := characters.size()
	parts.append("new" if heroes == 0 else "%d hero%s" % [heroes, "" if heroes == 1 else "es"])
	if dragons_slain > 0:
		parts.append("dragon slain ×%d" % dragons_slain)
	var minutes := int(play_time_seconds / 60.0)
	parts.append("%dh %02dm" % [minutes / 60, minutes % 60] if minutes >= 60 else "%dm" % minutes)
	return " · ".join(parts)

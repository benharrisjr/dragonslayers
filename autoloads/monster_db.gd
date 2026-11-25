extends Node

## Enemy definitions. The KayKit skeletons skin to the same Rig_Medium as the players, so they
## share the whole animation set for free -- that is why the enemy roster starts here rather
## than with the Kenney blocky characters, which are rigged differently.

const SKELETON_ROOT := "res://art/KayKit_Skeletons_1.1_FREE/characters/gltf/"

var _monsters: Dictionary = {}


## Every skeleton takes two hits and deals one point (half a heart) a hit. What sets them apart
## is how they move, how far they reach and how hard they shove.
func _ready() -> void:
	_add(_make(&"skeleton_minion", "Skeleton Minion", "Skeleton_Minion.glb", {
		"max_health": 2, "move_speed": 3.6, "damage": 1, "knockback": 11.0,
		"gold": 4, "attack_cooldown": 1.9,
	}))
	_add(_make(&"skeleton_warrior", "Skeleton Warrior", "Skeleton_Warrior.glb", {
		"max_health": 2, "move_speed": 3.2, "damage": 1, "knockback": 15.0,
		"gold": 9, "attack_range": 2.6, "attack_cooldown": 2.2, "scale": 1.1,
		"knockback_resistance": 0.75,
	}))
	_add(_make(&"skeleton_rogue", "Skeleton Rogue", "Skeleton_Rogue.glb", {
		"max_health": 2, "move_speed": 5.2, "damage": 1, "knockback": 8.0,
		"gold": 7, "attack_cooldown": 1.2, "aggro_range": 18.0,
		"attack_anim": "melee/Melee_Dualwield_Attack_Slice",
	}))
	## Rare: rewards an ability rather than gold, and hits hard enough to make the ledge behind
	## you the real threat.
	_add(_make(&"skeleton_mage", "Bone Sorcerer", "Skeleton_Mage.glb", {
		"max_health": 2, "move_speed": 2.8, "damage": 1, "knockback": 20.0,
		"knockback_lift": 0.55, "gold": 25, "is_rare": true, "attack_range": 9.0,
		"attack_cooldown": 2.6, "wind_up": 0.7, "scale": 1.15,
		"attack_anim": "ranged/Ranged_Magic_Shoot",
	}))
	## Each dungeon's guardian: a towering warrior that takes a real beating, hits for a whole
	## heart and barely gives ground. Its big chest stays locked until it falls.
	_add(_make(&"skeleton_champion", "Skeleton Champion", "Skeleton_Warrior.glb", {
		"max_health": 16, "move_speed": 3.0, "damage": 2, "knockback": 19.0,
		"knockback_lift": 0.5, "gold": 60, "attack_range": 3.4, "attack_cooldown": 2.0,
		"wind_up": 0.6, "scale": 1.7, "knockback_resistance": 0.3, "aggro_range": 16.0,
		"leash_range": 40.0,
	}))


func get_monster(id: StringName) -> MonsterData:
	return _monsters.get(id)


func all_ids() -> Array:
	return _monsters.keys()


func _add(m: MonsterData) -> void:
	_monsters[m.id] = m


func _make(id: StringName, name: String, model: String, fields: Dictionary) -> MonsterData:
	var m := MonsterData.new()
	m.id = id
	m.display_name = name
	m.model_path = SKELETON_ROOT + model
	for key: String in fields:
		m.set(key, fields[key])
	return m

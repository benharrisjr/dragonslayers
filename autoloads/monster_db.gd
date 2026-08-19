extends Node

## Enemy definitions. The KayKit skeletons skin to the same Rig_Medium as the players, so they
## share the whole animation set for free -- that is why the enemy roster starts here rather
## than with the Kenney blocky characters, which are rigged differently.

const SKELETON_ROOT := "res://art/KayKit_Skeletons_1.1_FREE/characters/gltf/"

var _monsters: Dictionary = {}


func _ready() -> void:
	_add(_make(&"skeleton_minion", "Skeleton Minion", "Skeleton_Minion.glb", {
		"max_health": 5, "move_speed": 3.6, "damage": 1, "knockback": 11.0,
		"gold": 4, "attack_cooldown": 1.9,
	}))
	_add(_make(&"skeleton_warrior", "Skeleton Warrior", "Skeleton_Warrior.glb", {
		"max_health": 10, "move_speed": 3.2, "damage": 2, "knockback": 15.0,
		"gold": 9, "attack_range": 2.6, "attack_cooldown": 2.2, "scale": 1.1,
		"knockback_resistance": 0.75,
	}))
	_add(_make(&"skeleton_rogue", "Skeleton Rogue", "Skeleton_Rogue.glb", {
		"max_health": 6, "move_speed": 5.2, "damage": 1, "knockback": 8.0,
		"gold": 7, "attack_cooldown": 1.2, "aggro_range": 18.0,
		"attack_anim": "melee/Melee_Dualwield_Attack_Slice",
	}))
	## Rare: rewards an ability rather than gold, and hits hard enough to make the ledge behind
	## you the real threat.
	_add(_make(&"skeleton_mage", "Bone Sorcerer", "Skeleton_Mage.glb", {
		"max_health": 14, "move_speed": 2.8, "damage": 2, "knockback": 20.0,
		"knockback_lift": 0.55, "gold": 25, "is_rare": true, "attack_range": 9.0,
		"attack_cooldown": 2.6, "wind_up": 0.7, "scale": 1.15,
		"attack_anim": "ranged/Ranged_Magic_Shoot",
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

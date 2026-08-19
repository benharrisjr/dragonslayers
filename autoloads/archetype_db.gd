extends Node

## The four playable classes, mapped onto the KayKit adventurer models as specified:
## Knight -> Knight, Shaman -> Barbarian, Archer -> Rogue_Hooded, Wizard -> Mage.

const CHAR_ROOT := "res://art/KayKit_Adventurers_2.0_FREE/Characters/gltf/"
const ASSET_ROOT := "res://art/KayKit_Adventurers_2.0_FREE/Assets/gltf/"

## Order matters: it is the lobby's left-to-right order and the default pick for slots 0-3.
const ORDER: Array[StringName] = [&"knight", &"shaman", &"archer", &"wizard"]

var _archetypes: Dictionary = {}


func _ready() -> void:
	_add(_make(&"knight", "Knight", Color(0.35, 0.55, 0.95), "Knight.glb", {
		"handslot.r": "sword_1handed.gltf",
		"handslot.l": "shield_round.gltf",
	}, {
		"knockback_resistance": 0.7,  ## Armoured: the hardest class to shove off a ledge.
		"move_speed": 6.6,
		"basic": &"knight_swing", "abilities": [&"shield_bash"],
		"attack_idle": "melee/Melee_1H_Attack_Chop",
	}))
	_add(_make(&"shaman", "Shaman", Color(0.55, 0.85, 0.45), "Barbarian.glb", {
		"handslot.r": "staff.gltf",
	}, {
		"knockback_resistance": 0.85,
		"move_speed": 6.9,
		"max_magic": 120.0,
		"basic": &"shaman_swing", "abilities": [&"totem_mend"],
	}))
	_add(_make(&"archer", "Archer", Color(0.95, 0.75, 0.3), "Rogue_Hooded.glb", {
		"handslot.l": "bow_withString.gltf",
		"handslot.r": "quiver.gltf",
	}, {
		"knockback_resistance": 1.1,
		"move_speed": 7.6,
		"jump_velocity": 11.4,  ## Nimblest of the four; reaches ledges the others cannot.
		"basic": &"archer_shot", "abilities": [&"power_shot"],
	}))
	_add(_make(&"wizard", "Wizard", Color(0.7, 0.5, 0.95), "Mage.glb", {
		"handslot.r": "wand.gltf",
		"handslot.l": "spellbook_open.gltf",
	}, {
		"knockback_resistance": 1.35,  ## Light: gets thrown a long way, so play the back line.
		"move_speed": 6.4,
		"max_magic": 140.0,
		"basic": &"wizard_bolt", "abilities": [&"fireball"],
	}))


func get_archetype(id: StringName) -> ArchetypeData:
	return _archetypes.get(id)


func default_for_slot(slot: int) -> StringName:
	return ORDER[slot % ORDER.size()]


func _add(a: ArchetypeData) -> void:
	_archetypes[a.id] = a


func _make(id: StringName, name: String, color: Color, model: String,
		weapons: Dictionary, opts: Dictionary) -> ArchetypeData:
	var a := ArchetypeData.new()
	a.id = id
	a.display_name = name
	a.color = color
	a.model_path = CHAR_ROOT + model
	var resolved := {}
	for bone: String in weapons:
		resolved[bone] = ASSET_ROOT + weapons[bone]
	a.weapon_paths = resolved
	a.basic_attack = AbilityDB.get_ability(opts.get("basic", &""))
	var abilities: Array[AbilityData] = []
	for ability_id: StringName in opts.get("abilities", []):
		abilities.append(AbilityDB.get_ability(ability_id))
	a.abilities = abilities
	for key: String in ["move_speed", "jump_velocity", "max_magic", "max_hearts",
			"knockback_resistance"]:
		if opts.has(key):
			a.set(key, opts[key])
	return a

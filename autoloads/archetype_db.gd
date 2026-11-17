extends Node

## The four heroes. They are looks, not classes: each wears a different KayKit adventurer and
## a different colour, and they are otherwise the same character. What a player can do comes
## from the gear they carry (ItemDB), not from who they picked.

const CHAR_ROOT := "res://art/KayKit_Adventurers_2.0_FREE/Characters/gltf/"
const ASSET_ROOT := "res://art/KayKit_Adventurers_2.0_FREE/Assets/gltf/"

## Order matters: it is the lobby's left-to-right order and the default pick for slots 0-3.
const ORDER: Array[StringName] = [&"knight", &"shaman", &"archer", &"wizard"]

var _archetypes: Dictionary = {}


func _ready() -> void:
	_add(_make(&"knight", "Knight", Color(0.35, 0.55, 0.95), "Knight.glb"))
	_add(_make(&"shaman", "Barbarian", Color(0.55, 0.85, 0.45), "Barbarian.glb"))
	_add(_make(&"archer", "Rogue", Color(0.95, 0.75, 0.3), "Rogue_Hooded.glb"))
	_add(_make(&"wizard", "Mage", Color(0.7, 0.5, 0.95), "Mage.glb"))


func get_archetype(id: StringName) -> ArchetypeData:
	return _archetypes.get(id)


func default_for_slot(slot: int) -> StringName:
	return ORDER[slot % ORDER.size()]


func _add(a: ArchetypeData) -> void:
	_archetypes[a.id] = a


func _make(id: StringName, name: String, color: Color, model: String) -> ArchetypeData:
	var a := ArchetypeData.new()
	a.id = id
	a.display_name = name
	a.color = color
	a.model_path = CHAR_ROOT + model
	## Everyone carries the sword and shield they start with -- and keep through death -- so
	## the models are always in hand whichever hero is wearing them.
	a.weapon_paths = {
		"handslot.r": ASSET_ROOT + "sword_1handed.gltf",
		"handslot.l": ASSET_ROOT + "shield_round.gltf",
	}
	a.basic_attack = AbilityDB.get_ability(&"sword_swing")
	return a

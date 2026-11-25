extends Node

## The five heroes. Each wears a different KayKit adventurer and fights differently: the weapon
## each starts with -- and keeps through death -- is their own, and so is the attack it makes.
## Everything else a player can do comes from the gear they find (ItemDB), whoever they are.
##
##   Knight     sword and shield: a wide slash, and the only one who can block
##   Barbarian  two-handed axe: a slow, heavy chop that sends things flying
##   Thief      dagger: a quick, narrow stab
##   Mage       staff: a bolt of magic, at range
##   Archer     bow: an arrow, at longer range
##
## Holding the attack button charges a stronger move, let loose on release: the Knight and the
## Barbarian spin, the Thief and the Archer throw a flurry of knives or arrows all round them,
## and the Mage lets go a ring of magic.

const CHAR_ROOT := "res://art/KayKit_Adventurers_2.0_FREE/Characters/gltf/"
const ASSET_ROOT := "res://art/KayKit_Adventurers_2.0_FREE/Assets/gltf/"

## Order matters: it is the order the character select steps through, and the default pick for
## slots 0-3 when nobody went through it (command-line starts, tests).
const ORDER: Array[StringName] = [&"knight", &"barbarian", &"thief", &"mage", &"archer"]

var _archetypes: Dictionary = {}


func _ready() -> void:
	_add(_make(&"knight", "Knight", Color(0.35, 0.55, 0.95), "Knight.glb",
			{"handslot.r": "sword_1handed.gltf", "handslot.l": "shield_round.gltf"},
			[ItemDB.SWORD, ItemDB.SHIELD], &"sword_swing", &"sword_spin",
			"Sword and shield. Slashes wide, and blocks."))
	_add(_make(&"barbarian", "Barbarian", Color(0.85, 0.45, 0.3), "Barbarian.glb",
			{"handslot.r": "axe_2handed.gltf"},
			[ItemDB.AXE], &"axe_cleave", &"axe_spin",
			"Two-handed axe. Slow, heavy chops."))
	_add(_make(&"thief", "Thief", Color(0.95, 0.75, 0.3), "Rogue_Hooded.glb",
			{"handslot.r": "dagger.gltf"},
			[ItemDB.DAGGER], &"dagger_stab", &"knife_flurry",
			"Dagger. Quick, close stabs."))
	_add(_make(&"mage", "Mage", Color(0.7, 0.5, 0.95), "Mage.glb",
			{"handslot.r": "staff.gltf"},
			[ItemDB.STAFF], &"magic_bolt", &"magic_ring",
			"Staff. Casts bolts of magic."))
	_add(_make(&"archer", "Archer", Color(0.45, 0.8, 0.45), "Ranger.glb",
			{"handslot.l": "bow_withString.gltf"},
			[ItemDB.BOW], &"bow_shot", &"arrow_flurry",
			"Bow. Long-range arrows."))


func get_archetype(id: StringName) -> ArchetypeData:
	return _archetypes.get(id)


func has(id: StringName) -> bool:
	return _archetypes.has(id)


func default_for_slot(slot: int) -> StringName:
	return ORDER[slot % ORDER.size()]


## The hero `steps` along the character select from `id`, wrapping round.
func step(id: StringName, steps: int) -> StringName:
	var index := maxi(ORDER.find(id), 0)
	return ORDER[posmod(index + steps, ORDER.size())]


func _add(a: ArchetypeData) -> void:
	_archetypes[a.id] = a


func _make(id: StringName, name: String, color: Color, model: String, weapons: Dictionary,
		gear: Array[StringName], attack: StringName, charged: StringName,
		blurb: String) -> ArchetypeData:
	var a := ArchetypeData.new()
	a.id = id
	a.display_name = name
	a.color = color
	a.blurb = blurb
	a.model_path = CHAR_ROOT + model
	var resolved := {}
	for bone: String in weapons:
		resolved[bone] = ASSET_ROOT + weapons[bone]
	a.weapon_paths = resolved
	a.starting_gear = gear
	a.basic_attack = AbilityDB.get_ability(attack)
	a.charged_attack = AbilityDB.get_ability(charged)
	return a

extends Node

## Every ability in the game, built in code rather than as .tres files.
##
## Constructing them here keeps the whole balance table readable in one diff and removes a
## class of bug that hand-written .tres invites -- a mistyped property name in a resource file
## fails silently, a mistyped one here fails at parse time. They are still real AbilityData
## resources, so nothing stops a .tres being dropped in later for editor tweaking.

var _abilities: Dictionary = {}


func _ready() -> void:
	# --- the sword: the one attack every player has, free so nobody is ever helpless ---
	_add(_make(&"sword_swing", "Sword Swing", AbilityData.Shape.MELEE_ARC, {
		"damage": 2, "knockback": 7.0, "range": 3.8, "arc_degrees": 80.0, "cooldown": 0.55,
		"wind_up": 0.22, "animation": "melee/Melee_1H_Attack_Slice_Horizontal",
	}))

	# --- monster attacks live here too, so knockback tuning is all on one screen ---
	_add(_make(&"skeleton_slash", "Bone Slash", AbilityData.Shape.MELEE_ARC, {
		"damage": 1, "knockback": 11.0, "knockback_lift": 0.4, "range": 2.4,
		"arc_degrees": 70.0, "cooldown": 1.9, "wind_up": 0.45,
		"animation": "melee/Melee_1H_Attack_Slice_Horizontal",
	}))


func get_ability(id: StringName) -> AbilityData:
	return _abilities.get(id)


func has(id: StringName) -> bool:
	return _abilities.has(id)


func all_ids() -> Array:
	return _abilities.keys()


func _add(ability: AbilityData) -> void:
	_abilities[ability.id] = ability


func _make(id: StringName, name: String, shape: AbilityData.Shape, fields: Dictionary) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = name
	a.shape = shape
	for key: String in fields:
		a.set(key, fields[key])
	return a

extends Node

## Every ability in the game, built in code rather than as .tres files.
##
## Constructing them here keeps the whole balance table readable in one diff and removes a
## class of bug that hand-written .tres invites -- a mistyped property name in a resource file
## fails silently, a mistyped one here fails at parse time. They are still real AbilityData
## resources, so nothing stops a .tres being dropped in later for editor tweaking.

var _abilities: Dictionary = {}


func _ready() -> void:
	# --- basic weapon attacks (free, so a drained player is never helpless) ---
	_add(_make(&"knight_swing", "Sword Swing", AbilityData.Shape.MELEE_ARC, {
		"damage": 2, "knockback": 7.0, "range": 3.0, "arc_degrees": 65.0, "cooldown": 0.55,
		"wind_up": 0.22, "animation": "melee/Melee_1H_Attack_Chop",
	}))
	_add(_make(&"shaman_swing", "Totem Smash", AbilityData.Shape.MELEE_ARC, {
		"damage": 3, "knockback": 9.0, "range": 3.2, "arc_degrees": 55.0, "cooldown": 0.8,
		"wind_up": 0.34, "animation": "melee/Melee_2H_Attack_Chop", "animation_speed": 1.2,
	}))
	_add(_make(&"archer_shot", "Arrow Shot", AbilityData.Shape.PROJECTILE, {
		"damage": 2, "knockback": 4.0, "range": 26.0, "cooldown": 0.5, "wind_up": 0.3,
		"projectile_speed": 34.0, "animation": "ranged/Ranged_Bow_Release",
		"vfx_color": Color(0.85, 0.8, 0.6),
	}))
	_add(_make(&"wizard_bolt", "Arcane Bolt", AbilityData.Shape.PROJECTILE, {
		"damage": 2, "knockback": 5.0, "range": 22.0, "cooldown": 0.6, "wind_up": 0.3,
		"projectile_speed": 24.0, "animation": "ranged/Ranged_Magic_Shoot",
		"vfx_color": Color(0.5, 0.6, 1.0),
	}))

	# --- one signature ability per class for the slice ---
	_add(_make(&"shield_bash", "Shield Bash", AbilityData.Shape.MELEE_ARC, {
		"damage": 2, "knockback": 22.0, "knockback_lift": 0.5, "range": 3.4,
		"arc_degrees": 75.0, "magic_cost": 25.0, "cooldown": 3.0, "wind_up": 0.2,
		"animation": "melee/Melee_Block_Attack", "vfx_color": Color(0.9, 0.85, 0.5),
	}))
	_add(_make(&"totem_mend", "Totem of Mending", AbilityData.Shape.SELF, {
		"damage": 0, "heal": 6, "knockback": 0.0, "magic_cost": 40.0, "cooldown": 8.0,
		"wind_up": 0.5, "radius": 8.0, "animation": "ranged/Ranged_Magic_Summon",
		"vfx_color": Color(0.4, 1.0, 0.5),
	}))
	_add(_make(&"power_shot", "Power Shot", AbilityData.Shape.PROJECTILE, {
		"damage": 6, "knockback": 16.0, "range": 32.0, "magic_cost": 30.0, "cooldown": 4.0,
		"wind_up": 0.45, "projectile_speed": 46.0, "animation": "ranged/Ranged_Bow_Release",
		"vfx_color": Color(1.0, 0.7, 0.3),
	}))
	_add(_make(&"fireball", "Fireball", AbilityData.Shape.PROJECTILE, {
		"damage": 5, "knockback": 14.0, "knockback_lift": 0.45, "range": 24.0,
		"radius": 3.5, "magic_cost": 35.0, "cooldown": 3.5, "wind_up": 0.5,
		"projectile_speed": 18.0, "animation": "ranged/Ranged_Magic_Spellcasting",
		"vfx_color": Color(1.0, 0.45, 0.15),
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

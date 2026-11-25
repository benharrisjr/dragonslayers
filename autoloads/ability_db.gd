extends Node

## Every ability in the game, built in code rather than as .tres files.
##
## Constructing them here keeps the whole balance table readable in one diff and removes a
## class of bug that hand-written .tres invites -- a mistyped property name in a resource file
## fails silently, a mistyped one here fails at parse time. They are still real AbilityData
## resources, so nothing stops a .tres being dropped in later for editor tweaking.

var _abilities: Dictionary = {}


func _ready() -> void:
	# --- each hero's weapon attack: free, so nobody is ever helpless ---
	## Every attack deals one point -- half a heart. The heroes differ in reach, speed and shove.
	## Knight. Wide and quick; the shield is the knight's other half.
	_add(_make(&"sword_swing", "Sword Swing", AbilityData.Shape.MELEE_ARC, {
		"damage": 1, "knockback": 7.0, "range": 3.8, "arc_degrees": 80.0, "cooldown": 0.55,
		"wind_up": 0.16, "animation": "melee/Melee_1H_Attack_Slice_Horizontal",
		## The clip's blade sweeps through at 0.30 s; played at 1.9x that is the wind-up.
		"animation_speed": 1.9,
	}))

	## Barbarian. Slower than the sword and narrower, but throws whatever it hits much further.
	_add(_make(&"axe_cleave", "Axe Cleave", AbilityData.Shape.MELEE_ARC, {
		"damage": 1, "knockback": 12.0, "knockback_lift": 0.45, "range": 3.9, "arc_degrees": 70.0,
		"cooldown": 0.95, "wind_up": 0.38, "animation": "melee/Melee_2H_Attack_Chop",
		## The axe comes down at 0.83 s into the clip; played at 2.2x it lands on the wind-up,
		## with the slash.
		"animation_speed": 2.2,
	}))
	## Thief. Short reach and a narrow point, but fast enough to land three for the sword's two.
	_add(_make(&"dagger_stab", "Dagger Stab", AbilityData.Shape.MELEE_ARC, {
		"damage": 1, "knockback": 4.0, "range": 3.0, "arc_degrees": 40.0, "cooldown": 0.34,
		"wind_up": 0.12, "animation": "melee/Melee_1H_Attack_Stab", "animation_speed": 1.7,
	}))
	## Mage. A bolt of magic: the range to stay out of reach, for less damage per hit.
	_add(_make(&"magic_bolt", "Magic Bolt", AbilityData.Shape.PROJECTILE, {
		"damage": 1, "knockback": 6.0, "range": 22.0, "cooldown": 0.6, "wind_up": 0.28,
		"projectile_speed": 24.0, "animation": "ranged/Ranged_Magic_Shoot",
		"vfx_color": Color(0.55, 0.6, 1.0),
	}))
	## Archer. Longer and faster than the bolt, with a longer draw before it flies.
	_add(_make(&"bow_shot", "Arrow", AbilityData.Shape.PROJECTILE, {
		"damage": 1, "knockback": 5.0, "range": 28.0, "cooldown": 0.55, "wind_up": 0.34,
		"projectile_speed": 36.0, "animation": "ranged/Ranged_Bow_Release",
		"vfx_color": Color(0.85, 0.75, 0.55),
	}))

	# --- charged attacks: hold the attack button, let go ---
	## Still one point a hit, like everything else: what charging buys is hitting everything
	## round you at once, and shoving it harder.
	## Knight. A full turn with the sword.
	_add(_make(&"sword_spin", "Spin Attack", AbilityData.Shape.MELEE_ARC, {
		"damage": 1, "knockback": 13.0, "knockback_lift": 0.4, "range": 4.2, "arc_degrees": 180.0,
		"cooldown": 0.4, "wind_up": 0.18, "animation": "melee/Melee_2H_Attack_Spin",
		"animation_speed": 1.4,
	}))
	## Barbarian. A wider, heavier turn with the axe.
	_add(_make(&"axe_spin", "Whirlwind", AbilityData.Shape.MELEE_ARC, {
		"damage": 1, "knockback": 18.0, "knockback_lift": 0.5, "range": 5.0, "arc_degrees": 180.0,
		"cooldown": 0.5, "wind_up": 0.22, "animation": "melee/Melee_2H_Attack_Spin",
		"animation_speed": 1.2,
	}))
	## Thief. Knives flung out all round.
	_add(_make(&"knife_flurry", "Knife Flurry", AbilityData.Shape.PROJECTILE, {
		"damage": 1, "knockback": 6.0, "range": 12.0, "cooldown": 0.4, "wind_up": 0.15,
		"projectile_speed": 26.0, "projectile_count": 10, "animation": "general/Throw",
		"animation_speed": 1.6, "vfx_color": Color(0.85, 0.88, 0.95),
	}))
	## Archer. A quick draw, then a full turn on the spot loosing arrows one after another, each
	## along where the archer faces as they come round. The draw is held while charging (see
	## PlayerCharacter._update_animation); the spin is PlayerCharacter._spin_volley.
	_add(_make(&"arrow_flurry", "Arrow Storm", AbilityData.Shape.PROJECTILE, {
		"damage": 1, "knockback": 7.0, "range": 18.0, "cooldown": 0.45, "wind_up": 0.12,
		"projectile_speed": 32.0, "projectile_count": 12, "projectile_interval": 0.05,
		"animation": "ranged/Ranged_Bow_Draw", "animation_speed": 3.0,
		"vfx_color": Color(0.85, 0.75, 0.55),
	}))
	## Mage. A ring of magic that bursts out from the mage and throws back what it catches.
	_add(_make(&"magic_ring", "Arcane Ring", AbilityData.Shape.NOVA, {
		"damage": 1, "knockback": 15.0, "knockback_lift": 0.5, "radius": 6.5, "cooldown": 0.5,
		"wind_up": 0.25, "animation": "ranged/Ranged_Magic_Summon", "animation_speed": 1.4,
		"vfx_color": Color(0.6, 0.45, 1.0),
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

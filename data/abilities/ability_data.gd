class_name AbilityData
extends Resource

## One attack or spell. Basic weapon swings are abilities too, just free ones, so that every
## source of damage in the game passes through the same resolve path in CombatResolver and
## nothing can deal damage without also declaring its knockback.

enum Shape {
	MELEE_ARC,   ## Cone in front of the caster; the bread-and-butter weapon swing.
	PROJECTILE,  ## Spawns a travelling body that resolves on contact.
	SELF,        ## No hit test -- heals, buffs, shields.
	NOVA,        ## Radial burst centred on the caster; used by the dragon's wing flap.
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var shape: Shape = Shape.MELEE_ARC

@export_group("Cost")
## Magic is 0-100. A basic weapon attack costs nothing, which is what makes it the fallback
## when a player is drained.
@export var magic_cost: float = 0.0
@export var cooldown: float = 0.6
## Delay between starting the animation and the hit landing, so the swing connects on the
## frame it visually should rather than the frame the button was pressed.
@export var wind_up: float = 0.25

@export_group("Reach")
@export var range: float = 2.6
## Half-angle in degrees for MELEE_ARC, ignored otherwise.
@export var arc_degrees: float = 60.0
@export var radius: float = 3.0
@export var projectile_speed: float = 22.0

@export_group("Effect")
@export var damage: int = 1
@export var heal: int = 0
## Metres per second imparted along the hit direction. Knockback is a core mechanic here --
## ledges are everywhere -- so this is a first-class field, never an afterthought.
@export var knockback: float = 6.0
## Fraction of the knockback applied upwards. A little loft makes a shove read as a hit; too
## much turns every skirmish into juggling.
@export var knockback_lift: float = 0.35

@export_group("Presentation")
@export var animation: String = "melee/Melee_1H_Attack_Chop"
@export var animation_speed: float = 1.4
@export var vfx_color: Color = Color(1, 1, 1)


func can_afford(magic: float) -> bool:
	return magic >= magic_cost

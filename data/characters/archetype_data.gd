class_name ArchetypeData
extends Resource

## A playable class: which KayKit model to wear, what it holds, how it moves, and what it can
## cast. The four archetypes differ only in this data, so the player controller never branches
## on class.

@export var id: StringName = &""
@export var display_name: String = ""
@export var color: Color = Color.WHITE

@export_group("Model")
## All four adventurers skin to the same 23-joint Rig_Medium skeleton and ship with zero baked
## animations, so the model is only a mesh and every clip comes from RigAnimations.
@export var model_path: String = ""
## Weapon model -> bone it hangs off. The rig exposes handslot.l and handslot.r for exactly this.
@export var weapon_paths: Dictionary = {}

@export_group("Stats")
@export var max_hearts: int = 3
@export var max_magic: float = 100.0
@export var move_speed: float = 7.0
@export var jump_velocity: float = 10.5
## Multiplier on incoming knockback. The Knight is heavy and hard to shove off a ledge; the
## Wizard is not.
@export var knockback_resistance: float = 1.0

@export_group("Combat")
@export var basic_attack: AbilityData
@export var abilities: Array[AbilityData] = []

@export_group("Animation")
@export var idle_anim: String = "general/Idle_A"
@export var run_anim: String = "move/Running_A"
@export var jump_anim: String = "move/Jump_Idle"
@export var land_anim: String = "move/Jump_Land"
@export var hit_anim: String = "general/Hit_A"
@export var death_anim: String = "general/Death_A"

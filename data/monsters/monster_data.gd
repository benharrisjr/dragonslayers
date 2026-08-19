class_name MonsterData
extends Resource

## One kind of enemy. Rare monsters drop an ability instead of gold, which is the main reason
## the flag lives here rather than being decided at spawn time.

@export var id: StringName = &""
@export var display_name: String = ""
@export var model_path: String = ""
@export var scale: float = 1.0

@export_group("Stats")
@export var max_health: int = 6
@export var move_speed: float = 3.4
## How far it will notice a player. Kept generous: a monster that ignores you is not a threat,
## and the whole point of these encounters is being shoved towards a cliff.
@export var aggro_range: float = 14.0
@export var leash_range: float = 26.0
@export var knockback_resistance: float = 1.0

@export_group("Attack")
@export var damage: int = 1
@export var knockback: float = 9.0
@export var knockback_lift: float = 0.4
@export var attack_range: float = 2.2
@export var attack_cooldown: float = 1.9
@export var wind_up: float = 0.45

@export_group("Reward")
@export var gold: int = 5
@export var is_rare: bool = false

@export_group("Animation")
@export var idle_anim: String = "special/Skeletons_Idle"
@export var walk_anim: String = "special/Skeletons_Walking"
@export var attack_anim: String = "melee/Melee_1H_Attack_Chop"
@export var hit_anim: String = "general/Hit_A"
@export var death_anim: String = "special/Skeletons_Death"
@export var spawn_anim: String = "special/Skeletons_Awaken_Standing"

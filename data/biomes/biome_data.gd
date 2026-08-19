class_name BiomeData
extends Resource

## Everything that makes one of the 16 map chunks look and feel distinct: how bumpy its
## terrain is, what colour it is, what grows on it and what lives on it.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Terrain")
@export var ground_color: Color = Color(0.35, 0.6, 0.25)
@export var cliff_color: Color = Color(0.42, 0.34, 0.24)
## Number of distinct plateau levels above the base. Links-Awakening terrain reads as a few
## crisp steps rather than a smooth slope, so this stays small.
@export var height_levels: int = 3
## 0 = billiard table, 1 = every tile a different height. Above ~0.5 the plateaus stop reading
## as places you can stand and fight.
@export var roughness: float = 0.35
## Chance a tile at the lowest level is a hole instead -- the ledges players get knocked off.
@export var pit_chance: float = 0.0
@export var water_level: int = -1

@export_group("Props")
## Each entry: {"path": String, "weight": float, "scale": Vector2(min, max), "radius": float}
@export var props: Array[Dictionary] = []
@export var prop_density: float = 0.05

@export_group("Contents")
@export var monster_ids: Array[StringName] = []
@export var monster_count: int = 6
@export var chest_count: int = 1

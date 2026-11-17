class_name BiomeData
extends Resource

## Everything that makes one of the 16 map chunks look and feel distinct: how bumpy its
## terrain is, what colour it is, what grows on it and what lives on it.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Terrain")
@export var ground_color: Color = Color(0.35, 0.6, 0.25)
@export var cliff_color: Color = Color(0.42, 0.34, 0.24)
## Colour of ground below the chunk's own level: wet sand and sea bed on the beach.
@export var low_color: Color = Color(0.35, 0.6, 0.25)
## How many levels the mesas rise above the chunk's ground: 0 for flat, at most 2. Mesas are
## optional high ground -- without the feather nobody can step up onto one.
@export var height_levels: int = 1
## How much of the chunk is mesa. The terrain noise runs 0..1 and ground above this value is
## raised, so 1.0 is a billiard table and 0.6 is roughly a third of the chunk.
@export var mesa_threshold: float = 0.7
## Bottomless pits in this chunk. A handful of deliberate hazards, not a texture.
@export var pit_count: int = 0
@export var water_level: int = -1

@export_group("Props")
## Each entry: {"path": String, "weight": float, "scale": Vector2(min, max), "radius": float}
@export var props: Array[Dictionary] = []
@export var prop_density: float = 0.05

@export_group("Contents")
@export var monster_ids: Array[StringName] = []
@export var monster_count: int = 6
@export var chest_count: int = 1

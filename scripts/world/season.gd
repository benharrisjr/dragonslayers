class_name Season
extends RefCounted

## The time of year a match is played in, rolled from the world seed.
##
## Rolled from the seed rather than at random so every machine in an online game gets the same
## one without it being sent anywhere. What it changes:
##
##   Spring  bright green ground, flower beds
##   Summer  duller green ground, patches of long grass that bends as things walk through it and
##           is cut down by swings and fire (GrassField)
##   Fall    orange ground, autumn trees
##   Winter  snow, which keeps the tracks of everything that walks through it (SnowTrails)
##
## Only grassland changes colour: the beach stays sand and the mountain stays rock in every
## season, and the desert and the temple ruins keep their own ground until it snows.

enum Kind { SPRING, SUMMER, FALL, WINTER }

const NAMES: Array[String] = ["Spring", "Summer", "Fall", "Winter"]

## Grassland: takes the season's colour, and its flowers or long grass.
const GRASSLAND: Array[StringName] = [&"town", &"plains", &"fields", &"forest", &"lake"]
## Bare ground that only changes when it snows.
const SNOW_ONLY: Array[StringName] = [&"desert", &"temple"]

## The colour grassland leans towards each season, and how far. Leaning rather than replacing
## keeps the biomes apart: a forest is still darker than the plains around it.
const GROUND: Array[Color] = [
	Color(0.4, 0.7, 0.26),  ## spring: bright, fresh green
	Color(0.44, 0.53, 0.25),  ## summer: dull, dry green
	Color(0.84, 0.4, 0.12),  ## fall: orange
	## Winter: snow. Not pure white -- under the sun and the colour grade that blows out to a
	## flat sheet with no shading at all, and the tracks need something to be darker than.
	Color(0.7, 0.74, 0.81),
]
const LEAN: Array[float] = [0.6, 0.7, 0.82, 0.92]
## A cliff in winter catches a little snow on its face; otherwise it is the biome's own rock.
const WINTER_CLIFF_FROST := 0.28

## Trees that change with the season, by file name: [fall model, winter model], each with a
## scale multiplier so the swap stands as tall as what it replaced -- measured from the models'
## own bounds (survival trees 1.41 and 1.71 units tall, the platformer kit's snowy trees 1.93
## and 2.0, the town's tree 2.41).
const _SURVIVAL := "res://art/kenney_survival-kit/Models/GLB format/"
const _PLATFORMER := "res://art/kenney_platformer-kit-2/Models/GLB format/"
const TREE_SWAPS: Dictionary = {
	"tree.glb": [[_SURVIVAL + "tree-autumn.glb", 1.0], [_PLATFORMER + "tree-snow.glb", 0.73]],
	"tree-tall.glb": [[_SURVIVAL + "tree-autumn-tall.glb", 1.0],
			[_PLATFORMER + "tree-pine-snow.glb", 0.85]],
	"tree-autumn.glb": [[_SURVIVAL + "tree-autumn.glb", 1.0],
			[_PLATFORMER + "tree-snow.glb", 0.73]],
	"tree-autumn-tall.glb": [[_SURVIVAL + "tree-autumn-tall.glb", 1.0],
			[_PLATFORMER + "tree-pine-snow.glb", 0.85]],
}

## The town's trees come from another kit, at another size.
const _TOWN := "res://art/kenney_fantasy-town-kit_2/Models/GLB format/"
const TOWN_SWAPS: Dictionary = {
	"tree.glb": [[_SURVIVAL + "tree-autumn.glb", 1.71], [_PLATFORMER + "tree-snow.glb", 1.25]],
}

## The season of the match being played. Set by GameWorld.build from the seed.
static var current: Kind = Kind.SPRING
## `--season=winter` on the command line: every match is that season. -1 for none.
static var forced: int = -1


## The season a seed gives. Uses its own generator, so it takes nothing from the sequence the
## terrain and the props are drawn from.
static func roll(world_seed: int) -> Kind:
	if forced >= 0:
		return forced as Kind
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ 0x5EA50
	return rng.randi_range(0, NAMES.size() - 1) as Kind


static func from_name(text: String) -> int:
	return NAMES.find(text.capitalize())


static func display_name(kind: Kind = current) -> String:
	return NAMES[kind]


static func is_grassland(biome_id: StringName) -> bool:
	return GRASSLAND.has(biome_id)


## Whether a biome's ground is under snow this winter.
static func snows_on(biome_id: StringName, kind: Kind = current) -> bool:
	return kind == Kind.WINTER and (GRASSLAND.has(biome_id) or SNOW_ONLY.has(biome_id))


## The colour of a biome's ground (or of `base`, one of its ground colours) this season.
static func ground_color(biome_id: StringName, base: Color, kind: Kind = current) -> Color:
	if GRASSLAND.has(biome_id) or snows_on(biome_id, kind):
		return base.lerp(GROUND[kind], LEAN[kind])
	return base


static func cliff_color(biome_id: StringName, base: Color, kind: Kind = current) -> Color:
	if snows_on(biome_id, kind):
		return base.lerp(GROUND[Kind.WINTER], WINTER_CLIFF_FROST)
	return base


## The model to stand in a prop's place this season, and how much to scale it by. Anything
## without a seasonal look comes back unchanged.
static func prop_swap(path: String, kind: Kind = current) -> Array:
	var file := path.get_file()
	var table: Dictionary = {}
	if path.begins_with(_SURVIVAL):
		table = TREE_SWAPS
	elif path.begins_with(_TOWN):
		table = TOWN_SWAPS
	if not table.has(file):
		return [path, 1.0]
	match kind:
		Kind.FALL:
			return table[file][0]
		Kind.WINTER:
			return table[file][1]
	return [path, 1.0]

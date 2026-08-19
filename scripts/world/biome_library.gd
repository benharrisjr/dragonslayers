class_name BiomeLibrary
extends RefCounted

## The eight terrain types the 16 chunks are drawn from.
##
## Terrain colour lives here rather than in the Kenney block meshes because those only ship in
## grass and snow, and every one of them samples a single shared `colormap` atlas -- eight
## biomes would need eight repainted atlases. Generating the ground as vertex-coloured geometry
## gives any palette for free; the kits are still used for everything standing on top of it.

const PROP_ROOT := "res://art/"

static var _biomes: Dictionary = {}


static func get_biome(id: StringName) -> BiomeData:
	if _biomes.is_empty():
		_build()
	return _biomes.get(id)


static func all_ids() -> Array:
	if _biomes.is_empty():
		_build()
	return _biomes.keys()


static func _build() -> void:
	_add(&"town", "Town", Color(0.46, 0.55, 0.34), Color(0.55, 0.5, 0.42), {
		"height_levels": 1, "roughness": 0.12, "prop_density": 0.055,
		"monster_ids": [], "monster_count": 0, "chest_count": 1,
		"props": [
			_prop("kenney_fantasy-town-kit_2", "watermill", 0.6, 1.6, 2.4),
			_prop("kenney_fantasy-town-kit_2", "windmill", 0.5, 1.6, 2.4),
			_prop("kenney_fantasy-town-kit_2", "stall-red", 1.3, 1.5, 1.4),
			_prop("kenney_fantasy-town-kit_2", "stall-green", 1.3, 1.5, 1.4),
			_prop("kenney_fantasy-town-kit_2", "cart", 1.0, 1.5, 1.2),
			_prop("kenney_castle-kit", "tower-square", 0.5, 1.5, 2.0),
			_prop("kenney_fantasy-town-kit_2", "tree", 1.4, 1.4, 1.2),
			_prop("kenney_fantasy-town-kit_2", "fountain-round", 0.4, 1.6, 2.0),
			_prop("kenney_fantasy-town-kit_2", "lantern", 1.0, 1.5, 0.4),
		],
	})
	_add(&"plains", "Plains", Color(0.42, 0.66, 0.28), Color(0.5, 0.42, 0.3), {
		"height_levels": 3, "roughness": 0.34, "pit_chance": 0.05, "prop_density": 0.035,
		"monster_ids": [&"skeleton_minion", &"skeleton_rogue"], "monster_count": 7,
		"chest_count": 1,
		"props": [
			_prop("kenney_survival-kit", "tree", 1.6, 2.4, 1.1),
			_prop("kenney_survival-kit", "rock-a", 1.2, 2.2, 0.9),
			_prop("kenney_survival-kit", "rock-b", 1.0, 2.2, 0.9),
			_prop("kenney_survival-kit", "grass-large", 2.0, 2.0, 0.0),
		],
	})
	_add(&"fields", "Fields", Color(0.62, 0.68, 0.26), Color(0.52, 0.44, 0.3), {
		"height_levels": 2, "roughness": 0.22, "pit_chance": 0.02, "prop_density": 0.045,
		"monster_ids": [&"skeleton_minion"], "monster_count": 5, "chest_count": 1,
		"props": [
			_prop("kenney_survival-kit", "patch-grass-large", 2.4, 2.2, 0.0),
			_prop("kenney_fantasy-town-kit_2", "fence", 1.2, 1.5, 0.5),
			_prop("kenney_survival-kit", "tree-autumn", 1.0, 2.2, 1.1),
			_prop("kenney_survival-kit", "resource-wood", 0.8, 2.0, 0.6),
		],
	})
	_add(&"forest", "Forest", Color(0.24, 0.48, 0.24), Color(0.38, 0.32, 0.24), {
		"height_levels": 3, "roughness": 0.4, "pit_chance": 0.05, "prop_density": 0.13,
		"monster_ids": [&"skeleton_rogue", &"skeleton_minion"], "monster_count": 9,
		"chest_count": 2,
		"props": [
			_prop("kenney_survival-kit", "tree-tall", 3.0, 2.6, 1.2),
			_prop("kenney_survival-kit", "tree", 2.6, 2.4, 1.1),
			_prop("kenney_survival-kit", "tree-autumn-tall", 1.4, 2.4, 1.2),
			_prop("kenney_survival-kit", "tree-log", 0.8, 2.2, 0.9),
			_prop("kenney_survival-kit", "rock-c", 0.8, 2.2, 0.9),
		],
	})
	_add(&"desert", "Desert", Color(0.82, 0.72, 0.42), Color(0.7, 0.56, 0.34), {
		"height_levels": 3, "roughness": 0.3, "pit_chance": 0.09, "prop_density": 0.03,
		"monster_ids": [&"skeleton_warrior", &"skeleton_minion"], "monster_count": 8,
		"chest_count": 2,
		"props": [
			_prop("kenney_survival-kit", "rock-sand-a", 1.6, 2.4, 1.0),
			_prop("kenney_survival-kit", "rock-sand-b", 1.4, 2.4, 1.0),
			_prop("kenney_survival-kit", "rock-sand-c", 1.2, 2.4, 1.0),
			_prop("kenney_graveyard-kit_5", "pillar-obelisk", 0.7, 1.6, 0.8),
		],
	})
	_add(&"lake", "Lake", Color(0.46, 0.62, 0.36), Color(0.44, 0.4, 0.34), {
		"height_levels": 2, "roughness": 0.25, "water_level": 0, "prop_density": 0.05,
		"monster_ids": [&"skeleton_minion"], "monster_count": 5, "chest_count": 1,
		"props": [
			_prop("kenney_survival-kit", "tree", 1.4, 2.3, 1.1),
			_prop("kenney_survival-kit", "rock-flat-grass", 1.6, 2.4, 0.9),
			_prop("kenney_watercraft-pack", "boat-row-small", 0.5, 1.4, 1.2),
		],
	})
	_add(&"temple", "Temple", Color(0.55, 0.53, 0.48), Color(0.48, 0.46, 0.44), {
		"height_levels": 3, "roughness": 0.2, "pit_chance": 0.11, "prop_density": 0.07,
		"monster_ids": [&"skeleton_warrior", &"skeleton_mage", &"skeleton_rogue"],
		"monster_count": 9, "chest_count": 2,
		"props": [
			_prop("kenney_graveyard-kit_5", "pillar-large", 1.8, 1.7, 0.9),
			_prop("kenney_graveyard-kit_5", "pillar-small", 1.2, 1.7, 0.8),
			_prop("kenney_castle-kit", "wall", 1.0, 1.6, 1.0),
			_prop("kenney_graveyard-kit_5", "gravestone-cross", 1.0, 1.6, 0.5),
			_prop("kenney_graveyard-kit_5", "urn-round", 0.8, 1.6, 0.5),
		],
	})
	## The mountain is a cone rather than a plateau field, and it is where the dragon waits.
	_add(&"mountain", "Mountain", Color(0.52, 0.5, 0.46), Color(0.4, 0.38, 0.36), {
		"height_levels": 9, "roughness": 0.5, "pit_chance": 0.0, "prop_density": 0.03,
		"monster_ids": [&"skeleton_warrior"], "monster_count": 6, "chest_count": 1,
		"props": [
			_prop("kenney_platformer-kit-2", "tree-pine-snow", 1.2, 1.4, 1.0),
			_prop("kenney_survival-kit", "rock-c", 2.0, 2.6, 1.0),
			_prop("kenney_survival-kit", "rock-b", 1.6, 2.6, 1.0),
		],
	})


static func _add(id: StringName, name: String, ground: Color, cliff: Color,
		fields: Dictionary) -> void:
	var biome := BiomeData.new()
	biome.id = id
	biome.display_name = name
	biome.ground_color = ground
	biome.cliff_color = cliff
	## The two typed-Array properties are copied element by element. Object.set() will not
	## coerce an untyped Array into an Array[StringName] or Array[Dictionary] -- it drops the
	## value and reports nothing, which silently emptied every biome of props and monsters.
	if fields.has("monster_ids"):
		var monsters: Array[StringName] = []
		for monster_id: StringName in fields["monster_ids"]:
			monsters.append(monster_id)
		biome.monster_ids = monsters
	if fields.has("props"):
		var props: Array[Dictionary] = []
		for prop: Dictionary in fields["props"]:
			props.append(prop)
		biome.props = props
	for key: String in fields:
		if key == "monster_ids" or key == "props":
			continue
		biome.set(key, fields[key])
	_biomes[id] = biome


## Kenney kits are authored on a ~1 unit grid while this world runs at 1 unit = 1 metre, so
## props carry their own scale multiplier rather than being uniformly fudged.
static func _prop(kit: String, model: String, weight: float, scale: float,
		radius: float) -> Dictionary:
	return {
		"path": "%s%s/Models/GLB format/%s.glb" % [PROP_ROOT, kit, model],
		"weight": weight,
		"scale": scale,
		"radius": radius,
	}

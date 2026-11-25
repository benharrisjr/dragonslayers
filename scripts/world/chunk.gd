class_name Chunk
extends LootArea

## One of the 16 map tiles: its terrain, its scenery, its monsters and its chests.
##
## Every peer builds this from the same seed, and every node inside it is named deterministically
## (Monster_3_02, Chest_3_00). That is what lets the game skip a MultiplayerSpawner entirely --
## identical node paths on every machine mean RPCs address the same object everywhere, and the
## only thing crossing the wire is the seed.

const PROP_CLEARANCE_TILES := 2
## How much of a prop's visual radius is solid.
const COLLIDER_FRACTION := 0.45
## How far a prop's collider continues underground.
const COLLIDER_ROOT := 6.0
## Placement attempts per tile per unit of a biome's prop_density. Cut to roughly a third of
## what it was: the world read as littered, and open ground is what makes the ramps, mesas and
## shoreline legible from a distance.
const PROP_ATTEMPTS := 0.7
## Tiles round a spawn point kept clear of the river.
const SPAWN_DRY := 4

var index: int = 0
var biome: BiomeData
## The chunk's ground. `heights` is its level array, kept as a shortcut for the many callers
## that only want to know how high a tile is.
var terrain: TerrainData
var heights: PackedInt32Array

## A liftable prop has been taken out of the ground (on every peer, as part of the lift).
signal prop_lifted(index: int)

var monsters: Array[Monster] = []
var chests: Array[TreasureChest] = []

var _rng: RandomNumberGenerator
var _occupied: Dictionary = {}
## Every prop placed, in placement order -- the same order on every peer, so a prop's index
## names it across the network. Each: {"node", "body", "burnable", "burnt", "liftable", "taken",
## "radius"}.
var _props: Array[Dictionary] = []

## The bugs flying about this chunk, if it has any.
var bugs: BugSwarm
## The town's shop; null everywhere else.
var shop: Shop
## The way into a dungeon, in the chunks that have one.
var entrance: DungeonEntrance
## The ledged cliff tops, as ChunkMesher.build lists them.
var ledges: Array = []
## On the mountain: each dungeon's shrine, bottom terrace first (MountainShrine).
var shrines: Array[MountainShrine] = []
## Summer's long grass or spring's flowers, on grassland; null otherwise.
var ground_cover: GrassField
## The fall's leaf piles and litter, on grassland; null otherwise.
var leaves: LeafField

## Scenery a lantern's fire burns away, matched on the start of the model's file name.
const FLAMMABLE: Array[String] = [
	"tree", "grass", "patch-grass", "resource-wood", "fence", "tent", "barrel", "stall",
	"cart", "boat",
]


## `ctx` is WorldGenerator.context() for this cell: its ground level and its neighbours'.
func build(chunk_index: int, biome_id: StringName, rng: RandomNumberGenerator,
		ctx: Dictionary = {}) -> void:
	index = chunk_index
	biome = BiomeLibrary.get_biome(biome_id)
	_rng = rng
	name = "Chunk_%02d_%s" % [index, biome_id]
	add_to_group("chunks")
	position = WorldGenerator.chunk_origin(index)

	## Worked out already where the whole map is being built, so the paths could be laid over it.
	terrain = ctx["terrain"] if ctx.has("terrain") else WorldGenerator.heightmap(biome, _rng, ctx)
	heights = terrain.heights
	_build_terrain()
	RiverBuilder.build(self)
	if biome.id == &"beach":
		_build_sea()
	elif biome.water_level >= 0:
		_build_lake()
	_place_torches(ctx.get("torches", []))
	_scatter_props()
	_spawn_monsters()
	_spawn_chests()
	## Last, so that adding them moved nothing that was already being placed from the seed.
	if biome.id == &"town":
		_spawn_shop()
	_spawn_bugs()
	_place_crates()
	## A dungeon's way in, if this chunk holds one. Its own generator, and nearly last, so it moves
	## nothing that was already placed -- it clears the scenery under it instead.
	var entrance_id: StringName = ctx.get("entrance", &"")
	if entrance_id != &"":
		entrance = DungeonEntrance.place(self, entrance_id)
	if biome.id == &"mountain":
		_place_shrines(int(ctx.get("ascent_side", -1)))
	_grow_ground_cover()


## Lanes either side of the middle of the ascent face to try for each shrine, nearest first:
## just clear of the road, which zigzags over the middle seven.
const SHRINE_LANE := 6
const SHRINE_SEARCH := 14
## Shrines are built at a person's scale; this makes them read against the 6 m terrace walls.
const SHRINE_SCALE := 1.4


## One shrine per dungeon up the mountain, a terrace each, bottom to top in Dungeon.IDS order. Each
## stands on its terrace's inner row against the wall up to the next, on the face the road climbs
## and just to one side of it, so climbing the road passes them in order. Placed after everything
## else and clearing the scenery under it, so it moves nothing placed from the seed.
func _place_shrines(side: int) -> void:
	if side < 0:
		side = 1
	var size := terrain.size
	var middle := size / 2
	var outward := Vector2(ChunkMesher.NEIGHBOUR_DX[side], ChunkMesher.NEIGHBOUR_DZ[side])
	var root := Node3D.new()
	root.name = "Shrines"
	add_child(root)
	var count := mini(WorldGenerator.TERRACES, Dungeon.IDS.size())
	for terrace in count:
		var level := terrain.base_level + (terrace + 1) * WorldGenerator.TERRACE_RISE
		var spot := _shrine_tile(side, middle, level)
		if spot.x < 0:
			push_warning("No room for the %s shrine on terrace %d" % [Dungeon.IDS[terrace], terrace + 1])
			continue
		clear_props_within(spot, 0)
		_mark_occupied(spot.x, spot.y, 1)
		var shrine := MountainShrine.new()
		shrine.setup(Dungeon.IDS[terrace])
		root.add_child(shrine)
		## Back against the wall, facing out over the drop.
		shrine.position = _tile_centre(spot.x, spot.y) - Vector3(outward.x, 0.0, outward.y) * 0.25
		shrine.rotation.y = atan2(outward.x, outward.y)
		shrine.scale = Vector3.ONE * SHRINE_SCALE
		shrines.append(shrine)


## The tile for a shrine on the terrace at `level`: in its inner row (the wall up to the next
## terrace right behind it), dry, flat and not part of a ramp. Lanes nearest the road first.
## (-1, -1) if there is none.
func _shrine_tile(side: int, middle: int, level: int) -> Vector2i:
	var size := terrain.size
	for offset in range(SHRINE_LANE, SHRINE_SEARCH + 1):
		for sign: int in [1, -1]:
			var lane := middle + offset * sign
			for depth in range(WorldGenerator.BORDER, size / 2):
				var here := WorldGenerator._from_side(size, side, depth, lane)
				var inner := WorldGenerator._from_side(size, side, depth + 1, lane)
				if terrain.level(inner.x, inner.y) <= level:
					continue
				if terrain.level(here.x, here.y) != level:
					break
				var at := here.y * size + here.x
				if terrain.slopes[at] == TerrainData.Slope.FLAT and terrain.reserved[at] == 0 \
						and _dry_around(here.x, here.y, 1) and not is_arena_tile(here.x, here.y):
					return here
				break
	return Vector2i(-1, -1)


## Spring's flowers, summer's long grass or the fall's leaves, from a generator of their own so the season changes
## nothing else about where things are.
func _grow_ground_cover() -> void:
	if not Season.is_grassland(biome.id):
		return
	var kind := Season.current
	if kind == Season.Kind.FALL:
		leaves = LeafField.new()
		add_child(leaves)
		leaves.grow(self, GameState.chunk_rng(index + 7000))
		return
	if kind != Season.Kind.SPRING and kind != Season.Kind.SUMMER:
		return
	ground_cover = GrassField.new()
	add_child(ground_cover)
	var rng := GameState.chunk_rng(index + 7000)
	if kind == Season.Kind.SUMMER:
		ground_cover.grow_grass(self, rng)
	else:
		ground_cover.grow_flowers(self, rng)


## Whether there is no river within `reach` tiles of a tile. The players are spread round the
## spawn tile, not stood on it, and a spawn beside the river put some of them straight in it.
func _dry_around(x: int, z: int, reach: int) -> bool:
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if terrain.in_bounds(x + dx, z + dz) and terrain.is_water(x + dx, z + dz):
				return false
	return true


## Shows or hides everything in the chunk but its skeletons, which can walk out of it. Drawing
## only: nothing stops running.
func set_drawn(on: bool) -> void:
	for child in get_children():
		if child is Node3D and child.name != "Monsters":
			(child as Node3D).visible = on


## The river under a world position, if there is any: {"surface" (the water's height), "bank" (the
## height of its banks, which is where a raft rides), "flow" (Vector3, the way it runs)}. Empty
## where there is no river.
func river_at(at: Vector3) -> Dictionary:
	var local := at - global_position
	var x := int(floor(local.x / ChunkMesher.TILE_SIZE))
	var z := int(floor(local.z / ChunkMesher.TILE_SIZE))
	if not terrain.is_water(x, z):
		return {}
	var flow := terrain.flow[z * terrain.size + x]
	return {
		"surface": terrain.water_surface(x, z),
		## Where a raft rides: level with the banks, or as much lower as the river is cut deep.
		"bank": (terrain.level(x, z) + 1) * ChunkMesher.STEP_HEIGHT - terrain.sink_at(x, z),
		"flow": Vector3(flow.x, 0.0, flow.y),
		## On the bridge, not under it: a land bridge stands well over the water, as a plank one
		## does where the river is cut deep, and someone rafting beneath it is still on the river.
		"bridge": terrain.is_bridge(x, z)
				and ((terrain.bridge_lift(x, z) <= 1 and terrain.sink_at(x, z) <= 0.0)
				or at.y > global_position.y + (terrain.level(x, z) + terrain.bridge_lift(x, z)) \
				* ChunkMesher.STEP_HEIGHT - 0.8),
	}


## The river anywhere in the world; see river_at.
static func river_under(tree: SceneTree, at: Vector3) -> Dictionary:
	var chunk := containing(tree, at)
	return chunk.river_at(at) if chunk != null else {}


## Water too deep to stand in under a world position: the river (see river_at), or the deep
## middle of the lake or the sea past its shallows. Still water answers like the river does,
## with "still": true, no flow, and "bank" at its surface -- nothing rafts on it, and a body that
## has sunk half a metre into it has gone in. Empty over dry ground and the shallows.
func water_at(at: Vector3) -> Dictionary:
	var river := river_at(at)
	if not river.is_empty():
		return river
	var local := at - global_position
	var x := int(floor(local.x / ChunkMesher.TILE_SIZE))
	var z := int(floor(local.z / ChunkMesher.TILE_SIZE))
	if not terrain.is_deep(x, z):
		return {}
	return {
		"surface": terrain.still_surface,
		"bank": terrain.still_surface,
		"flow": Vector3.ZERO,
		"bridge": false,
		"still": true,
	}


## Deep water anywhere in the world; see water_at.
static func water_under(tree: SceneTree, at: Vector3) -> Dictionary:
	var chunk := containing(tree, at)
	return chunk.water_at(at) if chunk != null else {}


## Whether a world position is somewhere to put a player back after a fall: no pit, river or
## deep water on its tile or the eight round it, so a respawn there does not land on the lip
## they just went over. Off the map counts as unsafe.
static func is_safe_footing(tree: SceneTree, at: Vector3) -> bool:
	## A dungeon's floors have no drops in them.
	if Dungeon.containing(tree, at) != null:
		return true
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var point: Vector3 = at + Vector3(dx, 0.0, dz) * ChunkMesher.TILE_SIZE
			var chunk := containing(tree, point)
			if chunk == null:
				return false
			var local := point - chunk.global_position
			var x := clampi(int(floor(local.x / ChunkMesher.TILE_SIZE)), 0, chunk.terrain.size - 1)
			var z := clampi(int(floor(local.z / ChunkMesher.TILE_SIZE)), 0, chunk.terrain.size - 1)
			if chunk.terrain.is_hazard(x, z):
				return false
	return true


## Open, dry, flat ground where nothing else stands: where grass and flowers grow.
func is_open_ground(x: int, z: int) -> bool:
	if not _is_free(x, z):
		return false
	if biome.water_level >= 0:
		## Leave the lake's shore a tile of bare ground.
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if terrain.in_bounds(x + dx, z + dz) \
						and terrain.level(x + dx, z + dz) < terrain.base_level:
					return false
	return true


## The height of the drawn ground at a chunk-local point, autotiled corners included.
func ground_y(local: Vector3) -> float:
	return terrain.surface_at(local.x / ChunkMesher.TILE_SIZE, local.z / ChunkMesher.TILE_SIZE) \
			* ChunkMesher.STEP_HEIGHT


## Chunk-local position of a tile's centre, on its surface.
func tile_surface(x: int, z: int) -> Vector3:
	return _tile_centre(x, z)


func _build_terrain() -> void:
	ledges.clear()
	var mesh := ChunkMesher.build(terrain, biome, _rng, ledges)
	var instance := MeshInstance3D.new()
	instance.name = "Terrain"
	instance.mesh = mesh
	instance.material_override = ChunkMesher.make_material()
	add_child(instance)

	## Ledged cliff tops: a stone lip to see, and an invisible wall over it that only bodies
	## collide with, so nobody walks, jumps or is knocked off there.
	if not ledges.is_empty():
		var paths := ChunkMesher.ledge_paths(ledges)
		var lips := MeshInstance3D.new()
		lips.name = "Ledges"
		lips.mesh = ChunkMesher.build_ledges(paths, biome)
		lips.material_override = ChunkMesher.make_material()
		add_child(lips)
		var guard := StaticBody3D.new()
		guard.name = "LedgeBody"
		guard.collision_layer = Combatant.LAYER_LEDGE
		guard.collision_mask = 0
		var guard_shape := CollisionShape3D.new()
		guard_shape.shape = ChunkMesher.ledge_shape(paths)
		guard.add_child(guard_shape)
		add_child(guard)

	## Where the mountain spills over the border, a cliff down the chunk's edge for when the next
	## chunk is too far away to be drawn. No collider: it is under the next chunk's ground.
	var skirts := ChunkMesher.build_skirts(terrain, biome)
	if skirts != null:
		var skirt := MeshInstance3D.new()
		skirt.name = "Skirt"
		skirt.mesh = skirts
		skirt.material_override = ChunkMesher.make_material()
		skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(skirt)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)

	## Caps the bottom of every pit so the sky is not visible under the world. Added after the
	## collider is built from the terrain mesh alone, so it stays scenery -- players fall through
	## it exactly as before.
	var caps := ChunkMesher.build_void_caps(heights, WorldGenerator.CHUNK_TILES)
	if caps != null:
		var void_floor := MeshInstance3D.new()
		void_floor.name = "VoidFloor"
		void_floor.mesh = caps
		void_floor.material_override = ChunkMesher.make_void_material()
		void_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(void_floor)


## The lake: a disc of water over shallows level with the shore, stepping down to deep water in
## the middle (WorldGenerator.heightmap).
func _build_lake() -> void:
	## One sheet over the whole chunk at the water line: the shore and the islands stand above
	## it and hide it, so it shows only over the lake -- which runs on into the next chunk where
	## the lake fills two, meeting that chunk's sheet edge to edge.
	var size := WorldGenerator.CHUNK_TILES * ChunkMesher.TILE_SIZE
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(size, size)
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = sheet
	instance.material_override = _with_depth(still_water_material())
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3(size * 0.5, terrain.still_surface, size * 0.5)
	add_child(instance)


## The sea: one sheet at the water line across the whole chunk. The sand stands above it and
## the sea bed slopes away beneath, so the shoreline is simply wherever the two cross.
func _build_sea() -> void:
	var size := WorldGenerator.CHUNK_TILES * ChunkMesher.TILE_SIZE
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	## Enough vertices for the swell to show.
	plane.subdivide_width = 31
	plane.subdivide_depth = 31
	plane.material = _with_depth(sea_material())
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = plane
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3(size * 0.5, WorldGenerator.SEA_SURFACE, size * 0.5)
	add_child(instance)


## A still-water material made to know how deep this chunk's water is, tile by tile, so
## deep water shows darker with a pale line along the drop -- the edge has to be readable before
## anyone walks off it. The pattern is in world space and runs on TIME, so every chunk's water
## still moves together and joins up.
func _with_depth(base: ShaderMaterial) -> ShaderMaterial:
	var size := terrain.size
	var image := Image.create(size, size, false, Image.FORMAT_R8)
	for z in size:
		for x in size:
			var value := 0.0
			if terrain.is_deep(x, z):
				var below := terrain.still_surface - terrain.surface_level(x, z) * ChunkMesher.STEP_HEIGHT
				value = clampf(0.4 + 0.3 * (below - WorldGenerator.DEEP_WATER) / ChunkMesher.STEP_HEIGHT,
						0.0, 1.0)
			image.set_pixel(x, z, Color(value, 0.0, 0.0))
	var material := base
	material.set_shader_parameter("use_depth_map", true)
	material.set_shader_parameter("depth_map", ImageTexture.create_from_image(image))
	material.set_shader_parameter("depth_origin", Vector2(global_position.x, global_position.z))
	material.set_shader_parameter("depth_map_size", float(size) * ChunkMesher.TILE_SIZE)
	return material


## The lake's and the sea's water: the same water as the river, without a current. Each
## chunk gets its own (it carries the chunk's depth map), and none is kept in a static: a
## material holding a texture past the renderer's shutdown is reported as a leak.
static func still_water_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/world/water.gdshader")
	for layer in ["wave", "wave_normal", "caustics", "foam"]:
		material.set_shader_parameter(layer + "_texture", load("res://art/water/%s.tres" % layer))
	return material


static func sea_material() -> ShaderMaterial:
	var material := still_water_material()
	material.set_shader_parameter("displacement_amount", 0.16)
	return material


func _scatter_props() -> void:
	if biome.props.is_empty():
		return
	var tiles := WorldGenerator.CHUNK_TILES
	var attempts := int(tiles * tiles * biome.prop_density * PROP_ATTEMPTS)
	var total_weight := 0.0
	for prop: Dictionary in biome.props:
		total_weight += prop["weight"]

	var container := Node3D.new()
	container.name = "Props"
	add_child(container)

	for _i in attempts:
		var x := _rng.randi_range(1, tiles - 2)
		var z := _rng.randi_range(1, tiles - 2)
		if not _is_free(x, z):
			continue
		var prop := _pick_prop(total_weight)
		if prop.is_empty():
			continue
		## Autumn and snow-covered trees in their seasons, in the same places.
		var swap := Season.prop_swap(prop["path"])
		var packed: PackedScene = load(swap[0])
		if packed == null:
			continue

		var node := packed.instantiate() as Node3D
		var scale_factor: float = prop["scale"] * _rng.randf_range(0.85, 1.15) * float(swap[1])
		node.scale = Vector3.ONE * scale_factor
		node.position = _tile_centre(x, z)
		node.rotation.y = _rng.randf() * TAU
		container.add_child(node)
		var radius: float = prop["radius"]
		## Big trunks need more room between them than the default, or a forest turns into a
		## wall: leave a few metres of gap beyond the colliders.
		_mark_occupied(x, z, maxi(PROP_CLEARANCE_TILES,
				ceili(radius * COLLIDER_FRACTION * 2.0 / ChunkMesher.TILE_SIZE) + 1))

		Culling.apply_prop_range(node, radius)
		var record := {"node": node, "body": null, "burnt": false,
				"burnable": _is_flammable(prop["path"]),
				"liftable": String(prop["path"]).get_file().begins_with("rock"),
				"taken": false, "radius": radius}
		_props.append(record)
		if radius > 0.0:
			## Trees and rocks are obstacles you can be knocked into, not scenery you walk
			## through, so anything with a radius gets a real collider.
			var body := StaticBody3D.new()
			body.collision_layer = Combatant.LAYER_SCENERY
			var shape := CollisionShape3D.new()
			var cylinder := CylinderShape3D.new()
			cylinder.radius = radius * COLLIDER_FRACTION
			## Rooted well below the surface: a body that ends up overlapping the trunk is then
			## pushed out sideways, never down through the ground under it.
			var above := 4.0 * float(prop.get("size", 1.0))
			cylinder.height = above + COLLIDER_ROOT
			shape.shape = cylinder
			shape.position.y = (above - COLLIDER_ROOT) * 0.5
			body.add_child(shape)
			body.position = node.position
			container.add_child(body)
			record["body"] = body


func _spawn_monsters() -> void:
	if biome.monster_ids.is_empty() or biome.monster_count <= 0:
		return
	var container := Node3D.new()
	container.name = "Monsters"
	add_child(container)

	var placed := 0
	for _attempt in biome.monster_count * 8:
		if placed >= biome.monster_count:
			break
		var x := _rng.randi_range(4, WorldGenerator.CHUNK_TILES - 5)
		var z := _rng.randi_range(4, WorldGenerator.CHUNK_TILES - 5)
		if not _is_free(x, z):
			continue
		var monster_id: StringName = biome.monster_ids[_rng.randi() % biome.monster_ids.size()]
		var data := MonsterDB.get_monster(monster_id)
		if data == null:
			continue

		var monster := Monster.new()
		monster.name = "Monster_%d_%02d" % [index, placed]
		_add_body_shape(monster, 0.45, 1.7)
		container.add_child(monster)
		monster.global_position = global_position + _tile_centre(x, z) + Vector3.UP * 0.4
		monster.reset_physics_interpolation()
		monster.configure(data)
		monster.loot_dropped.connect(_on_monster_died)
		monsters.append(monster)
		_mark_occupied(x, z)
		placed += 1


func _spawn_chests() -> void:
	if biome.chest_count <= 0:
		return
	var container := Node3D.new()
	container.name = "Chests"
	add_child(container)

	var placed := 0
	for _attempt in biome.chest_count * 12:
		if placed >= biome.chest_count:
			break
		var x := _rng.randi_range(3, WorldGenerator.CHUNK_TILES - 4)
		var z := _rng.randi_range(3, WorldGenerator.CHUNK_TILES - 4)
		if not _is_free(x, z):
			continue
		## The first chest in every chunk is the large one, and it holds a piece of gear.
		var large := placed == 0
		## Gear must never be stranded: the large chest only goes on ground that can be walked
		## to. The small ones may sit up on a mesa, where reaching them takes a jump.
		if large and terrain.reach[z * WorldGenerator.CHUNK_TILES + x] == 0:
			continue
		var chest := TreasureChest.new()
		chest.name = "Chest_%d_%02d" % [index, placed]
		container.add_child(chest)
		chest.position = _tile_centre(x, z)
		chest.setup(large, _rng.randi_range(15, 30) * (3 if large else 1))
		if large:
			chest.item_id = ItemDB.chest_item(index, biome.id)
		chest.opened.connect(_on_chest_opened)
		chests.append(chest)
		_mark_occupied(x, z)
		placed += 1


static func _is_flammable(model_path: String) -> bool:
	var file := model_path.get_file()
	for prefix in FLAMMABLE:
		if file.begins_with(prefix):
			return true
	return false


## Host only: sets light to every flammable prop within reach of a fire.
func burn_near(at: Vector3, reach: float) -> void:
	if not NetworkManager.is_host():
		return
	for index in _props.size():
		var record := _props[index]
		if record["burnt"] or not record["burnable"]:
			continue
		var node := record["node"] as Node3D
		var offset := node.global_position - at
		if Vector2(offset.x, offset.z).length() <= reach + 0.6 and absf(offset.y) < 3.0:
			if NetworkManager.is_networked():
				_net_burn_prop.rpc(index)
			else:
				_net_burn_prop(index)


## Where every tree and rock stands, for the map screen: {"position": Vector3, "tree": bool}.
func prop_marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record in _props:
		var node := record["node"] as Node3D
		if node != null and is_instance_valid(node) and not record["taken"] \
				and not record.get("crate", false):
			out.append({"position": global_position + node.position, "tree": record["burnable"]})
	return out


## World positions of the flammable props still standing.
func flammable_props() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for record in _props:
		if record["burnable"] and not record["burnt"]:
			found.append((record["node"] as Node3D).global_position)
	return found


## A prop burns away on every peer: its collider goes at once, so the way it was blocking is
## open, and what is left of it shrinks into the ground.
@rpc("authority", "call_local", "reliable")
func _net_burn_prop(index: int) -> void:
	if index < 0 or index >= _props.size() or _props[index]["burnt"]:
		return
	var record := _props[index]
	record["burnt"] = true
	var body := record["body"] as Node
	if body != null:
		body.queue_free()
	var node := record["node"] as Node3D
	var tween := node.create_tween()
	tween.tween_property(node, "scale", node.scale * Vector3(1.0, 0.02, 1.0), 0.9) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(node.queue_free)


## The torches beside this chunk's stretch of the paths (PathNetwork.torches).
func _place_torches(tiles: Array) -> void:
	for tile: Vector2i in tiles:
		var torch := Torch.new()
		torch.position = _tile_centre(tile.x, tile.y)
		add_child(torch)
		_mark_occupied(tile.x, tile.y, 1)


# --- crates ----------------------------------------------------------------------------------

const CRATE_MODEL := "res://art/kenney_platformer-kit-2/Models/GLB format/crate.glb"
## How big a crate stands, in metres, and how many a chunk has (a little stack or two of them).
const CRATE_SIZE := 1.0
const CRATE_GROUPS := Vector2i(2, 4)
## Between the middles of two crates in a row: more than a crate's diagonal, so turned any way
## they never overlap.
const CRATE_SPACING := 1.6


## Crates: wooden boxes in twos and threes on open ground, which anyone can pick up -- no glove
## needed -- and throw, or break with a blow, for what is inside (LootArea.spawn_crate_loot). They
## are props like the rocks, so lifting and throwing one goes exactly as a rock does. A generator
## of their own, so they move nothing that was placed before them.
func _place_crates() -> void:
	if biome.id == &"mountain":
		return
	var packed := load(CRATE_MODEL) as PackedScene
	if packed == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(_rng.seed & 0x7fffffff, 0xC4A7E))
	var tiles := WorldGenerator.CHUNK_TILES
	var container := Node3D.new()
	container.name = "Crates"
	add_child(container)
	var groups := rng.randi_range(CRATE_GROUPS.x, CRATE_GROUPS.y)
	var made := 0
	for _attempt in 60:
		if made >= groups:
			break
		var x := rng.randi_range(WorldGenerator.BORDER + 2, tiles - WorldGenerator.BORDER - 3)
		var z := rng.randi_range(WorldGenerator.BORDER + 2, tiles - WorldGenerator.BORDER - 3)
		if not _is_free(x, z) or terrain.reach[z * tiles + x] == 0 or not _dry_around(x, z, 2):
			continue
		## A row of one to three, far enough apart that no two overlap however they are turned.
		var count := rng.randi_range(1, 3)
		var heading := rng.randf() * TAU
		var along := Vector3(cos(heading), 0.0, sin(heading))
		var placed: Array[Vector3] = []
		for i in count:
			var offset := along * (i - (count - 1) * 0.5) * CRATE_SPACING \
					+ Vector3(rng.randf_range(-0.1, 0.1), 0.0, rng.randf_range(-0.1, 0.1))
			var at := _tile_centre(x, z) + offset
			var turn := rng.randf() * TAU
			## Only on the same flat ground as the middle of the group, never over an edge.
			var under := Vector2i(floori(at.x / ChunkMesher.TILE_SIZE), floori(at.z / ChunkMesher.TILE_SIZE))
			if not terrain.in_bounds(under.x, under.y) or terrain.level(under.x, under.y) != terrain.level(x, z) \
					or terrain.is_slope(under.x, under.y) or terrain.is_water(under.x, under.y):
				continue
			var crowded := false
			for other in placed:
				if Vector2(other.x - at.x, other.z - at.z).length() < CRATE_SIZE * 1.45:
					crowded = true
			if crowded:
				continue
			at.y = ground_y(at)
			placed.append(at)
			_add_crate(packed, container, at, turn)
		_mark_occupied(x, z, 2)
		made += 1


func _add_crate(packed: PackedScene, container: Node3D, at: Vector3, turn: float) -> void:
	var node := Node3D.new()
	node.name = "Crate_%d" % _props.size()
	node.set_meta("crate", true)
	var model := packed.instantiate() as Node3D
	node.add_child(model)
	## Sized from the model's own bounds, whatever units the kit was made in.
	var bounds := AABB()
	var first := true
	for mesh in Culling.meshes_under(model):
		var box := mesh.get_aabb()
		box = mesh.transform * box
		bounds = box if first else bounds.merge(box)
		first = false
	var largest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if largest > 0.0:
		model.scale = Vector3.ONE * CRATE_SIZE / largest
		model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) \
				* model.scale.x
	node.position = at
	node.rotation.y = turn
	container.add_child(node)
	var body := StaticBody3D.new()
	body.collision_layer = Combatant.LAYER_SCENERY
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE * CRATE_SIZE * 0.9
	shape.shape = box_shape
	shape.position.y = CRATE_SIZE * 0.45
	body.add_child(shape)
	body.position = at
	body.rotation.y = turn
	container.add_child(body)
	_props.append({"node": node, "body": body, "burnt": false, "burnable": false,
			"liftable": true, "taken": false, "radius": CRATE_SIZE * 1.2, "crate": true})


func is_crate(index: int) -> bool:
	return index >= 0 and index < _props.size() and _props[index].get("crate", false)


## Host: something hit hard at `point` (see DungeonEntrance.struck). Every crate within reach
## breaks, on every peer, and gives up what it held.
static func struck(tree: SceneTree, point: Vector3, radius: float) -> void:
	if not NetworkManager.is_host():
		return
	var chunk := containing(tree, point)
	if chunk == null:
		return
	for index in chunk._props.size():
		if not chunk.is_crate(index) or not chunk.can_lift(index):
			continue
		var node := chunk._props[index]["node"] as Node3D
		var offset := node.global_position + Vector3.UP * CRATE_SIZE * 0.5 - point
		if offset.length() > radius + CRATE_SIZE * 0.7:
			continue
		if NetworkManager.is_networked():
			chunk._net_break_crate.rpc(index)
		else:
			chunk._net_break_crate(index)
		chunk.spawn_crate_loot(node.global_position + Vector3.UP * 0.5)


## A crate breaks apart on every peer: gone from the ground, in a burst of its own splinters.
@rpc("authority", "call_local", "reliable")
func _net_break_crate(index: int) -> void:
	if not is_crate(index) or not can_lift(index):
		return
	var node := lift_prop(index)
	if node == null:
		return
	var at := global_position + node.position + Vector3.UP * CRATE_SIZE * 0.5
	var meshes := Culling.meshes_under(node)
	if not meshes.is_empty() and meshes[0].mesh != null:
		var splinters := RockShards.new()
		GameWorld.effects_root(get_tree()).add_child(splinters)
		splinters.burst(meshes[0], at, meshes[0].global_transform.basis.get_scale().x * 0.5)
	GameSfx.play_at(&"rock_shatter", at)
	node.queue_free()


# --- rocks a power glove can lift ----------------------------------------------------------

## The rock a player standing at `at` and looking along `facing` would pick up: the nearest one
## whose side is within `reach` and that is not behind them. {"chunk", "index"}, or {} for none.
static func nearest_liftable(tree: SceneTree, at: Vector3, facing: Vector3,
		reach: float, crates_only: bool = false) -> Dictionary:
	var best := {}
	var best_gap := reach
	for node in tree.get_nodes_in_group("chunks"):
		var chunk := node as Chunk
		## Only chunks near enough to hold a rock in reach are worth walking.
		var middle := chunk.global_position \
				+ Vector3(WorldGenerator.CHUNK_SIZE, 0.0, WorldGenerator.CHUNK_SIZE) * 0.5
		if absf(at.x - middle.x) > WorldGenerator.CHUNK_SIZE * 0.5 + 8.0 \
				or absf(at.z - middle.z) > WorldGenerator.CHUNK_SIZE * 0.5 + 8.0:
			continue
		for index in chunk._props.size():
			if not chunk.can_lift(index) or (crates_only and not chunk.is_crate(index)):
				continue
			var record := chunk._props[index]
			var offset := (record["node"] as Node3D).global_position - at
			if absf(offset.y) > 2.5:
				continue
			offset.y = 0.0
			var gap := offset.length() - float(record["radius"]) * COLLIDER_FRACTION
			if gap < best_gap and (offset.length() < 0.5 or facing.dot(offset.normalized()) > 0.2):
				best_gap = gap
				best = {"chunk": chunk, "index": index}
	return best


func can_lift(index: int) -> bool:
	if index < 0 or index >= _props.size():
		return false
	var record := _props[index]
	return record["liftable"] and not record["taken"] and not record["burnt"]


## Takes a rock out of the ground on this peer and hands its model over, collider gone. The
## caller decides what becomes of it. Null if it was already taken.
func lift_prop(index: int) -> Node3D:
	if not can_lift(index):
		return null
	var record := _props[index]
	record["taken"] = true
	var body := record["body"] as Node
	if body != null:
		body.queue_free()
		record["body"] = null
	var node := record["node"] as Node3D
	node.get_parent().remove_child(node)
	prop_lifted.emit(index)
	return node


## Adds a rock the glove can lift that was not scattered with the rest -- the desert entrance's
## marked rock. Returns its index. Built in the same order on every peer, like the props.
func add_liftable(node: Node3D, body: StaticBody3D, radius: float) -> int:
	_props.append({"node": node, "body": body, "burnt": false, "burnable": false,
			"liftable": true, "taken": false, "radius": radius})
	return _props.size() - 1


## Clears away the scenery standing within `radius` tiles of `tile`, where something is to be
## built. The records stay (a prop's index is its name on the network), marked as gone.
func clear_props_within(tile: Vector2i, radius: int) -> void:
	for record in _props:
		if record["taken"] or record["burnt"]:
			continue
		var node := record["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var at := Vector2i((node.position / ChunkMesher.TILE_SIZE).x, (node.position / ChunkMesher.TILE_SIZE).z)
		if absi(at.x - tile.x) > radius or absi(at.y - tile.y) > radius:
			continue
		## Taken and burnt both: nothing lifts it, burns it or draws it on the map again.
		record["taken"] = true
		record["burnt"] = true
		var body := record["body"] as Node
		if body != null:
			body.free()
			record["body"] = null
		node.free()
		record["node"] = null


## World positions of the rocks still standing, for the playtest and anything else that wants one.
func liftable_props() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for index in _props.size():
		if can_lift(index) and not is_crate(index):
			found.append((_props[index]["node"] as Node3D).global_position)
	return found


# --- shop and bugs ----------------------------------------------------------------------------

## The shop stands as near the middle of town as there is room for it.
func _spawn_shop() -> void:
	var tiles := WorldGenerator.CHUNK_TILES
	var half := tiles / 2
	for ring in range(2, half - 4):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var x := half + dx
				var z := half + dz
				if not _is_free(x, z) or terrain.reach[z * tiles + x] == 0:
					continue
				shop = Shop.new()
				shop.name = "Shop_%d" % index
				add_child(shop)
				shop.position = _tile_centre(x, z)
				shop.setup()
				_mark_occupied(x, z, 3)
				return


func _spawn_bugs() -> void:
	var count: int = BugSwarm.COUNTS.get(biome.id, 0)
	if count <= 0:
		return
	## Their own generator: bugs are decoration as far as the seed is concerned, and must not
	## shift where anything else in the chunk is placed.
	var rng := GameState.chunk_rng(index + 5000)
	var tiles := WorldGenerator.CHUNK_TILES
	var homes: Array[Vector3] = []
	for _attempt in count * 6:
		if homes.size() >= count:
			break
		var x := rng.randi_range(4, tiles - 5)
		var z := rng.randi_range(4, tiles - 5)
		var at := z * tiles + x
		if heights[at] == ChunkMesher.HOLE or heights[at] < terrain.base_level \
				or terrain.reach[at] == 0 or is_arena_tile(x, z):
			continue
		homes.append(_tile_centre(x, z))
	bugs = BugSwarm.new()
	bugs.name = "Bugs"
	add_child(bugs)
	bugs.build(homes, rng)


## The chunk a world position falls in, or null outside the map.
static func containing(tree: SceneTree, at: Vector3) -> Chunk:
	for node in tree.get_nodes_in_group("chunks"):
		var chunk := node as Chunk
		var local := at - chunk.global_position
		if local.x >= 0.0 and local.z >= 0.0 and local.x < WorldGenerator.CHUNK_SIZE \
				and local.z < WorldGenerator.CHUNK_SIZE:
			return chunk
	return null


# --- placement helpers -----------------------------------------------------------------------

## Local position of a tile's centre, sitting on its surface.
func _tile_centre(x: int, z: int) -> Vector3:
	return Vector3(
		(x + 0.5) * ChunkMesher.TILE_SIZE,
		terrain.surface_level(x, z) * ChunkMesher.STEP_HEIGHT,
		(z + 0.5) * ChunkMesher.TILE_SIZE)


func _is_free(x: int, z: int) -> bool:
	var level := heights[z * WorldGenerator.CHUNK_TILES + x]
	if level == ChunkMesher.HOLE:
		return false
	if _occupied.has(Vector2i(x, z)):
		return false
	var at := z * WorldGenerator.CHUNK_TILES + x
	if terrain.path[at] != 0:
		return false
	## Ramps and their landings stay clear, and nothing stands on a slope. Neither does anything
	## go in the water -- a chest on the sea bed is a chest nobody finds.
	if terrain.reserved[at] != 0 or terrain.slopes[at] != 0 or level < terrain.base_level:
		return false
	## The rim is every chunk's walkway to its neighbours; scenery on it is clutter in a doorway.
	if terrain.rim(x, z) < WorldGenerator.BORDER:
		return false
	## Nothing stands on the boss platform. The fight is about reading a tell and moving, and a
	## pine tree between you and the dragon is the difference between dodging a tail sweep and
	## being pinned against it.
	if is_arena_tile(x, z):
		return false
	## Refuse tiles right on a cliff edge, so props do not end up half-embedded in a drop and
	## monsters do not spawn already falling.
	for side in 4:
		var nx := x + ChunkMesher.NEIGHBOUR_DX[side]
		var nz := z + ChunkMesher.NEIGHBOUR_DZ[side]
		if nx < 0 or nz < 0 or nx >= WorldGenerator.CHUNK_TILES or nz >= WorldGenerator.CHUNK_TILES:
			continue
		if heights[nz * WorldGenerator.CHUNK_TILES + nx] == ChunkMesher.HOLE:
			return false
	return true


func _mark_occupied(x: int, z: int, clearance: int = PROP_CLEARANCE_TILES) -> void:
	for dz in range(-clearance, clearance + 1):
		for dx in range(-clearance, clearance + 1):
			_occupied[Vector2i(x + dx, z + dz)] = true


func _pick_prop(total_weight: float) -> Dictionary:
	var roll := _rng.randf() * total_weight
	for prop: Dictionary in biome.props:
		roll -= prop["weight"]
		if roll <= 0.0:
			return prop
	return biome.props[-1] if not biome.props.is_empty() else {}


## Kept as a name the chunk and the world both call, but the setup itself lives on Combatant
## so that players, monsters and the dragon cannot drift apart on collision layers.
static func _add_body_shape(body: CharacterBody3D, radius: float, height: float) -> void:
	Combatant.setup_body(body, radius, height)


## Highest solid tile centre in the chunk, used to stand the dragon on the summit and to place
## player spawns on ground rather than in a pit.
func highest_tile() -> Vector3:
	var best := Vector3.ZERO
	var best_level := -1
	var tiles := WorldGenerator.CHUNK_TILES
	for z in range(4, tiles - 4):
		for x in range(4, tiles - 4):
			var level := heights[z * tiles + x]
			if level != ChunkMesher.HOLE and level > best_level:
				best_level = level
				best = _tile_centre(x, z)
	return global_position + best


## Whether a tile falls inside the mountain's boss arena, including its skirt. Only the
## mountain has one; every other chunk answers false and scatters as normal.
func is_arena_tile(x: int, z: int) -> bool:
	if biome.id != &"mountain":
		return false
	var half := (WorldGenerator.CHUNK_TILES - 1) * 0.5
	return Vector2(x - half, z - half).length() \
			<= WorldGenerator.ARENA_RADIUS_TILES + WorldGenerator.ARENA_SKIRT_TILES + 1


## World position of the chunk's centre tile surface. On the mountain this is the middle of the
## flat summit platform, which is where the boss and its arena are anchored.
func centre_tile_position() -> Vector3:
	var half := WorldGenerator.CHUNK_TILES / 2
	return global_position + _tile_centre(half, half)


## Somewhere in this chunk a body can actually stand: not a pit, not a cliff edge, not up on a
## mesa it could not walk down from, and nothing already placed there. The occupancy check is the important one -- props carry colliders, and
## a player dropped inside a tree is wedged in it, unable to move in any direction.
func ground_spawn(rng: RandomNumberGenerator) -> Vector3:
	var tiles := WorldGenerator.CHUNK_TILES
	for _attempt in 128:
		var x := rng.randi_range(4, tiles - 5)
		var z := rng.randi_range(4, tiles - 5)
		if _is_free(x, z) and terrain.reach[z * tiles + x] != 0 and _dry_around(x, z, SPAWN_DRY):
			return global_position + _tile_centre(x, z) + Vector3.UP * 1.0
	## Falling back to merely-solid ground is still better than returning a pit, but the search
	## above has 128 tries on a 4096-tile chunk and reaching here means something is very wrong.
	for _attempt in 64:
		var x := rng.randi_range(4, tiles - 5)
		var z := rng.randi_range(4, tiles - 5)
		if heights[z * tiles + x] != ChunkMesher.HOLE:
			return global_position + _tile_centre(x, z) + Vector3.UP * 1.0
	return global_position + Vector3(tiles, 2.0, tiles)

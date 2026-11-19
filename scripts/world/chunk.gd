class_name Chunk
extends Node3D

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

var index: int = 0
var biome: BiomeData
## The chunk's ground. `heights` is its level array, kept as a shortcut for the many callers
## that only want to know how high a tile is.
var terrain: TerrainData
var heights: PackedInt32Array

var monsters: Array[Monster] = []
var chests: Array[TreasureChest] = []

var _rng: RandomNumberGenerator
var _occupied: Dictionary = {}
## Host's running count of pickups spawned in this chunk; see _spawn_pickup.
var _pickup_serial: int = 0
## Every prop placed, in placement order -- the same order on every peer, so a prop's index
## names it across the network. Each: {"node", "body", "burnable", "burnt", "liftable", "taken",
## "radius"}.
var _props: Array[Dictionary] = []
## The bugs flying about this chunk, if it has any.
var bugs: BugSwarm
## The town's shop; null everywhere else.
var shop: Shop

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

	terrain = WorldGenerator.heightmap(biome, _rng, ctx)
	heights = terrain.heights
	_build_terrain()
	if biome.id == &"beach":
		_build_sea()
	elif biome.water_level >= 0:
		_build_lake()
	_scatter_props()
	_spawn_monsters()
	_spawn_chests()
	## Last, so that adding them moved nothing that was already being placed from the seed.
	if biome.id == &"town":
		_spawn_shop()
	_spawn_bugs()


func _build_terrain() -> void:
	var mesh := ChunkMesher.build(terrain, biome, _rng)
	var instance := MeshInstance3D.new()
	instance.name = "Terrain"
	instance.mesh = mesh
	instance.material_override = ChunkMesher.make_material()
	add_child(instance)

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


## The lake: a disc of ankle-deep water over ground that is level with the shore.
func _build_lake() -> void:
	var size := WorldGenerator.CHUNK_TILES * ChunkMesher.TILE_SIZE
	var disc := CylinderMesh.new()
	disc.top_radius = size * 0.5 * 0.55
	disc.bottom_radius = disc.top_radius
	disc.height = 0.02
	disc.radial_segments = 48
	disc.material = _water_material()
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = disc
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## Sits just above the lake bed so the bottom is visible through it rather than z-fighting.
	instance.position = Vector3(size * 0.5,
			ChunkMesher.height_to_world(terrain.base_level) + 0.35, size * 0.5)
	add_child(instance)


## The sea: one sheet at the water line across the whole chunk. The sand stands above it and
## the sea bed slopes away beneath, so the shoreline is simply wherever the two cross.
func _build_sea() -> void:
	var size := WorldGenerator.CHUNK_TILES * ChunkMesher.TILE_SIZE
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.material = _water_material()
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = plane
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3(size * 0.5, WorldGenerator.SEA_SURFACE, size * 0.5)
	add_child(instance)


func _water_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.5, 0.75, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.15
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
		var packed: PackedScene = load(prop["path"])
		if packed == null:
			continue

		var node := packed.instantiate() as Node3D
		var scale_factor: float = prop["scale"] * _rng.randf_range(0.85, 1.15)
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


func _on_monster_died(monster: Monster) -> void:
	if not NetworkManager.is_host():
		return
	## Its last footing, not its final resting place: a skeleton shoved off a cliff still owes
	## the party its gold, and coins spawned in mid-air over a pit are coins nobody can collect.
	_spawn_loot(monster.last_grounded_position, monster.data.gold, monster.data.is_rare)


func _on_chest_opened(chest: TreasureChest) -> void:
	if not NetworkManager.is_host():
		return
	_spawn_loot(chest.global_position + Vector3.UP, chest.gold_value, chest.is_large)
	if chest.item_id != &"":
		## Set down in front of the chest rather than on it, clear of the coins.
		drop_item(chest.item_id, chest.global_position + Vector3(0.0, 0.8, 2.8))


## Loot is spawned by the host and replicated, unlike everything else in the chunk: where a coin
## lands depends on when something died, which is not derivable from the seed.
func _spawn_loot(at: Vector3, gold: int, generous: bool) -> void:
	var coins := clampi(gold / 5, 1, 6)
	for i in coins:
		var offset := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
		_net_spawn_pickup(Pickup.Kind.GOLD, gold / coins, at + offset)
	if generous:
		_net_spawn_pickup(Pickup.Kind.HEART, Combatant.POINTS_PER_HEART, at + Vector3.RIGHT)


func _net_spawn_pickup(kind: Pickup.Kind, value: int, at: Vector3, from_pid: int = 0) -> void:
	_pickup_serial += 1
	if NetworkManager.is_networked():
		_spawn_pickup.rpc(int(kind), value, at, from_pid, _pickup_serial)
	else:
		_spawn_pickup(int(kind), value, at, from_pid, _pickup_serial)


## `serial` is the host's running count for this chunk and becomes the pickup's name. The host
## later tells everyone a pickup was collected by addressing that node, so its name has to be
## the same on every machine -- which an automatically generated one is not.
@rpc("authority", "call_local", "reliable")
func _spawn_pickup(kind: int, value: int, at: Vector3, from_pid: int = 0, serial: int = 0) -> void:
	var pickup := Pickup.new()
	if serial > 0:
		pickup.name = "Pickup_%d" % serial
	add_child(pickup)
	pickup.setup(kind as Pickup.Kind, value, at)
	pickup.dropped_by = from_pid


## Host only: puts a piece of gear on the ground here. `from_pid` is the player who dropped it,
## if it was dropped rather than found -- they have to wait a moment before taking it back.
func drop_item(id: StringName, at: Vector3, from_pid: int = 0) -> void:
	var number := ItemDB.ORDER.find(id)
	if number >= 0:
		_net_spawn_pickup(Pickup.Kind.ITEM, number, at, from_pid)


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
		if node != null and is_instance_valid(node) and not record["taken"]:
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


# --- rocks a power glove can lift ----------------------------------------------------------

## The rock a player standing at `at` and looking along `facing` would pick up: the nearest one
## whose side is within `reach` and that is not behind them. {"chunk", "index"}, or {} for none.
static func nearest_liftable(tree: SceneTree, at: Vector3, facing: Vector3,
		reach: float) -> Dictionary:
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
			if not chunk.can_lift(index):
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
	return node


## World positions of the rocks still standing, for the playtest and anything else that wants one.
func liftable_props() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for index in _props.size():
		if can_lift(index):
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
			<= WorldGenerator.ARENA_RADIUS_TILES + WorldGenerator.ARENA_SKIRT_TILES


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
		if _is_free(x, z) and terrain.reach[z * tiles + x] != 0:
			return global_position + _tile_centre(x, z) + Vector3.UP * 1.0
	## Falling back to merely-solid ground is still better than returning a pit, but the search
	## above has 128 tries on a 4096-tile chunk and reaching here means something is very wrong.
	for _attempt in 64:
		var x := rng.randi_range(4, tiles - 5)
		var z := rng.randi_range(4, tiles - 5)
		if heights[z * tiles + x] != ChunkMesher.HOLE:
			return global_position + _tile_centre(x, z) + Vector3.UP * 1.0
	return global_position + Vector3(tiles, 2.0, tiles)

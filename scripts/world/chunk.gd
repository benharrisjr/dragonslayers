class_name Chunk
extends Node3D

## One of the 16 map tiles: its terrain, its scenery, its monsters and its chests.
##
## Every peer builds this from the same seed, and every node inside it is named deterministically
## (Monster_3_02, Chest_3_00). That is what lets the game skip a MultiplayerSpawner entirely --
## identical node paths on every machine mean RPCs address the same object everywhere, and the
## only thing crossing the wire is the seed.

const PROP_CLEARANCE_TILES := 2

var index: int = 0
var biome: BiomeData
var heights: PackedInt32Array

var monsters: Array[Monster] = []
var chests: Array[TreasureChest] = []

var _rng: RandomNumberGenerator
var _occupied: Dictionary = {}


func build(chunk_index: int, biome_id: StringName, rng: RandomNumberGenerator) -> void:
	index = chunk_index
	biome = BiomeLibrary.get_biome(biome_id)
	_rng = rng
	name = "Chunk_%02d_%s" % [index, biome_id]
	position = WorldGenerator.chunk_origin(index)

	heights = WorldGenerator.heightmap(biome, _rng)
	_build_terrain()
	if biome.water_level >= 0:
		_build_water()
	_scatter_props()
	_spawn_monsters()
	_spawn_chests()


func _build_terrain() -> void:
	var mesh := ChunkMesher.build(heights, WorldGenerator.CHUNK_TILES, biome, _rng)
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


func _build_water() -> void:
	var size := WorldGenerator.CHUNK_TILES * ChunkMesher.TILE_SIZE
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.5, 0.75, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.15
	plane.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = plane
	## Sits just above the lake floor so the bottom is visible through it rather than z-fighting.
	instance.position = Vector3(size * 0.5,
			ChunkMesher.height_to_world(biome.water_level) + 0.35, size * 0.5)
	add_child(instance)


func _scatter_props() -> void:
	if biome.props.is_empty():
		return
	var tiles := WorldGenerator.CHUNK_TILES
	var attempts := int(tiles * tiles * biome.prop_density * 2.0)
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
		_mark_occupied(x, z)

		var radius: float = prop["radius"]
		if radius > 0.0:
			## Trees and rocks are obstacles you can be knocked into, not scenery you walk
			## through, so anything with a radius gets a real collider.
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var cylinder := CylinderShape3D.new()
			cylinder.radius = radius * 0.45
			cylinder.height = 4.0
			shape.shape = cylinder
			shape.position.y = 2.0
			body.add_child(shape)
			body.position = node.position
			container.add_child(body)


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
		## One chest per chunk is large, and only in chunks that have more than one.
		var large := placed == 0 and biome.chest_count > 1
		var chest := TreasureChest.new()
		chest.name = "Chest_%d_%02d" % [index, placed]
		container.add_child(chest)
		chest.position = _tile_centre(x, z)
		chest.setup(large, _rng.randi_range(15, 30) * (3 if large else 1))
		chest.opened.connect(_on_chest_opened)
		chests.append(chest)
		_mark_occupied(x, z)
		placed += 1


func _on_monster_died(monster: Monster) -> void:
	if not NetworkManager.is_host():
		return
	_spawn_loot(monster.global_position, monster.data.gold, monster.data.is_rare)


func _on_chest_opened(chest: TreasureChest) -> void:
	if not NetworkManager.is_host():
		return
	_spawn_loot(chest.global_position + Vector3.UP, chest.gold_value, chest.is_large)


## Loot is spawned by the host and replicated, unlike everything else in the chunk: where a coin
## lands depends on when something died, which is not derivable from the seed.
func _spawn_loot(at: Vector3, gold: int, generous: bool) -> void:
	var coins := clampi(gold / 5, 1, 6)
	for i in coins:
		var offset := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
		_net_spawn_pickup(Pickup.Kind.GOLD, gold / coins, at + offset)
	if generous:
		_net_spawn_pickup(Pickup.Kind.HEART, Combatant.POINTS_PER_HEART, at + Vector3.RIGHT)


func _net_spawn_pickup(kind: Pickup.Kind, value: int, at: Vector3) -> void:
	if NetworkManager.is_networked():
		_spawn_pickup.rpc(int(kind), value, at)
	else:
		_spawn_pickup(int(kind), value, at)


@rpc("authority", "call_local", "reliable")
func _spawn_pickup(kind: int, value: int, at: Vector3) -> void:
	var pickup := Pickup.new()
	add_child(pickup)
	pickup.setup(kind as Pickup.Kind, value, at)


# --- placement helpers -----------------------------------------------------------------------

## Local position of a tile's centre, sitting on its surface.
func _tile_centre(x: int, z: int) -> Vector3:
	var level := heights[z * WorldGenerator.CHUNK_TILES + x]
	return Vector3(
		(x + 0.5) * ChunkMesher.TILE_SIZE,
		ChunkMesher.height_to_world(level),
		(z + 0.5) * ChunkMesher.TILE_SIZE)


func _is_free(x: int, z: int) -> bool:
	var level := heights[z * WorldGenerator.CHUNK_TILES + x]
	if level == ChunkMesher.HOLE:
		return false
	if _occupied.has(Vector2i(x, z)):
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


func _mark_occupied(x: int, z: int) -> void:
	for dz in range(-PROP_CLEARANCE_TILES, PROP_CLEARANCE_TILES + 1):
		for dx in range(-PROP_CLEARANCE_TILES, PROP_CLEARANCE_TILES + 1):
			_occupied[Vector2i(x + dx, z + dz)] = true


func _pick_prop(total_weight: float) -> Dictionary:
	var roll := _rng.randf() * total_weight
	for prop: Dictionary in biome.props:
		roll -= prop["weight"]
		if roll <= 0.0:
			return prop
	return biome.props[-1] if not biome.props.is_empty() else {}


## Combatants are capsules: a box catches on every terrain step, and stepping up 0.9 m plateaus
## is something players and monsters both need to do constantly.
static func _add_body_shape(body: CharacterBody3D, radius: float, height: float) -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	shape.position.y = height * 0.5
	body.add_child(shape)
	body.floor_max_angle = deg_to_rad(50.0)
	body.floor_snap_length = 0.6


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


func ground_spawn(rng: RandomNumberGenerator) -> Vector3:
	var tiles := WorldGenerator.CHUNK_TILES
	for _attempt in 64:
		var x := rng.randi_range(4, tiles - 5)
		var z := rng.randi_range(4, tiles - 5)
		if heights[z * tiles + x] != ChunkMesher.HOLE:
			return global_position + _tile_centre(x, z) + Vector3.UP * 1.0
	return global_position + Vector3(tiles, 2.0, tiles)

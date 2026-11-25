class_name LeafField
extends Node3D

## A chunk's fallen leaves, in the fall: heaped piles here and there and a litter of loose ones.
##
## Every leaf is an instance in a MultiMesh (one per 8x8-tile block, so blocks out of sight are
## culled together), drawn with leaves.gdshader, which makes leaves flutter as anything passes.
## Walking through them kicks them up: a kicked leaf is flung out and up, tumbles, drifts and
## settles somewhere new -- so a pile someone has run through stays run through. A sword swing
## or a fan's gust scatters them the same way, harder; fire burns them away.
##
## Like the grass, none of this is sent between machines. Every peer lays the same leaves from
## the seed and sees the same bodies move through them, so each scatters its own copy.

const GROUP := &"leaf_fields"
const BLOCK_TILES := 8
## Piles per chunk, and leaves to a pile.
const PILES := Vector2i(6, 11)
const PILE_LEAVES := 110
const PILE_RADIUS := 1.2
const PILE_HEIGHT := 0.6
## Loose leaves: the chance an open tile has some, and how many.
const LITTER_CHANCE := 0.3
const LITTER_LEAVES := Vector2i(2, 5)
const LEAF_SCALE := Vector2(1.6, 2.4)
const DRAW_DISTANCE := 75.0
## Bodies moving slower than this are standing, and kick nothing.
const KICK_SPEED := 1.5
## How far round a body leaves are kicked, beyond its own width.
const KICK_REACH := 0.55
const GRAVITY := 5.5
const DRAG := 1.6
## Bodies further than this from every player on this machine kick nothing: nobody is looking.
const KICK_DISTANCE := 35.0
## Leaf colours: crimson, rust, gold, brown, and the odd late green -- leaning away from the
## orange of the ground itself, so the leaves stand out on it.
const COLOURS: Array[Color] = [
	Color(0.72, 0.12, 0.08), Color(0.6, 0.2, 0.08), Color(0.98, 0.8, 0.22),
	Color(0.42, 0.24, 0.1), Color(0.55, 0.12, 0.12), Color(0.55, 0.55, 0.15),
]

static var _leaf_mesh: ArrayMesh
static var _material: ShaderMaterial

## Each: {"multimesh", "positions" (chunk-local), "floor" (ground height under each leaf),
## "basis" (Array[Basis]), "burnt" (PackedByteArray), "bounds" (Rect2)}
var _blocks: Array[Dictionary] = []
## Leaves in the air: [block index, leaf index, velocity, spin axis, spin rate].
var _flying: Array[Array] = []
## The same leaves, by block * 65536 + index, so a kick can skip one already in the air.
var _airborne: Dictionary = {}
var _rustle_wait: float = 0.0
var _time: float = 0.0


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = ComicLook.shader_for(preload("res://scripts/world/leaves.gdshader"))
	return _material


static func apply_pushers(found: PackedVector4Array) -> void:
	GrassField.apply_pushers(material(), found)


## Lays piles and loose leaves across `chunk`'s open ground. Returns how many leaves.
func grow(chunk: Chunk, rng: RandomNumberGenerator) -> int:
	name = "Leaves"
	add_to_group(GROUP)
	var by_block := {}
	var total := 0
	var tiles := WorldGenerator.CHUNK_TILES
	## Piles first: a mound of leaves, deepest in the middle.
	var piles := rng.randi_range(PILES.x, PILES.y)
	var placed := 0
	for _attempt in piles * 20:
		if placed >= piles:
			break
		var x := rng.randi_range(2, tiles - 3)
		var z := rng.randi_range(2, tiles - 3)
		if not chunk.is_open_ground(x, z):
			continue
		placed += 1
		var centre := chunk.tile_surface(x, z)
		for _leaf in PILE_LEAVES:
			var reach := sqrt(rng.randf()) * PILE_RADIUS
			var angle := rng.randf() * TAU
			var mound := PILE_HEIGHT * (1.0 - (reach / PILE_RADIUS) * (reach / PILE_RADIUS))
			var at := centre + Vector3(cos(angle) * reach, mound * rng.randf_range(0.5, 1.0) + 0.02,
					sin(angle) * reach)
			## On the ground under the leaf, which a rounded-off corner may have lowered.
			var floor_y := chunk.ground_y(at)
			at.y += floor_y - centre.y
			_add(by_block, at, floor_y, _leaf_basis(rng, 0.7), rng)
			total += 1
	## Then the litter: a few loose leaves on a good share of the open ground.
	for z in tiles:
		for x in tiles:
			if rng.randf() >= LITTER_CHANCE or not chunk.is_open_ground(x, z):
				continue
			var centre := chunk.tile_surface(x, z)
			for _leaf in rng.randi_range(LITTER_LEAVES.x, LITTER_LEAVES.y):
				var at := centre + Vector3(rng.randf_range(-1.0, 1.0), 0.02 + rng.randf() * 0.02,
						rng.randf_range(-1.0, 1.0))
				var floor_y := chunk.ground_y(at)
				at.y += floor_y - centre.y
				_add(by_block, at, floor_y, _leaf_basis(rng, 0.2), rng)
				total += 1
	for key: Vector2i in by_block:
		_build_block(by_block[key])
	return total


func leaf_count() -> int:
	var count := 0
	for block in _blocks:
		count += (block["positions"] as PackedVector3Array).size()
	return count


func flying_count() -> int:
	return _flying.size()


func burnt_count() -> int:
	var count := 0
	for block in _blocks:
		count += (block["burnt"] as PackedByteArray).count(1)
	return count


## The highest any leaf in the field lies, chunk-local: the top of the tallest pile.
func highest_leaf() -> float:
	var top := -INF
	for block in _blocks:
		for at: Vector3 in block["positions"]:
			top = maxf(top, at.y)
	return top


## Flings the leaves within `reach` of `origin` (world space): outwards from it, along
## `direction`, and up, harder for a bigger `strength`. Returns how many were kicked.
func kick(origin: Vector3, reach: float, direction: Vector3, strength: float) -> int:
	var local := origin - global_position
	var flat_direction := Vector3(direction.x, 0.0, direction.z)
	if flat_direction.length_squared() > 0.0001:
		flat_direction = flat_direction.normalized()
	var count := 0
	for block_index in _blocks.size():
		var block: Dictionary = _blocks[block_index]
		if not (block["bounds"] as Rect2).grow(reach + 0.5).has_point(Vector2(local.x, local.z)):
			continue
		var positions: PackedVector3Array = block["positions"]
		var burnt: PackedByteArray = block["burnt"]
		for index in positions.size():
			if burnt[index] == 1:
				continue
			var offset := positions[index] - local
			if absf(offset.y) > 2.0:
				continue
			var flat := Vector3(offset.x, 0.0, offset.z)
			var distance := flat.length()
			if distance > reach:
				continue
			if _airborne.has(block_index * 65536 + index):
				continue
			var outward := flat / distance if distance > 0.001 else flat_direction
			var power := strength * (1.0 - distance / reach * 0.5) * randf_range(0.6, 1.2)
			var velocity := (outward * 0.9 + flat_direction * 0.6) * power \
					+ Vector3.UP * randf_range(0.5, 0.9) * power
			_airborne[block_index * 65536 + index] = true
			_flying.append([block_index, index, velocity,
					Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
					randf_range(6.0, 14.0)])
			count += 1
	if count > 4 and _rustle_wait <= 0.0:
		GameSfx.play_at(&"leaves", origin)
		_rustle_wait = 0.3
	return count


## Burns the leaves within `reach` of `origin` away for good.
func burn(origin: Vector3, reach: float) -> int:
	var local := origin - global_position
	var count := 0
	for block in _blocks:
		if not (block["bounds"] as Rect2).grow(reach).has_point(Vector2(local.x, local.z)):
			continue
		var positions: PackedVector3Array = block["positions"]
		var burnt: PackedByteArray = block["burnt"]
		var multimesh: MultiMesh = block["multimesh"]
		for index in positions.size():
			if burnt[index] == 1:
				continue
			var offset := positions[index] - local
			if Vector2(offset.x, offset.z).length() > reach or absf(offset.y) > 2.5:
				continue
			burnt[index] = 1
			multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO),
					positions[index]))
			count += 1
		block["burnt"] = burnt
	return count


## Kicks leaves in every field near `origin`. See kick().
static func kick_all(tree: SceneTree, origin: Vector3, reach: float, direction: Vector3,
		strength: float) -> int:
	var count := 0
	for field in _fields_near(tree, origin, reach):
		count += field.kick(origin, reach, direction, strength)
	return count


static func burn_all(tree: SceneTree, origin: Vector3, reach: float) -> int:
	var count := 0
	for field in _fields_near(tree, origin, reach):
		count += field.burn(origin, reach)
	return count


## Every moving body near a player on this machine kicks the leaves around its feet. Called once
## a physics frame by GameWorld in the fall.
static func kick_from_bodies(tree: SceneTree) -> void:
	if tree.get_first_node_in_group(GROUP) == null:
		return
	var watchers: Array[Vector3] = []
	for pid in PlayerRegistry.local_pids():
		var body := PlayerRegistry.body_of(pid) as Node3D
		if body != null:
			watchers.append(body.global_position)
	for node in tree.get_nodes_in_group("combatants"):
		var body := node as Combatant
		if body == null or body.is_dead:
			continue
		var planar := Vector3(body.velocity.x, 0.0, body.velocity.z)
		if planar.length() < KICK_SPEED:
			continue
		var near := false
		for at in watchers:
			if at.distance_squared_to(body.global_position) < KICK_DISTANCE * KICK_DISTANCE:
				near = true
				break
		if near:
			kick_all(tree, body.global_position, body.hit_radius + KICK_REACH, planar,
					clampf(planar.length() * 0.45, 1.5, 6.0))


func _physics_process(delta: float) -> void:
	_time += delta
	_rustle_wait = maxf(0.0, _rustle_wait - delta)
	if _flying.is_empty():
		return
	var landed: Array[int] = []
	for slot in _flying.size():
		var leaf: Array = _flying[slot]
		var block: Dictionary = _blocks[leaf[0]]
		var index: int = leaf[1]
		var velocity: Vector3 = leaf[2]
		velocity.y -= GRAVITY * delta
		## Leaves fall slowly and sideways: strong drag, and a flutter back and forth.
		velocity.x -= velocity.x * DRAG * delta
		velocity.z -= velocity.z * DRAG * delta
		velocity.y = maxf(velocity.y, -2.2)
		var flutter := Vector3(sin(_time * 7.0 + index), 0.0, cos(_time * 6.0 + index * 1.7)) * 0.5
		var positions: PackedVector3Array = block["positions"]
		var floors: PackedFloat32Array = block["floor"]
		var at := positions[index] + (velocity + flutter) * delta
		var basis: Basis = (block["basis"] as Array)[index]
		basis = basis.rotated(leaf[3], float(leaf[4]) * delta).orthonormalized()
		if at.y <= floors[index] + 0.02 and velocity.y < 0.0:
			## Down. It lies flat where it fell, a little scattered.
			at.y = floors[index] + 0.02 + randf() * 0.03
			basis = Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * basis.get_scale().x)
			landed.append(slot)
		leaf[2] = velocity
		positions[index] = at
		block["positions"] = positions
		(block["basis"] as Array)[index] = basis
		(block["multimesh"] as MultiMesh).set_instance_transform(index, Transform3D(basis, at))
	landed.reverse()
	for slot in landed:
		var leaf: Array = _flying[slot]
		_airborne.erase(int(leaf[0]) * 65536 + int(leaf[1]))
		_flying.remove_at(slot)


static func _fields_near(tree: SceneTree, origin: Vector3, reach: float) -> Array[LeafField]:
	var out: Array[LeafField] = []
	for node in tree.get_nodes_in_group(GROUP):
		var field := node as LeafField
		var middle := field.global_position + Vector3.ONE * WorldGenerator.CHUNK_SIZE * 0.5
		if Vector2(middle.x - origin.x, middle.z - origin.z).length() \
				<= WorldGenerator.CHUNK_SIZE * 0.75 + reach:
			out.append(field)
	return out


func _leaf_basis(rng: RandomNumberGenerator, tilt: float) -> Basis:
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	basis = basis.rotated(Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)).normalized(),
			rng.randf_range(-tilt, tilt))
	return basis.scaled(Vector3.ONE * rng.randf_range(LEAF_SCALE.x, LEAF_SCALE.y))


func _add(by_block: Dictionary, at: Vector3, ground: float, basis: Basis,
		rng: RandomNumberGenerator) -> void:
	var key := Vector2i(int(at.x / (BLOCK_TILES * ChunkMesher.TILE_SIZE)),
			int(at.z / (BLOCK_TILES * ChunkMesher.TILE_SIZE)))
	if not by_block.has(key):
		by_block[key] = []
	var colour := COLOURS[rng.randi_range(0, COLOURS.size() - 1)]
	colour = colour * rng.randf_range(0.85, 1.12)
	(by_block[key] as Array).append([at, ground, basis, colour])


func _build_block(leaves: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _leaf()
	multimesh.instance_count = leaves.size()
	var positions := PackedVector3Array()
	var floors := PackedFloat32Array()
	var bases: Array = []
	for index in leaves.size():
		var leaf: Array = leaves[index]
		multimesh.set_instance_transform(index, Transform3D(leaf[2], leaf[0]))
		multimesh.set_instance_custom_data(index, leaf[3])
		positions.append(leaf[0])
		floors.append(leaf[1])
		bases.append(leaf[2])
	var burnt := PackedByteArray()
	burnt.resize(leaves.size())
	_blocks.append({"multimesh": multimesh, "positions": positions, "floor": floors,
			"basis": bases, "burnt": burnt, "bounds": GrassField.bounds_of(positions)})
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = DRAW_DISTANCE
	add_child(instance)


## One leaf, lying flat: a pointed oval with a slight fold down the middle, 0.25 m long.
static func _leaf() -> ArrayMesh:
	if _leaf_mesh != null:
		return _leaf_mesh
	var outline := [Vector3(0.0, 0.0, -0.13), Vector3(0.06, 0.0, -0.06), Vector3(0.075, 0.0, 0.02),
			Vector3(0.05, 0.0, 0.08), Vector3(0.0, 0.0, 0.12), Vector3(-0.05, 0.0, 0.08),
			Vector3(-0.075, 0.0, 0.02), Vector3(-0.06, 0.0, -0.06)]
	var middle := Vector3(0.0, 0.012, 0.0)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in outline.size():
		surface.add_vertex(middle)
		surface.add_vertex(outline[index])
		surface.add_vertex(outline[(index + 1) % outline.size()])
	surface.generate_normals()
	_leaf_mesh = surface.commit()
	return _leaf_mesh

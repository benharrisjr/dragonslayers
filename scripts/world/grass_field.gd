class_name GrassField
extends Node3D

## A chunk's seasonal ground cover: summer's long grass, or spring's flowers.
##
## Long grass grows in patches (noise over the chunk's open ground), a few tufts to a tile. Every
## tuft -- two crossed quads with a handful of blades cut out of each -- is an instance in a
## MultiMesh, one per 16x16-tile block so blocks out of sight are culled as a unit, drawn with
## grass.gdshader, which blows it about in gusts and bends and splays it away from whatever walks
## through it. A sword (or an axe, or a dagger) cuts what its swing passes through; fire and a
## shattering rock flatten what they land on. Cutting shrinks a tuft to stubble rather than
## removing it, so a mown path stays visible.
##
## Nothing about the grass is sent between machines. Every peer grows the same grass from the
## seed, and every peer sees the same swings and fires, so each cuts its own copy the same way.
##
## Flowers are Kenney's flower models, scattered more thinly, and only for looking at.

enum Mode { GRASS, FLOWERS }

const BLOCK_TILES := 16
## Tufts per tile; each is ten blades or so.
const BLADES_PER_TILE := 5
## How much of a chunk's open ground is long grass: noise above this grows it.
const PATCH_THRESHOLD := 0.22
const NOISE_FREQUENCY := 0.07
const BLADE_HEIGHT := Vector2(0.75, 1.15)
## What is left of a blade once it has been cut, as a share of its height.
const STUBBLE := 0.16
## Beyond this a block is not drawn. Grass is knee-high: past here it is a smudge of colour the
## ground already has. The shader shrinks it away before then, so it does not pop.
const DRAW_DISTANCE := 85.0
## Two crossed quads per tuft, twice as wide as they are tall.
const TUFT_WIDTH := 1.1
## Flower clumps per open tile, and how much bigger the Kenney models are drawn.
const FLOWER_CHANCE := 0.06
const FLOWER_SCALE := Vector2(1.4, 2.1)
const FLOWER_MODELS: Array[String] = [
	"res://art/kenney_platformer-kit-2/Models/GLB format/flowers.glb",
	"res://art/kenney_platformer-kit-2/Models/GLB format/flowers-tall.glb",
]
const GROUP := &"grass_fields"
## How far a body bends grass around it, beyond its own width.
const PUSH_REACH := 0.7
const MAX_PUSHERS := 16
## Only bodies this close to a player on this machine push grass: nobody is there to see the rest.
const PUSH_DISTANCE := 45.0

static var _blade_mesh: ArrayMesh
static var _material: ShaderMaterial

var mode: Mode = Mode.GRASS
## Each: {"multimesh": MultiMesh, "roots": PackedVector3Array (chunk-local), "heights":
## PackedFloat32Array, "cut": PackedByteArray, "basis": Array[Basis]}
var _blocks: Array[Dictionary] = []
## Flower beds: {"multimesh", "transforms" (Array[Transform3D]), "burnt" (PackedByteArray),
## "bounds" (Rect2)}.
var _beds: Array[Dictionary] = []


## The material every patch of grass shares, so the pushers are handed over once per frame.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = ComicLook.shader_for(preload("res://scripts/world/grass.gdshader"))
		_material.set_shader_parameter("wind_noise", _wind_noise())
		_material.set_shader_parameter("fade_start", DRAW_DISTANCE - 30.0)
		_material.set_shader_parameter("fade_end", DRAW_DISTANCE - 5.0)
	return _material


## Soft, seamless noise for the gusts, scrolled across the world by the shader.
static func _wind_noise() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 2
	noise.seed = 7
	return ImageTexture.create_from_image(noise.get_seamless_image(128, 128))


## Grows long grass across `chunk`'s open ground. Returns how many tufts.
func grow_grass(chunk: Chunk, rng: RandomNumberGenerator) -> int:
	mode = Mode.GRASS
	name = "Grass"
	add_to_group(GROUP)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = NOISE_FREQUENCY
	var blocks := {}
	var total := 0
	for z in WorldGenerator.CHUNK_TILES:
		for x in WorldGenerator.CHUNK_TILES:
			if noise.get_noise_2d(x, z) < PATCH_THRESHOLD or not chunk.is_open_ground(x, z):
				continue
			var key := Vector2i(x / BLOCK_TILES, z / BLOCK_TILES)
			if not blocks.has(key):
				blocks[key] = []
			var centre := chunk.tile_surface(x, z)
			for _blade in BLADES_PER_TILE:
				var root := centre + Vector3(rng.randf_range(-1.0, 1.0), 0.0,
						rng.randf_range(-1.0, 1.0)) * ChunkMesher.TILE_SIZE * 0.5
				## A tile's corner may be rounded off or filled in (autotiled cliffs).
				root.y = chunk.ground_y(root)
				(blocks[key] as Array).append([root, rng.randf_range(BLADE_HEIGHT.x, BLADE_HEIGHT.y),
						rng.randf() * TAU, rng.randf_range(0.8, 1.35),
						Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.88, 1.1),
						rng.randf_range(0.8, 1.0))])
				total += 1
	for key: Vector2i in blocks:
		_add_grass_block(blocks[key])
	return total


## Scatters flower clumps across `chunk`'s open ground. Returns how many.
func grow_flowers(chunk: Chunk, rng: RandomNumberGenerator) -> int:
	mode = Mode.FLOWERS
	name = "Flowers"
	add_to_group(GROUP)
	var meshes: Array[Mesh] = []
	for path in FLOWER_MODELS:
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var model := packed.instantiate() as Node3D
		var found := Culling.meshes_under(model)
		if not found.is_empty() and found[0].mesh != null:
			meshes.append(found[0].mesh)
		model.free()
	if meshes.is_empty():
		return 0
	## Per block and per model, so each MultiMesh draws one mesh.
	var blocks := {}
	var total := 0
	## Flowers come in drifts rather than evenly: a noise field makes some meadows thick with
	## them and leaves others bare.
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.05
	for z in WorldGenerator.CHUNK_TILES:
		for x in WorldGenerator.CHUNK_TILES:
			var chance := FLOWER_CHANCE * (1.0 + 2.5 * maxf(noise.get_noise_2d(x, z), 0.0))
			if rng.randf() >= chance or not chunk.is_open_ground(x, z):
				continue
			var which := rng.randi_range(0, meshes.size() - 1)
			var key := Vector3i(x / BLOCK_TILES, z / BLOCK_TILES, which)
			if not blocks.has(key):
				blocks[key] = []
			var at := chunk.tile_surface(x, z) + Vector3(rng.randf_range(-0.6, 0.6), 0.0,
					rng.randf_range(-0.6, 0.6))
			at.y = chunk.ground_y(at)
			var size := rng.randf_range(FLOWER_SCALE.x, FLOWER_SCALE.y)
			(blocks[key] as Array).append(Transform3D(
					Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), at))
			total += 1
	for key: Vector3i in blocks:
		var transforms: Array = blocks[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = meshes[key.z]
		multimesh.instance_count = transforms.size()
		var origins := PackedVector3Array()
		for index in transforms.size():
			multimesh.set_instance_transform(index, transforms[index])
			origins.append((transforms[index] as Transform3D).origin)
		var burnt := PackedByteArray()
		burnt.resize(transforms.size())
		_beds.append({"multimesh": multimesh, "transforms": transforms, "burnt": burnt,
				"bounds": GrassField.bounds_of(origins)})
		_add_instance(multimesh, false)
	return total


func blade_count() -> int:
	var count := 0
	for block in _blocks:
		count += (block["roots"] as PackedVector3Array).size()
	return count


func cut_count() -> int:
	var count := 0
	for block in _blocks:
		count += (block["cut"] as PackedByteArray).count(1)
	return count


## Cuts down the grass in a swing: within `reach` of `origin` (world space) and within half of
## `arc_degrees` either side of `facing`. A full circle (360) is a fire or a falling rock.
## Returns how many blades were cut.
func cut(origin: Vector3, reach: float, facing: Vector3 = Vector3.ZERO,
		arc_degrees: float = 360.0) -> int:
	if mode != Mode.GRASS:
		return 0
	var local := origin - global_position
	var flat_facing := Vector2(facing.x, facing.z).normalized()
	var half_arc := deg_to_rad(arc_degrees) * 0.5
	var count := 0
	for block in _blocks:
		## Most cuts are a sword's length across; skip every block they cannot reach.
		if not (block["bounds"] as Rect2).grow(reach).has_point(Vector2(local.x, local.z)):
			continue
		var roots: PackedVector3Array = block["roots"]
		var cut_flags: PackedByteArray = block["cut"]
		var multimesh: MultiMesh = block["multimesh"]
		for index in roots.size():
			if cut_flags[index] == 1:
				continue
			var offset := roots[index] - local
			if absf(offset.y) > 2.5:
				continue
			var flat := Vector2(offset.x, offset.z)
			if flat.length() > reach:
				continue
			if arc_degrees < 360.0 and flat.length() > 0.4 \
					and absf(flat_facing.angle_to(flat)) > half_arc:
				continue
			cut_flags[index] = 1
			var basis: Basis = block["basis"][index]
			multimesh.set_instance_transform(index,
					Transform3D(basis.scaled(Vector3(1.0, STUBBLE, 1.0)), roots[index]))
			count += 1
		block["cut"] = cut_flags
	return count


## Fire: long grass within `reach` burns down to stubble, and flowers burn away entirely.
## Returns how many blades or flowers went.
func burn(origin: Vector3, reach: float) -> int:
	if mode == Mode.GRASS:
		return cut(origin, reach)
	var local := origin - global_position
	var count := 0
	for bed in _beds:
		if not (bed["bounds"] as Rect2).grow(reach).has_point(Vector2(local.x, local.z)):
			continue
		var transforms: Array = bed["transforms"]
		var burnt: PackedByteArray = bed["burnt"]
		for index in transforms.size():
			var at: Vector3 = (transforms[index] as Transform3D).origin
			if burnt[index] == 1 or absf(at.y - local.y) > 2.5 \
					or Vector2(at.x - local.x, at.z - local.z).length() > reach:
				continue
			burnt[index] = 1
			(bed["multimesh"] as MultiMesh).set_instance_transform(index,
					Transform3D(Basis().scaled(Vector3.ZERO), at))
			count += 1
		bed["burnt"] = burnt
	return count


func flower_count() -> int:
	var count := 0
	for bed in _beds:
		count += (bed["transforms"] as Array).size()
	return count


func burnt_flowers() -> int:
	var count := 0
	for bed in _beds:
		count += (bed["burnt"] as PackedByteArray).count(1)
	return count


## Fire, in every field near it. See burn().
static func burn_all(tree: SceneTree, origin: Vector3, reach: float) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(GROUP):
		var field := node as GrassField
		var middle := field.global_position + Vector3.ONE * WorldGenerator.CHUNK_SIZE * 0.5
		if Vector2(middle.x - origin.x, middle.z - origin.z).length() \
				> WorldGenerator.CHUNK_SIZE * 0.75 + reach:
			continue
		count += field.burn(origin, reach)
	return count


## Cuts grass in every field in the match. See cut().
static func cut_all(tree: SceneTree, origin: Vector3, reach: float,
		facing: Vector3 = Vector3.ZERO, arc_degrees: float = 360.0) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(GROUP):
		var field := node as GrassField
		## A field's blocks are no more than a chunk across; skip the ones nowhere near.
		var middle := field.global_position + Vector3.ONE * WorldGenerator.CHUNK_SIZE * 0.5
		if Vector2(middle.x - origin.x, middle.z - origin.z).length() \
				> WorldGenerator.CHUNK_SIZE * 0.75 + reach:
			continue
		count += field.cut(origin, reach, facing, arc_degrees)
	if count > 0:
		GameSfx.play_at(&"grass_cut", origin)
	return count


## The xz rectangle a set of chunk-local points covers.
static func bounds_of(points: PackedVector3Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var box := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
	for point in points:
		box = box.expand(Vector2(point.x, point.z))
	return box


## The bodies grass and leaves should bend away from: every living player, and the monsters
## near the players on this machine, nearest first, as (position, radius). Shared by both, and
## built once a frame.
static func collect_pushers(tree: SceneTree) -> PackedVector4Array:
	var watchers: Array[Vector3] = []
	for pid in PlayerRegistry.local_pids():
		var body := PlayerRegistry.body_of(pid) as Node3D
		if body != null:
			watchers.append(body.global_position)
	var candidates: Array = []
	for node in tree.get_nodes_in_group("combatants"):
		var body := node as Combatant
		if body == null or body.is_dead:
			continue
		var nearest := INF
		for at in watchers:
			nearest = minf(nearest, at.distance_to(body.global_position))
		if nearest > PUSH_DISTANCE:
			continue
		candidates.append([nearest, body])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var pushers := PackedVector4Array()
	for entry: Array in candidates.slice(0, MAX_PUSHERS):
		var body: Combatant = entry[1]
		var at := body.global_position
		pushers.append(Vector4(at.x, at.y, at.z, body.hit_radius + PUSH_REACH))
	return pushers


## Hands a grass or leaf material the bodies to bend away from.
static func apply_pushers(target: ShaderMaterial, found: PackedVector4Array) -> void:
	var pushers := found.duplicate()
	var count := pushers.size()
	pushers.resize(MAX_PUSHERS)
	target.set_shader_parameter("pushers", pushers)
	target.set_shader_parameter("pusher_count", count)


func _add_grass_block(blades: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _blade()
	multimesh.instance_count = blades.size()
	var roots := PackedVector3Array()
	var heights := PackedFloat32Array()
	var bases: Array[Basis] = []
	for index in blades.size():
		var blade: Array = blades[index]
		var basis := Basis(Vector3.UP, blade[2]).scaled(Vector3(blade[3], blade[1], blade[3]))
		multimesh.set_instance_transform(index, Transform3D(basis, blade[0]))
		multimesh.set_instance_custom_data(index, blade[4])
		roots.append(blade[0])
		heights.append(blade[1])
		bases.append(basis)
	var cut_flags := PackedByteArray()
	cut_flags.resize(blades.size())
	_blocks.append({"multimesh": multimesh, "roots": roots, "heights": heights, "cut": cut_flags,
			"basis": bases, "bounds": GrassField.bounds_of(roots)})
	_add_instance(multimesh, true)


func _add_instance(multimesh: MultiMesh, grass: bool) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = DRAW_DISTANCE
	if grass:
		instance.material_override = material()
	add_child(instance)


## One tuft: two upright quads crossed at right angles, TUFT_WIDTH across and 1 m tall, cut into
## four rows so the wind and a push bend them smoothly. The shader draws the blades on them.
static func _blade() -> ArrayMesh:
	if _blade_mesh != null:
		return _blade_mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 4
	var half := TUFT_WIDTH * 0.5
	for across: Vector3 in [Vector3(half, 0.0, 0.0), Vector3(0.0, 0.0, half)]:
		for row in rows:
			var low := float(row) / rows
			var high := float(row + 1) / rows
			var corners := [[-across, low, 0.0], [across, low, 1.0], [across, high, 1.0],
					[-across, high, 0.0]]
			for index in [0, 1, 2, 0, 2, 3]:
				var corner: Array = corners[index]
				surface.set_uv(Vector2(corner[2], corner[1]))
				surface.set_normal(Vector3.UP)
				surface.add_vertex((corner[0] as Vector3) + Vector3(0.0, corner[1], 0.0))
	_blade_mesh = surface.commit()
	return _blade_mesh

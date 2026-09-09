class_name ChunkMesher
extends RefCounted

## Turns a chunk's integer heightmap into one vertex-coloured mesh plus its collider.
##
## Terrain is deliberately stepped rather than smooth. Links-Awakening-style ground reads as a
## few crisp plateaus with vertical cliffs between them, and that shape is also what makes the
## knockback mechanic legible: you can see exactly where the edge is before something shoves
## you over it. Cliff faces are real geometry in the collider, not decoration, for the same reason.

## One tile is 2 m, so a 32x32 chunk is 64 m across and a 4x4 map is 256 m.
const TILE_SIZE := 2.0
## One step is a comfortable hop (jump apex is ~2.3 m) but two stacked steps are not, which is
## what gives the plateaus their shape without needing explicit level design.
const STEP_HEIGHT := 0.9
## Sentinel height meaning "no floor here" -- the pits players fall into.
const HOLE := -999

## How far a pit's walls drop before the void cap closes it off. Deep enough that the bottom is
## never in frame from a normal camera angle, so a pit reads as bottomless.
const VOID_DEPTH := -8

## Side order used by both the mesher and the chunk's placement checks: +x, +z, -x, -z.
const NEIGHBOUR_DX: Array[int] = [1, 0, -1, 0]
const NEIGHBOUR_DZ: Array[int] = [0, 1, 0, -1]


static func height_to_world(level: int) -> float:
	return float(level) * STEP_HEIGHT


## `heights` is row-major, size*size, in tile levels.
static func build(heights: PackedInt32Array, size: int, biome: BiomeData,
		rng: RandomNumberGenerator) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z in size:
		for x in size:
			var level := heights[z * size + x]
			if level == HOLE:
				continue
			var top := height_to_world(level)
			var origin := Vector3(x * TILE_SIZE, top, z * TILE_SIZE)
			## A little per-tile colour jitter stops a large flat plateau reading as a single
			## untextured slab, which is the main risk of untextured terrain.
			var shade := 1.0 + rng.randf_range(-0.06, 0.06)
			_quad(surface, biome.ground_color * shade,
				origin,
				origin + Vector3(TILE_SIZE, 0, 0),
				origin + Vector3(TILE_SIZE, 0, TILE_SIZE),
				origin + Vector3(0, 0, TILE_SIZE))

			## A cliff face wherever a neighbour sits lower, or where the chunk ends.
			for side in 4:
				var nx := x + NEIGHBOUR_DX[side]
				var nz := z + NEIGHBOUR_DZ[side]
				var neighbour_level := 0
				if nx < 0 or nz < 0 or nx >= size or nz >= size:
					## Chunk borders are pinned to level 0 by the generator, so the rim never
					## needs a wall against its neighbour.
					neighbour_level = 0
				else:
					var found := heights[nz * size + nx]
					## A hole is bottomless: the wall drops far enough that no camera angle
					## reveals the underside of the world.
					neighbour_level = VOID_DEPTH if found == HOLE else found
				if neighbour_level >= level:
					continue
				var bottom := height_to_world(neighbour_level)
				var cliff_shade := 1.0 + rng.randf_range(-0.05, 0.05)
				_cliff(surface, biome.cliff_color * cliff_shade, origin, side, top, bottom)

	surface.generate_normals()
	var mesh := surface.commit()
	return mesh


## A black floor sealing the bottom of every pit.
##
## Deliberately built as a *separate* mesh from the terrain rather than another surface on it,
## because the terrain mesh is what the collision shape is generated from -- a floor welded into
## it would be something players land on, and the whole point of a pit is falling through.
## Without it the shaft is open at the bottom and you can see the sky underneath the world.
static func build_void_caps(heights: PackedInt32Array, size: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var found_any := false
	var floor_y := height_to_world(VOID_DEPTH)

	for z in size:
		for x in size:
			if heights[z * size + x] != HOLE:
				continue
			found_any = true
			var origin := Vector3(x * TILE_SIZE, floor_y, z * TILE_SIZE)
			## Wound to face upwards, so it is visible looking down into the shaft.
			_quad(surface, Color.BLACK,
				origin,
				origin + Vector3(TILE_SIZE, 0, 0),
				origin + Vector3(TILE_SIZE, 0, TILE_SIZE),
				origin + Vector3(0, 0, TILE_SIZE))

	if not found_any:
		return null
	surface.generate_normals()
	return surface.commit()


## Unshaded pure black. A lit material would catch the sun and read as a surface at the bottom
## of the pit rather than as nothing at all.
static func make_void_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	## Visible from below too, so a player falling past it does not see through the world.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.metallic = 0.0
	return material


static func _quad(surface: SurfaceTool, color: Color, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	for vertex in [a, b, c, a, c, d]:
		surface.set_color(color)
		surface.add_vertex(vertex)


static func _cliff(surface: SurfaceTool, color: Color, origin: Vector3, side: int,
		top: float, bottom: float) -> void:
	## Corners of the tile's top face, walked clockwise so each side index maps to one edge.
	var corners := [
		origin + Vector3(TILE_SIZE, 0, 0), origin + Vector3(TILE_SIZE, 0, TILE_SIZE),
		origin + Vector3(0, 0, TILE_SIZE), origin,
	]
	## Each side index takes the edge between two consecutive corners, so the wall it emits is
	## the one facing that neighbour.
	var left: Vector3 = corners[side]
	var right: Vector3 = corners[(side + 1) % 4]
	var drop := Vector3(0.0, bottom - top, 0.0)
	_quad(surface, color, left, left + drop, right + drop, right)

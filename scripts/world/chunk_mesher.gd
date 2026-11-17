class_name ChunkMesher
extends RefCounted

## Turns a chunk's integer heightmap into one vertex-coloured mesh plus its collider.
##
## Terrain is deliberately stepped rather than smooth. Links-Awakening-style ground reads as a
## few crisp plateaus with vertical cliffs between them, and that shape is also what makes the
## knockback mechanic legible: you can see exactly where the edge is before something shoves
## you over it. Cliff faces are real geometry in the collider, not decoration, for the same reason.
## The plateaus are joined by ramps and shores -- tiles whose corners sit at different heights --
## because a player without the feather cannot hop even one step.

## One tile is 2 m, so a 64x64 chunk is 128 m across and a 4x4 map is 512 m.
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


## Builds the terrain surface from a chunk's baked TerrainData.
static func build(terrain: TerrainData, biome: BiomeData, rng: RandomNumberGenerator) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size := terrain.size

	for z in size:
		for x in size:
			var level := terrain.level(x, z)
			if level == HOLE:
				continue
			var x0 := x * TILE_SIZE
			var z0 := z * TILE_SIZE
			var c0 := Vector3(x0, terrain.corner(x, z, 0) * STEP_HEIGHT, z0)
			var c1 := Vector3(x0 + TILE_SIZE, terrain.corner(x, z, 1) * STEP_HEIGHT, z0)
			var c2 := Vector3(x0 + TILE_SIZE, terrain.corner(x, z, 2) * STEP_HEIGHT, z0 + TILE_SIZE)
			var c3 := Vector3(x0, terrain.corner(x, z, 3) * STEP_HEIGHT, z0 + TILE_SIZE)
			## A little per-tile colour jitter stops a large flat plateau reading as a single
			## untextured slab, which is the main risk of untextured terrain.
			var shade := 1.0 + rng.randf_range(-0.06, 0.06)
			var color := biome.ground_color
			if level < terrain.base_level:
				color = biome.low_color
			if terrain.is_slope(x, z) and terrain.slopes[z * size + x] != TerrainData.Slope.SMOOTH:
				## Ramps are a touch paler than the ground they join, so the way up a cliff
				## can be picked out from across the chunk.
				color = color.lightened(0.14)
			_quad(surface, color * shade, c0, c1, c2, c3)

			## A cliff face wherever a neighbour's edge sits lower than this tile's.
			var corners: Array[Vector3] = [c1, c2, c3, c0]
			for side in 4:
				var mine := terrain.edge(x, z, side)
				var nx := x + NEIGHBOUR_DX[side]
				var nz := z + NEIGHBOUR_DZ[side]
				## Heights of whatever is beyond the edge, at this edge's left and right ends.
				var beyond_left := 0.0
				var beyond_right := 0.0
				if not terrain.in_bounds(nx, nz):
					var beyond: int = terrain.side_levels[side]
					## Nothing beyond the edge of the map but the boundary cliffs, which stand
					## against it, so no wall is needed there.
					if beyond == TerrainData.MAP_EDGE:
						continue
					beyond_left = beyond
					beyond_right = beyond
				elif terrain.is_hole(nx, nz):
					## A hole is bottomless: the wall drops far enough that no camera angle
					## reveals the underside of the world.
					beyond_left = VOID_DEPTH
					beyond_right = VOID_DEPTH
				else:
					## The neighbour walks its edge the other way round.
					var theirs := terrain.edge(nx, nz, (side + 2) % 4)
					beyond_left = theirs.y
					beyond_right = theirs.x
				if mine.x <= beyond_left + 0.01 and mine.y <= beyond_right + 0.01:
					continue
				var cliff_shade := 1.0 + rng.randf_range(-0.05, 0.05)
				var left := corners[side]
				var right := corners[(side + 1) % 4]
				var left_foot := Vector3(left.x, minf(left.y, beyond_left * STEP_HEIGHT), left.z)
				var right_foot := Vector3(right.x, minf(right.y, beyond_right * STEP_HEIGHT), right.z)
				_quad(surface, biome.cliff_color * cliff_shade, left, left_foot, right_foot, right)

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

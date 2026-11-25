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
const STEP_HEIGHT := 1.5
## Sentinel height meaning "no floor here" -- the pits players fall into.
const HOLE := -999

## How far a pit's walls drop before the void cap closes it off. Deep enough that the bottom is
## never in frame from a normal camera angle, so a pit reads as bottomless.
const VOID_DEPTH := -8

## The colour of the river's bed.
const RIVER_BED := Color(0.33, 0.3, 0.26)

## Side order used by both the mesher and the chunk's placement checks: +x, +z, -x, -z.
const NEIGHBOUR_DX: Array[int] = [1, 0, -1, 0]
const NEIGHBOUR_DZ: Array[int] = [0, 1, 0, -1]


static func height_to_world(level: int) -> float:
	return float(level) * STEP_HEIGHT


## Builds the terrain surface from a chunk's baked TerrainData.
##
## Smoothed: flat ground beside any change in it is drawn from TerrainData's smoothed outline --
## lattice cells cut into flat pieces, a cliff face along every line the outline runs -- so cliffs
## come out in curves rather than tile steps. Ramps, shores, the river and the rest are drawn as
## they stand, with walls along every half of a tile's edge that drops. Tiles in the middle of a
## flat stretch stay one quad, which keeps the mesh and its collider small.
##
## Each vertex carries what terrain.gdshader needs to texture it:
##  - COLOR: its own colour, alpha marking snow (as before).
##  - CUSTOM0: the colour on the other side of the nearest edge -- on a wall, the ground above
##    it (for the grass hanging over the lip); on the ground, the biome's rock (for the rim).
##  - UV: on a wall, metres along it and height above its foot; on the ground, 1 where the
##    vertex is on a cliff's lip (x) or at a cliff's foot (y), 0 a quadrant away.
##  - UV2: on a wall, depth below its lip and y = 1; on the ground, x = 1 on a ramp.
##
## `ledges`, if given, is filled with the cliff tops that carry a ledge, for build_ledges and
## ledge_shape: [from, to (chunk-local x, z), height, inward (towards the high side)].
static func build(terrain: TerrainData, biome: BiomeData, rng: RandomNumberGenerator,
		ledges: Array = []) -> ArrayMesh:
	var size := terrain.size
	var snowy := Season.snows_on(biome.id)
	var cliff := Season.cliff_color(biome.id, biome.cliff_color)
	cliff.a = 0.0
	var ground: Array = []
	var walls: Array = []
	## The biome's two ground colours, looked up once rather than per tile.
	var palette := {"ground": Season.ground_color(biome.id, biome.ground_color),
		"low": Season.ground_color(biome.id, biome.low_color), "base": terrain.base_level}

	for z in size:
		for x in size:
			var level := terrain.level(x, z)
			if level == HOLE:
				continue
			var index := z * size + x
			if _plain(terrain, x, z):
				## Flat ground with the same flat ground all round: one quad, no walls, and no
				## random number but the tile's own (the old mesher drew none for its sides).
				## The random number is still drawn, as it always was, since the rest of the chunk is
				## placed from the same generator -- but no longer used: shading each tile on its
				## own showed the grid up across every field. The shader's noise does that now.
				rng.randf_range(-0.06, 0.06)
				var plain_shade := 1.0
				var plain := (palette["ground"] if level >= terrain.base_level else palette["low"]) as Color
				plain *= plain_shade
				if terrain.deep[index] == 1:
					plain = plain.darkened(0.16 * maxf(terrain.base_level - level, 0.0))
				plain.a = 1.0 if snowy else 0.0
				var y := level * STEP_HEIGHT
				var x0 := x * TILE_SIZE
				var z0 := z * TILE_SIZE
				var p0 := Vector3(x0, y, z0)
				var p2 := Vector3(x0 + TILE_SIZE, y, z0 + TILE_SIZE)
				## Already wound to face up; nothing of it touches an edge.
				ground.append([p0, Vector3(x0 + TILE_SIZE, y, z0), p2, plain, cliff, false, true])
				ground.append([p0, p2, Vector3(x0, y, z0 + TILE_SIZE), plain, cliff, false, true])
				continue
			## A little per-tile colour jitter stops a large flat plateau reading as a single
			## slab. The random numbers are drawn in exactly the order they always were (one a
			## tile, then one per side the old square walls stood on), since the rest of the
			## chunk is placed from the same generator.
			rng.randf_range(-0.06, 0.06)
			var shade := 1.0
			var side_shade: Array[float] = [1.0, 1.0, 1.0, 1.0]
			## Sides against flat ground at the same level have no wall, then or now.
			var open_side: Array[bool] = [false, false, false, false]
			for side in 4:
				open_side[side] = _level_with(terrain, x, z, side)
				if not open_side[side] and _old_wall_on(terrain, x, z, side):
					rng.randf_range(-0.05, 0.05)
			var wet := terrain.water[index] == 1
			var ramp := terrain.is_slope(x, z) and terrain.slopes[index] != TerrainData.Slope.SMOOTH
			var tile := {"shade": shade, "wet": wet, "ramp": ramp, "deep": terrain.deep[index] == 1,
				"palette": palette}
			var color := _ground_color(terrain, biome, tile, float(level), snowy)

			var smooth := terrain.smooths(x, z)
			if smooth:
				_smoothed(terrain, biome, tile, x, z, snowy, cliff, ground, walls)
			else:
				var c := _corner_points(terrain, x, z)
				ground.append([c[0], c[1], c[2], color, cliff, ramp])
				ground.append([c[0], c[2], c[3], color, cliff, ramp])

			## A wall along each half of the tile's edge that stands above what is beyond it.
			var ends := _corner_points(terrain, x, z)
			var own_sink := terrain.sink_at(x, z)
			for side in 4:
				if open_side[side]:
					continue
				## Between two smoothed tiles the cliff is part of the smoothed outline, drawn above.
				if smooth and terrain.smooths(x + NEIGHBOUR_DX[side], z + NEIGHBOUR_DZ[side]):
					continue
				var left_end: Vector3 = ends[(side + 1) % 4]
				var right_end: Vector3 = ends[(side + 2) % 4]
				for half in 2:
					var levels := terrain.half_edge(x, z, side, half)
					var mine := levels * STEP_HEIGHT - Vector2.ONE * own_sink
					var beyond: Variant = _beyond(terrain, x, z, side, half)
					if beyond == null:
						continue
					var far := beyond as Vector2
					if mine.x <= far.x + 0.01 and mine.y <= far.y + 0.01:
						continue
					var a := Vector2(left_end.x, left_end.z)
					var b := Vector2(right_end.x, right_end.z)
					var middle := (a + b) * 0.5
					var from := a if half == 0 else middle
					var to := middle if half == 0 else b
					var top := _ground_color(terrain, biome, tile, maxf(levels.x, levels.y), snowy)
					var face := cliff * side_shade[side]
					face.a = 0.0
					walls.append([from, to, mine.x, mine.y, minf(mine.x, far.x), minf(mine.y, far.y),
							Vector3(NEIGHBOUR_DX[side], 0.0, NEIGHBOUR_DZ[side]), face, top])

	ledges.append_array(_ledge_segments(terrain, walls))
	return _commit(ground, walls, terrain.paint)


## The ground colour of a tile, or of a reshaped corner of it, at `level`.
static func _ground_color(terrain: TerrainData, biome: BiomeData, tile: Dictionary, level: float,
		snowy: bool) -> Color:
	var palette: Dictionary = tile["palette"]
	var color: Color = palette["ground"]
	if level < terrain.base_level:
		color = palette["low"]
	if tile["ramp"]:
		## Ramps are a touch paler than the ground they join, so the way up a cliff can be picked
		## out from across the chunk.
		color = color.lightened(0.08)
	if tile["deep"]:
		## Deep water's bed darkens with each step down, so the drop reads through the water
		## before anyone walks off it.
		color = color.darkened(0.16 * maxf(terrain.base_level - level, 0.0))
	if tile["wet"]:
		## The river bed: dark, wet stone, whatever the season.
		color = RIVER_BED
	color *= float(tile["shade"])
	## Alpha marks snow for the terrain shader's tracks; see terrain.gdshader.
	color.a = 1.0 if snowy and not tile["wet"] else 0.0
	return color


## A tile's four corners in chunk-local metres, as TerrainData bakes them.
static func _corner_points(terrain: TerrainData, x: int, z: int) -> Array[Vector3]:
	var x0 := x * TILE_SIZE
	var z0 := z * TILE_SIZE
	## The river's bed, where it runs deeper than its level says.
	var sink := terrain.sink_at(x, z)
	return [Vector3(x0, terrain.corner(x, z, 0) * STEP_HEIGHT - sink, z0),
		Vector3(x0 + TILE_SIZE, terrain.corner(x, z, 1) * STEP_HEIGHT - sink, z0),
		Vector3(x0 + TILE_SIZE, terrain.corner(x, z, 2) * STEP_HEIGHT - sink, z0 + TILE_SIZE),
		Vector3(x0, terrain.corner(x, z, 3) * STEP_HEIGHT - sink, z0 + TILE_SIZE)]


## Whether a tile is plain flat ground in the middle of more of the same: nothing round it
## differs, so it needs no quadrants and has no walls.
static func _plain(terrain: TerrainData, x: int, z: int) -> bool:
	if terrain.rim(x, z) == 0:
		return false
	var size := terrain.size
	var index := z * size + x
	var own := terrain.heights[index]
	if own == HOLE:
		return false
	for at in [index - size - 1, index - size, index - size + 1, index - 1, index, index + 1,
			index + size - 1, index + size, index + size + 1]:
		if terrain.heights[at] != own or terrain.slopes[at] != 0 or terrain.water[at] != 0:
			return false
	return true


## Draws a smoothing tile from TerrainData's smoothed outline: its lattice cells, each cut into
## flat pieces at their levels, with a cliff face along every line a cliff runs in it. A tile the
## outline does not cross is one quad.
static func _smoothed(terrain: TerrainData, biome: BiomeData, tile: Dictionary, x: int, z: int,
		snowy: bool, cliff: Color, ground: Array, walls: Array) -> void:
	var sub := TerrainData.SUB
	var levels := PackedInt32Array()
	var uniform := true
	for j in sub + 1:
		for i in sub + 1:
			var level := terrain.lattice_level_at(x * sub + i, z * sub + j)
			levels.append(level)
			if level != levels[0]:
				uniform = false
	var face := cliff
	face.a = 0.0
	var colors := {}
	var step := TILE_SIZE / sub
	var x0 := x * TILE_SIZE
	var z0 := z * TILE_SIZE
	if uniform:
		_flat_strip(ground, Vector2(x0, z0), Vector2(x0 + TILE_SIZE, z0 + TILE_SIZE), levels[0],
				_ground_color(terrain, biome, tile, float(levels[0]), snowy), cliff)
		return
	for j in sub:
		## Runs of flat cells along the row are drawn as one strip.
		var run_start := -1
		var run_level := 0
		for i in sub + 1:
			var flat := false
			var level := 0
			if i < sub:
				level = levels[j * (sub + 1) + i]
				flat = levels[j * (sub + 1) + i + 1] == level and levels[(j + 1) * (sub + 1) + i] == level \
						and levels[(j + 1) * (sub + 1) + i + 1] == level
			if run_start >= 0 and (not flat or level != run_level):
				if not colors.has(run_level):
					colors[run_level] = _ground_color(terrain, biome, tile, float(run_level), snowy)
				_flat_strip(ground, Vector2(x0 + run_start * step, z0 + j * step),
						Vector2(x0 + i * step, z0 + (j + 1) * step), run_level, colors[run_level], cliff)
				run_start = -1
			if i == sub:
				break
			if flat:
				if run_start < 0:
					run_start = i
					run_level = level
				continue
			var cx := x * sub + i
			var cz := z * sub + j
			var cell := terrain.cell_at(cx, cz)
			var shape := TerrainData.cell_shape(cell[0], cell[1])
			for piece: Array in shape["faces"]:
				var polygon: PackedVector2Array = piece[0]
				var piece_level: int = piece[1]
				if not colors.has(piece_level):
					colors[piece_level] = _ground_color(terrain, biome, tile, float(piece_level), snowy)
				var y := piece_level * STEP_HEIGHT
				var a := Vector3(polygon[0].x * TILE_SIZE, y, polygon[0].y * TILE_SIZE)
				for k in range(1, polygon.size() - 1):
					ground.append([a, Vector3(polygon[k].x * TILE_SIZE, y, polygon[k].y * TILE_SIZE),
							Vector3(polygon[k + 1].x * TILE_SIZE, y, polygon[k + 1].y * TILE_SIZE),
							colors[piece_level], cliff, false])
			for line: Array in shape["cliffs"]:
				var top: int = line[2]
				var below: int = line[3]
				if not colors.has(top):
					colors[top] = _ground_color(terrain, biome, tile, float(top), snowy)
				var out: Vector2 = line[4]
				walls.append([(line[0] as Vector2) * TILE_SIZE, (line[1] as Vector2) * TILE_SIZE,
						top * STEP_HEIGHT, top * STEP_HEIGHT, below * STEP_HEIGHT, below * STEP_HEIGHT,
						Vector3(out.x, 0.0, out.y), face, colors[top]])


## A flat rectangle of ground from `from` to `to` (metres, x and z) at `level`.
static func _flat_strip(ground: Array, from: Vector2, to: Vector2, level: int, color: Color,
		cliff: Color) -> void:
	var y := level * STEP_HEIGHT
	var p0 := Vector3(from.x, y, from.y)
	var p2 := Vector3(to.x, y, to.y)
	ground.append([p0, Vector3(to.x, y, from.y), p2, color, cliff, false])
	ground.append([p0, p2, Vector3(from.x, y, to.y), color, cliff, false])


## The heights beyond half of a tile's edge, at its two ends, in metres -- or null where nothing
## needs a wall (the edge of the map, which the boundary cliffs stand against).
static func _beyond(terrain: TerrainData, x: int, z: int, side: int, half: int) -> Variant:
	var nx := x + NEIGHBOUR_DX[side]
	var nz := z + NEIGHBOUR_DZ[side]
	if not terrain.in_bounds(nx, nz):
		if terrain.side_levels[side] == TerrainData.MAP_EDGE:
			return null
		var beyond := terrain.edge_level(side, TerrainData.lane_of(side, x, z)) * STEP_HEIGHT
		## Where the river crosses into the next chunk, what lies beyond is its bed, a level
		## below that chunk's ground (and deeper still where the river is cut deep there).
		if terrain.water[z * terrain.size + x] == 1:
			beyond -= STEP_HEIGHT + terrain.side_sink[side]
		return Vector2(beyond, beyond)
	if terrain.is_hole(nx, nz):
		## A hole is bottomless: the wall drops far enough that no camera angle reveals the
		## underside of the world.
		return Vector2(VOID_DEPTH, VOID_DEPTH) * STEP_HEIGHT
	## The neighbour walks its edge the other way round, so its other half lies against this
	## one, and its right end against this one's left.
	var theirs := terrain.half_edge(nx, nz, (side + 2) % 4, 1 - half) * STEP_HEIGHT \
			- Vector2.ONE * terrain.sink_at(nx, nz)
	return Vector2(theirs.y, theirs.x)


## Whether a flat tile and its neighbour on `side` are flat dry ground at the same level, in
## which case no corner along their shared edge is reshaped and no wall stands on it.
static func _level_with(terrain: TerrainData, x: int, z: int, side: int) -> bool:
	var nx := x + NEIGHBOUR_DX[side]
	var nz := z + NEIGHBOUR_DZ[side]
	if not terrain.in_bounds(nx, nz):
		return false
	var mine := z * terrain.size + x
	var theirs := nz * terrain.size + nx
	return terrain.heights[mine] == terrain.heights[theirs] and terrain.heights[mine] != HOLE \
			and terrain.slopes[mine] == 0 and terrain.slopes[theirs] == 0 \
			and terrain.water[mine] == 0 and terrain.water[theirs] == 0


## Whether the old square mesher stood a wall on this side of the tile -- kept only so the
## random numbers are drawn exactly as before.
static func _old_wall_on(terrain: TerrainData, x: int, z: int, side: int) -> bool:
	var mine := terrain.edge(x, z, side)
	var nx := x + NEIGHBOUR_DX[side]
	var nz := z + NEIGHBOUR_DZ[side]
	var beyond_left := 0.0
	var beyond_right := 0.0
	if not terrain.in_bounds(nx, nz):
		if terrain.side_levels[side] == TerrainData.MAP_EDGE:
			return false
		var beyond := terrain.edge_level(side, TerrainData.lane_of(side, x, z))
		if terrain.water[z * terrain.size + x] == 1:
			beyond -= 1
		beyond_left = beyond
		beyond_right = beyond
	elif terrain.is_hole(nx, nz):
		beyond_left = VOID_DEPTH
		beyond_right = VOID_DEPTH
	else:
		var theirs := terrain.edge(nx, nz, (side + 2) % 4)
		beyond_left = theirs.y
		beyond_right = theirs.x
	return not (mine.x <= beyond_left + 0.01 and mine.y <= beyond_right + 0.01)


## The ledged stretches of cliff top among `walls`: every full-height drop whose top belongs to
## a ledged tile and whose foot is ground anyone can walk to. Found by looking either side of
## each wall, so the rounded and chamfered corners carry the ledge round with them.
static func _ledge_segments(terrain: TerrainData, walls: Array) -> Array:
	var found: Array = []
	if not terrain.ledge.has(1):
		return found
	for wall: Array in walls:
		var top: float = wall[2]
		var foot: float = wall[4]
		if not is_equal_approx(top, wall[3]) or not is_equal_approx(foot, wall[5]) \
				or top - foot < STEP_HEIGHT - 0.01:
			continue
		var a: Vector2 = wall[0]
		var b: Vector2 = wall[1]
		var outward := Vector2((wall[6] as Vector3).x, (wall[6] as Vector3).z)
		var middle := (a + b) * 0.5
		var high := _owner(terrain, (middle - outward * 0.1) / TILE_SIZE, roundi(top / STEP_HEIGHT))
		var low := _owner(terrain, (middle + outward * 0.1) / TILE_SIZE, roundi(foot / STEP_HEIGHT))
		if high < 0 or low < 0 or terrain.ledge[high] == 0:
			continue
		if terrain.reach[low] == 0 or terrain.deep[low] == 1 or terrain.water[low] == 1:
			continue
		found.append([a, b, top, -outward])
	return found


## The tile at a point (in tiles) whose ground is at `level` -- the tile itself, or, where the
## point is in a reshaped corner, the neighbour whose level that corner took. -1 if none.
static func _owner(terrain: TerrainData, at: Vector2, level: int) -> int:
	var x := floori(at.x)
	var z := floori(at.y)
	if not terrain.in_bounds(x, z):
		return -1
	if terrain.heights[z * terrain.size + x] == level:
		return z * terrain.size + x
	for side in 4:
		var nx := x + NEIGHBOUR_DX[side]
		var nz := z + NEIGHBOUR_DZ[side]
		if terrain.in_bounds(nx, nz) and terrain.heights[nz * terrain.size + nx] == level:
			return nz * terrain.size + nx
	return -1


## How far in from the cliff's edge a ledge's lip runs, and its width.
const LEDGE_INSET := 0.06
const LEDGE_WIDTH := 0.34
## How tall a lip stands, give or take LEDGE_RISE_VARY, and how much lower its rounded top's
## edges are than its crown.
const LEDGE_RISE := 0.36
const LEDGE_RISE_VARY := 0.07
const LEDGE_BEVEL := 0.07
## Rounds of corner cutting that smooth a lip's path (each doubles its points), and how much an
## open end tapers down over its last metre.
const LEDGE_SMOOTHING := 3
const LEDGE_TAPER := 0.3
## Height of the invisible wall over a lip: well over any jump or knockback's rise.
const LEDGE_WALL := 4.5


## The ledges' paths: the cliff-edge segments joined end to end into runs, each smoothed into a
## curve so a lip bends round a corner instead of being boxes overlapping there. Each path is
## [points: PackedVector2Array along the cliff's edge, in metres; normals: PackedVector2Array
## pointing inward, off the drop; y: float; closed: bool].
static func ledge_paths(segments: Array) -> Array:
	var paths: Array = []
	if segments.is_empty():
		return paths
	## Every segment turned to run with the plateau on its left, so runs join head to tail.
	var runs: Array = []
	var starting := {}
	for segment: Array in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var y: float = segment[2]
		var inward: Vector2 = segment[3]
		var along := b - a
		if Vector2(-along.y, along.x).dot(inward) < 0.0:
			var swap := a
			a = b
			b = swap
		starting[_key(Vector3(a.x, y, a.y))] = runs.size()
		runs.append([a, b, y])
	var used := PackedByteArray()
	used.resize(runs.size())
	var ending := {}
	for index in runs.size():
		var run: Array = runs[index]
		ending[_key(Vector3((run[1] as Vector2).x, run[2], (run[1] as Vector2).y))] = index
	for first in runs.size():
		if used[first] == 1:
			continue
		## Walk back to where this run starts (or all the way round a loop), then forward.
		var start := first
		var steps := 0
		while steps < runs.size():
			var run: Array = runs[start]
			var key := _key(Vector3((run[0] as Vector2).x, run[2], (run[0] as Vector2).y))
			if not ending.has(key) or used[ending[key]] == 1 or ending[key] == first:
				break
			start = ending[key]
			steps += 1
		var y: float = runs[start][2]
		var points := PackedVector2Array([runs[start][0]])
		var closed := false
		var at := start
		while true:
			used[at] = 1
			var end: Vector2 = runs[at][1]
			var key := _key(Vector3(end.x, y, end.y))
			var next: int = starting.get(key, -1)
			if next == start and points.size() > 2:
				closed = true
				break
			points.append(end)
			if next < 0 or used[next] == 1:
				break
			at = next
		points = _smooth_path(_drop_straight(points, closed), closed)
		if points.size() < 2:
			continue
		paths.append([points, _path_normals(points, closed), y, closed])
	return paths


## Drops the points in the middle of a straight stretch, which smoothing would only multiply.
static func _drop_straight(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var kept := PackedVector2Array()
	var count := points.size()
	for i in count:
		if (i == 0 or i == count - 1) and not closed:
			kept.append(points[i])
			continue
		var before := points[(i - 1 + count) % count]
		var after := points[(i + 1) % count]
		var turn := (points[i] - before).normalized().cross((after - points[i]).normalized())
		if absf(turn) > 0.01 or (points[i] - before).dot(after - points[i]) < 0.0:
			kept.append(points[i])
	return kept if kept.size() >= 2 else points


## Chaikin's corner cutting, which converges on a quadratic B-spline through the path. An open
## path keeps its two ends where they were so it still meets its gaps.
static func _smooth_path(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	## Long straight stretches would be cut back too far from their corners: split them first.
	var even := PackedVector2Array()
	var count := points.size()
	var spans := count if closed else count - 1
	for i in spans:
		var a := points[i]
		var b := points[(i + 1) % count]
		var pieces := maxi(1, ceili(a.distance_to(b) / 1.0))
		for piece in pieces:
			even.append(a.lerp(b, float(piece) / pieces))
	if not closed:
		even.append(points[count - 1])
	for round in LEDGE_SMOOTHING:
		var cut := PackedVector2Array()
		count = even.size()
		if not closed:
			cut.append(even[0])
		spans = count if closed else count - 1
		for i in spans:
			var a := even[i]
			var b := even[(i + 1) % count]
			cut.append(a.lerp(b, 0.25))
			cut.append(a.lerp(b, 0.75))
		if not closed:
			cut.append(even[count - 1])
		even = cut
	return even


## The inward normal at each point of a path: the plateau side, averaged across each bend.
static func _path_normals(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var normals := PackedVector2Array()
	var count := points.size()
	for i in count:
		var before := points[i] - points[(i - 1 + count) % count] if closed or i > 0 else Vector2.ZERO
		var after := points[(i + 1) % count] - points[i] if closed or i < count - 1 else Vector2.ZERO
		var normal := Vector2.ZERO
		if before != Vector2.ZERO:
			normal += Vector2(-before.y, before.x).normalized()
		if after != Vector2.ZERO:
			normal += Vector2(-after.y, after.x).normalized()
		normal = normal.normalized()
		## Pushed out at a bend so the offset edges stay parallel to the path.
		var single := Vector2(-after.y, after.x).normalized() if after != Vector2.ZERO \
				else Vector2(-before.y, before.x).normalized()
		normals.append(normal / maxf(0.5, normal.dot(single)))
	return normals


## The lips along the ledges: low stone kerbs following the cliff's edge in smooth curves,
## drawn with the terrain's own material (rock on their sides, the rim's dirt on top).
static func build_ledges(paths: Array, biome: BiomeData) -> ArrayMesh:
	if paths.is_empty():
		return null
	var rock := Season.cliff_color(biome.id, biome.cliff_color)
	rock.a = 0.0
	var ground: Array = []
	var walls: Array = []
	for path: Array in paths:
		var points: PackedVector2Array = path[0]
		var normals: PackedVector2Array = path[1]
		var y: float = path[2]
		var closed: bool = path[3]
		var count := points.size()
		## Distance along the path at each point, for the height's wander and the end's taper.
		var along := PackedFloat32Array([0.0])
		for i in range(1, count):
			along.append(along[i - 1] + points[i].distance_to(points[i - 1]))
		var length := along[count - 1]
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		var rises := PackedFloat32Array()
		for i in count:
			outer.append(points[i] + normals[i] * LEDGE_INSET)
			inner.append(points[i] + normals[i] * (LEDGE_INSET + LEDGE_WIDTH))
			var s := along[i]
			var rise := LEDGE_RISE + LEDGE_RISE_VARY * (sin(s * 1.7 + points[0].x) * 0.6 + sin(s * 4.3 + y) * 0.4)
			if not closed:
				var from_end := minf(s, length - s)
				rise *= lerpf(1.0 - LEDGE_TAPER, 1.0, smoothstep(0.0, 1.0, from_end))
			rises.append(rise)
		var shade := rock * (0.92 + 0.08 * absf(sin(points[0].x * 4.1 + points[0].y * 9.7)))
		shade.a = 0.0
		var spans := count if closed else count - 1
		for i in spans:
			var j := (i + 1) % count
			var crown_i := (outer[i] + inner[i]) * 0.5
			var crown_j := (outer[j] + inner[j]) * 0.5
			var top_i := y + rises[i]
			var top_j := y + rises[j]
			var edge_i := top_i - LEDGE_BEVEL
			var edge_j := top_j - LEDGE_BEVEL
			## The rounded top: two strips sloping up from each side to the crown.
			for side: Array in [[outer[i], outer[j]], [inner[i], inner[j]]]:
				var e_i := Vector3((side[0] as Vector2).x, edge_i, (side[0] as Vector2).y)
				var e_j := Vector3((side[1] as Vector2).x, edge_j, (side[1] as Vector2).y)
				var c_i := Vector3(crown_i.x, top_i, crown_i.y)
				var c_j := Vector3(crown_j.x, top_j, crown_j.y)
				ground.append([e_i, e_j, c_j, shade, rock, false])
				ground.append([e_i, c_j, c_i, shade, rock, false])
			var facing := points[j] - points[i]
			var out := Vector2(facing.y, -facing.x).normalized()
			var out3 := Vector3(out.x, 0.0, out.y)
			walls.append([outer[i], outer[j], edge_i, edge_j, y, y, out3, shade, shade])
			walls.append([inner[j], inner[i], edge_j, edge_i, y, y, -out3, shade, shade])
		if not closed:
			for end: int in [0, count - 1]:
				var tip := (points[1] - points[0]) if end == 0 else (points[end - 1] - points[end])
				var cap := -tip.normalized()
				var top := y + rises[end]
				var crown := (outer[end] + inner[end]) * 0.5
				var a := outer[end] if end == 0 else inner[end]
				var b := inner[end] if end == 0 else outer[end]
				walls.append([a, crown, top - LEDGE_BEVEL, top, y, y, Vector3(cap.x, 0.0, cap.y), shade, shade])
				walls.append([crown, b, top, top - LEDGE_BEVEL, y, y, Vector3(cap.x, 0.0, cap.y), shade, shade])
	return _commit(ground, walls)


## The invisible walls standing on the ledges' inner faces, for a StaticBody3D on LAYER_LEDGE.
static func ledge_shape(paths: Array) -> ConcavePolygonShape3D:
	if paths.is_empty():
		return null
	var faces := PackedVector3Array()
	for path: Array in paths:
		var points: PackedVector2Array = path[0]
		var normals: PackedVector2Array = path[1]
		var y: float = path[2]
		var count := points.size()
		var spans := count if path[3] else count - 1
		for i in spans:
			var a := points[i] + normals[i] * (LEDGE_INSET + LEDGE_WIDTH)
			var b := points[(i + 1) % count] + normals[(i + 1) % count] * (LEDGE_INSET + LEDGE_WIDTH)
			var low_a := Vector3(a.x, y - 0.5, a.y)
			var low_b := Vector3(b.x, y - 0.5, b.y)
			var high_a := Vector3(a.x, y + LEDGE_WALL, a.y)
			var high_b := Vector3(b.x, y + LEDGE_WALL, b.y)
			faces.append_array([low_a, high_a, high_b, low_a, high_b, low_b])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return shape


## Writes out the ground triangles and wall quads, marking each ground vertex that sits on a
## wall's lip or at its foot so the shader can blend the edge.
static func _commit(ground: Array, walls: Array, paint: GroundPaint = null) -> ArrayMesh:
	var lips := {}
	var feet := {}
	for wall: Array in walls:
		for end in 2:
			var at: Vector2 = wall[end]
			var top: float = wall[2 + end]
			var foot: float = wall[4 + end]
			if top - foot < 0.01:
				continue
			lips[_key(Vector3(at.x, top, at.y))] = true
			if foot > VOID_DEPTH * STEP_HEIGHT + 0.01:
				feet[_key(Vector3(at.x, foot, at.y))] = true

	## Straight into arrays rather than through SurfaceTool, which is several times slower at
	## this many vertices.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var others := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	for tri: Array in ground:
		var color: Color = tri[3]
		var other: Color = tri[4]
		## Which tile's ground the triangle is, for the paint: the one under its middle.
		var tile := Vector2i.ZERO
		if paint != null:
			var middle := ((tri[0] as Vector3) + (tri[1] as Vector3) + (tri[2] as Vector3)) / 3.0
			tile = Vector2i(floori(middle.x / TILE_SIZE), floori(middle.z / TILE_SIZE))
		if tri.size() > 6 and tri[6] is bool:
			## A plain tile's quad, already facing up and nowhere near an edge.
			for i in 3:
				vertices.append(tri[i])
				normals.append(Vector3.UP)
				var here := color
				var beside := other
				if paint != null:
					here = paint.tint(color, tri[i], GroundPaint.Kind.GROUND, tile)
					beside = paint.tint(other, tri[i], GroundPaint.Kind.CLIFF, tile)
				colors.append(here)
				others.append(beside.r)
				others.append(beside.g)
				others.append(beside.b)
				others.append(beside.a)
				uvs.append(Vector2.ZERO)
				uv2s.append(Vector2.ZERO)
			continue
		var points: Array[Vector3] = [tri[0], tri[1], tri[2]]
		## Ground faces up, unless it says otherwise (the underside of a land bridge's arch).
		var normal := _wind(points, tri[6] if tri.size() > 6 else Vector3.UP)
		var ramp := Vector2(1.0 if tri[5] else 0.0, 0.0)
		for point in points:
			var key := _key(point)
			vertices.append(point)
			normals.append(normal)
			var here := color
			var beside := other
			if paint != null:
				here = paint.tint(color, point, GroundPaint.Kind.GROUND, tile)
				beside = paint.tint(other, point, GroundPaint.Kind.CLIFF, tile)
			colors.append(here)
			others.append(beside.r)
			others.append(beside.g)
			others.append(beside.b)
			others.append(beside.a)
			uvs.append(Vector2(1.0 if lips.has(key) else 0.0, 1.0 if feet.has(key) else 0.0))
			uv2s.append(ramp)
	for wall: Array in walls:
		var a: Vector2 = wall[0]
		var b: Vector2 = wall[1]
		var outward: Vector3 = wall[6]
		var direction := (b - a).normalized()
		## Corners: top of a, top of b, foot of b, foot of a. Each carries how far along the wall
		## it is, its height above the foot and its depth below the lip.
		var corners: Array = [
			[Vector3(a.x, wall[2], a.y), a.dot(direction), wall[2] - wall[4], 0.0],
			[Vector3(b.x, wall[3], b.y), b.dot(direction), wall[3] - wall[5], 0.0],
			[Vector3(b.x, wall[5], b.y), b.dot(direction), 0.0, wall[3] - wall[5]],
			[Vector3(a.x, wall[4], a.y), a.dot(direction), 0.0, wall[2] - wall[4]],
		]
		for triangle in [[0, 1, 2], [0, 2, 3]]:
			var picked: Array = [corners[triangle[0]], corners[triangle[1]], corners[triangle[2]]]
			var p0: Vector3 = picked[0][0]
			var cross := ((picked[1][0] as Vector3) - p0).cross((picked[2][0] as Vector3) - p0)
			if cross.length_squared() < 0.000001:
				continue
			if cross.dot(outward) > 0.0:
				picked = [picked[0], picked[2], picked[1]]
			var face: Color = wall[7]
			var top: Color = wall[8]
			## A cliff is coloured as the ground on top of it.
			var owner := Vector2i.ZERO
			if paint != null:
				var inside := (a + b) * 0.5 - Vector2(outward.x, outward.z) * 0.3
				owner = Vector2i(floori(inside.x / TILE_SIZE), floori(inside.y / TILE_SIZE))
			for corner: Array in picked:
				vertices.append(corner[0])
				normals.append(outward)
				var here := face
				var above := top
				if paint != null:
					here = paint.tint(face, corner[0], GroundPaint.Kind.CLIFF, owner)
					var lip := corner[0] as Vector3
					lip.y = maxf(wall[2], wall[3])
					above = paint.tint(top, lip, GroundPaint.Kind.GROUND, owner)
				colors.append(here)
				others.append(above.r)
				others.append(above.g)
				others.append(above.b)
				others.append(above.a)
				uvs.append(Vector2(corner[1], corner[2]))
				uv2s.append(Vector2(corner[3], 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_CUSTOM0] = others
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return mesh


## Puts a ground triangle's points in the winding Godot draws as the front face when seen from
## the side `facing` points to, and returns its normal.
static func _wind(points: Array[Vector3], facing: Vector3) -> Vector3:
	var cross := (points[1] - points[0]).cross(points[2] - points[0])
	if cross.dot(facing) > 0.0:
		var swap := points[1]
		points[1] = points[2]
		points[2] = swap
		cross = -cross
	return (-cross).normalized()


static func _key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * 64.0), roundi(point.y * 64.0), roundi(point.z * 64.0))


## Cliff faces down the chunk's own edge, from wherever its rim stands above the next chunk's
## ground level -- the mountain, where it spills across the border -- down to that level. Hidden
## under the next chunk's ground while that is drawn; while it is not (it is too far away), they
## close off what would otherwise be an open edge with the sky showing under it. For a mesh with
## no collider: the next chunk's ground is what is walked on there.
static func build_skirts(terrain: TerrainData, biome: BiomeData) -> ArrayMesh:
	var size := terrain.size
	var cliff := Season.cliff_color(biome.id, biome.cliff_color)
	cliff.a = 0.0
	var walls: Array = []
	for side in 4:
		var below: int = terrain.side_levels[side]
		if below == TerrainData.MAP_EDGE:
			continue
		var out := Vector2(NEIGHBOUR_DX[side], NEIGHBOUR_DZ[side])
		var along := Vector2(-out.y, out.x)
		for lane in size:
			var tile := WorldGenerator._from_side(size, side, 0, lane)
			if terrain.is_hole(tile.x, tile.y) or terrain.is_water(tile.x, tile.y):
				continue
			var top := mini(terrain.level(tile.x, tile.y), terrain.edge_level(side, lane))
			if top <= below:
				continue
			var middle := (Vector2(tile) + Vector2(0.5, 0.5) + out * 0.5) * TILE_SIZE
			var a := middle - along * TILE_SIZE * 0.5
			var b := middle + along * TILE_SIZE * 0.5
			walls.append([a, b, top * STEP_HEIGHT, top * STEP_HEIGHT, below * STEP_HEIGHT,
					below * STEP_HEIGHT, Vector3(out.x, 0.0, out.y), cliff, cliff])
	if walls.is_empty():
		return null
	return _commit([], walls)


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


## One material for all the ground in the match, so SnowTrails can hand every chunk the same
## track texture by setting it once.
static var _material: ShaderMaterial


static func make_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = ComicLook.shader_for(preload("res://scripts/world/terrain.gdshader"))
		if ComicLook.enabled:
			## Flat ground is all rim at a low angle: the rim light is for figures.
			_material.set_shader_parameter("rim_strength_comic", 0.0)
	return _material


static func _quad(surface: SurfaceTool, color: Color, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	for vertex in [a, b, c, a, c, d]:
		surface.set_color(color)
		surface.add_vertex(vertex)

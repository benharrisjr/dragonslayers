class_name TerrainData
extends RefCounted

## One chunk's ground: a level per tile, plus which tiles are slopes.
##
## Terrain is still stepped plateaus, but a player without the feather cannot jump, so a single
## 1.5 m step is a wall to them. Slopes are what join the plateaus up. A tile is either flat, a
## ramp rising one level towards one side, or "smooth" -- a shore tile whose corners rise to meet
## whatever sits one level above it, which is what lets a beach curve.
##
## Everything that needs to know the real shape of the ground -- the mesher, prop placement, the
## walkability check -- reads corner heights from here, so they cannot disagree about it.

enum Slope { FLAT, RISE_PX, RISE_PZ, RISE_NX, RISE_NZ, SMOOTH }

## A side with no chunk beyond it: the edge of the map.
const MAP_EDGE := -1000

var size: int = 0
## Row-major tile levels. ChunkMesher.HOLE marks a pit.
var heights: PackedInt32Array
var slopes: PackedByteArray
## Tiles kept clear of props, monsters and chests: ramps and the landings at either end.
var reserved: PackedByteArray
## Tiles a player can reach from the chunk's rim by walking alone -- no jump, no hookshot.
var reach: PackedByteArray
## The river (RiverCarver). `water` marks its tiles, whose level is the river bed; `bridge` marks
## the water tiles a bridge spans, holding how many levels above the bed its deck is (bridge_lift); `flow` is the way the water
## runs on each. `bridges` lists each bridge: {"from", "to" (tile corners, inclusive), "level"
## (its deck), "along_x" (which way it is walked)}.
var water: PackedByteArray
var bridge: PackedByteArray
var flow: PackedVector2Array
var bridges: Array[Dictionary] = []
## Still water too deep to stand in -- the lake's middle and the sea past the shallows. A body
## that goes down into it is fished out like one swept away by the river. `still_surface` is the
## height of that water in metres, or -INF where the chunk has none.
var deep: PackedByteArray
var still_surface: float = -INF
## Tiles whose cliff tops carry a ledge: a stone lip with an invisible wall over it, so nobody
## walks, jumps or is knocked off there (WorldGenerator._mark_ledges, ChunkMesher.build).
var ledge: PackedByteArray
## The desert dungeon's stairwell, in tiles (WorldGenerator._carve_stairwell); empty elsewhere.
var stairwell := Rect2i()
## The level this chunk's rim sits at, which is also its tier's ground level.
var base_level: int = 0
## Ground level of the chunk beyond each side (+x, +z, -x, -z), or MAP_EDGE.
var side_levels: PackedInt32Array = PackedInt32Array([MAP_EDGE, MAP_EDGE, MAP_EDGE, MAP_EDGE])
## The level of the tile just beyond each side, lane by lane (a side's lanes run along it, x for
## the z sides and z for the x sides): the next chunk's ground level, except where the mountain
## spills across the border. Empty means side_levels all along.
var edge_levels: Array[PackedInt32Array] = []
## How much deeper than usual the river runs here, in metres: its bed and water are this far
## lower than their levels say (WorldGenerator.RIVER_SINK), tile by tile. `side_sink` is the same for the
## river in the chunk beyond each side.
var sinks := PackedFloat32Array()
var side_sink := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## Ways across that the ground alone does not show -- a bridge between two bluffs, over open
## ground -- as (x, z) of the tile at one end and (x, z) of the tile at the other.
var spans: Array[Vector4i] = []
## Per tile: 0, or 1 + the index of the chunk whose ground this is -- the mountain, or a higher
## chunk spilling over the border -- so it is coloured as that chunk (GroundPaint).
var owner: PackedByteArray
## How the ground is coloured, blended across borders; null without a map round the chunk.
var paint: GroundPaint
## Per tile: 1 where one of the map's paths runs (PathNetwork), which scenery keeps off.
## `lake_shape` is the lake's outline, where the chunk has one (WorldGenerator.lake_scale); empty elsewhere.
var path: PackedByteArray
## The ramps carved up to higher chunks: {"side", "start" (lane), "length"}.
var ramps: Array[Dictionary] = []
var lake_shape := PackedFloat32Array()
## Where the chunk sits in a lake that fills two chunks (WorldGenerator._frame_lake); empty for a
## lake of one.
var lake_frame: Dictionary = {}

## How cliffs are drawn: smoothed, so they come out as curves rather than square tile steps.
##
## For each level, take "is this tile at least that high" -- 1 or 0 per tile -- and blur it with a
## quadratic B-spline over the 3x3 tiles round each point. The cliff up to that level is drawn
## where the blurred value crosses one half, traced on a lattice of SUB points per tile (marching
## squares). A straight cliff, a one-tile ridge and a one-tile gap all stay exactly on their tile
## edges; corners round off with a radius of about four fifths of a tile, a diagonal staircase
## becomes one sloping line, and a notch a gentle wave.
##
## Only flat ground takes part (smooths). Next to a ramp, a shore, a pit, the river, a reserved
## tile or the chunk's edge, the lattice takes the plain tile values instead, so the ground meets
## those square, exactly where their own geometry does.
##
## This is the drawn ground only. Who can walk where is still decided tile by tile (can_walk).
const SUB := 4

## Four corner heights per tile, in levels: (x,z), (x+1,z), (x+1,z+1), (x,z+1).
var _corners: PackedFloat32Array


func _init(tile_count: int = 0, base: int = 0) -> void:
	size = tile_count
	base_level = base
	heights.resize(size * size)
	heights.fill(base)
	slopes.resize(size * size)
	reserved.resize(size * size)
	reach.resize(size * size)
	water.resize(size * size)
	bridge.resize(size * size)
	flow.resize(size * size)
	deep.resize(size * size)
	ledge.resize(size * size)
	owner.resize(size * size)
	sinks.resize(size * size)
	path.resize(size * size)


func level(x: int, z: int) -> int:
	return heights[z * size + x]


func is_hole(x: int, z: int) -> bool:
	return heights[z * size + x] == ChunkMesher.HOLE


func is_water(x: int, z: int) -> bool:
	return in_bounds(x, z) and water[z * size + x] == 1


func is_bridge(x: int, z: int) -> bool:
	return in_bounds(x, z) and bridge[z * size + x] > 0


## How many levels above the river bed a bridge's deck is: 1 for a plank bridge, level with its
## banks; more for a land bridge, which arches high enough for a raft to pass under. 0 off one.
func bridge_lift(x: int, z: int) -> int:
	return bridge[z * size + x] if in_bounds(x, z) else 0


func is_deep(x: int, z: int) -> bool:
	return in_bounds(x, z) and deep[z * size + x] == 1


## Whether a body standing here could be in trouble: a pit, the river (off its bridges) or deep
## still water.
func is_hazard(x: int, z: int) -> bool:
	return is_hole(x, z) or (is_water(x, z) and not is_bridge(x, z)) or is_deep(x, z)


## Where the water's surface is on a river tile, in metres: a little below its banks.
func water_surface(x: int, z: int) -> float:
	return (heights[z * size + x] + 1) * ChunkMesher.STEP_HEIGHT - WorldGenerator.RIVER_SURFACE_DROP \
			- sink_at(x, z)


## How far below its level a tile's ground is drawn, in metres: the river's extra depth on its
## tiles, nothing anywhere else.
func sink_at(x: int, z: int) -> float:
	return sinks[z * size + x] if is_water(x, z) else 0.0


## The level of the tile beyond `side` at `lane` (see edge_levels).
func edge_level(side: int, lane: int) -> int:
	if edge_levels.is_empty():
		return side_levels[side]
	return edge_levels[side][clampi(lane, 0, size - 1)]


## Which lane of `side` a tile on it is in.
static func lane_of(side: int, x: int, z: int) -> int:
	return z if side % 2 == 0 else x


func is_slope(x: int, z: int) -> bool:
	return slopes[z * size + x] != Slope.FLAT


func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < size and z < size


## Distance in tiles from the nearest chunk edge; 0 on the outermost ring.
func rim(x: int, z: int) -> int:
	return mini(mini(x, z), mini(size - 1 - x, size - 1 - z))


## Works out every tile's corner heights. Call once the levels and slopes are final.
func bake() -> void:
	_lattice_levels.clear()
	_lattice_points.clear()
	_smooth_tiles.clear()
	_corners.resize(size * size * 4)
	for z in size:
		for x in size:
			var index := z * size + x
			var own := heights[index]
			var c0 := float(own)
			var c1 := c0
			var c2 := c0
			var c3 := c0
			match slopes[index]:
				Slope.RISE_PX:
					c1 += 1.0
					c2 += 1.0
				Slope.RISE_PZ:
					c2 += 1.0
					c3 += 1.0
				Slope.RISE_NX:
					c0 += 1.0
					c3 += 1.0
				Slope.RISE_NZ:
					c0 += 1.0
					c1 += 1.0
				Slope.SMOOTH:
					c0 = _smooth_corner(x, z, own)
					c1 = _smooth_corner(x + 1, z, own)
					c2 = _smooth_corner(x + 1, z + 1, own)
					c3 = _smooth_corner(x, z + 1, own)
			_corners[index * 4] = c0
			_corners[index * 4 + 1] = c1
			_corners[index * 4 + 2] = c2
			_corners[index * 4 + 3] = c3


## Whether a tile takes part in the smoothing: plain flat ground. Ramps, shores, pits, the river
## and reserved tiles (ramp landings, the desert stairwell, bridge ends) keep square edges, since
## the way onto a ramp has to stay exactly as wide as the generator made it.
func smooths(x: int, z: int) -> bool:
	if not in_bounds(x, z):
		return false
	var index := z * size + x
	return slopes[index] == Slope.FLAT and heights[index] != ChunkMesher.HOLE \
			and water[index] == 0 and bridge[index] == 0 and reserved[index] == 0


## The quadratic B-spline the tile values are blurred with, `u` tiles from a tile's middle.
static func _spline(u: float) -> float:
	u = absf(u)
	if u <= 0.5:
		return 0.75 - u * u
	if u < 1.5:
		return 0.5 * (1.5 - u) * (1.5 - u)
	return 0.0


## What the ground at lattice point (px, pz) -- in SUB-ths of a tile from the chunk's corner -- is
## made of: [levels, weights], the tiles that count there and how much. Blurred over the tiles
## round it where they all smooth. Otherwise only the highest of the smoothing tiles it lies in (or
## on) counts, at exactly a half, so the point is that high and the cliff runs exactly through it: square, as the ramp or the river beside it is. Both are worked out from the point
## alone, so every tile that shares it agrees.
func lattice(px: int, pz: int) -> Array:
	var width := size * SUB + 1
	if _lattice_points.size() != width * width:
		_lattice_points.clear()
		_lattice_points.resize(width * width)
	var at := pz * width + px
	if _lattice_points[at] != null:
		return _lattice_points[at]
	var count := _gather(px, pz)
	var levels := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in count:
		levels.append(_gather_levels[i])
		weights.append(_gather_weights[i])
	var point := [levels, weights]
	_lattice_points[at] = point
	return point


## The level drawn at lattice point (px, pz), worked out once and kept.
func lattice_level_at(px: int, pz: int) -> int:
	var width := size * SUB + 1
	if _lattice_levels.size() != width * width:
		_lattice_levels.resize(width * width)
		_lattice_levels.fill(UNSET)
	var at := pz * width + px
	var level := _lattice_levels[at]
	if level != UNSET:
		return level
	var count := _gather(px, pz)
	level = _gather_levels[0] if count > 0 else ChunkMesher.HOLE
	var mixed := false
	for i in range(1, count):
		if _gather_levels[i] != level:
			mixed = true
			break
	if mixed:
		level = ChunkMesher.HOLE
		for i in count:
			var candidate := _gather_levels[i]
			if candidate <= level:
				continue
			var total := 0.0
			for j in count:
				if _gather_levels[j] >= candidate:
					total += _gather_weights[j]
			if total >= 0.5:
				level = candidate
	_lattice_levels[at] = level
	return level


const UNSET := -100000
var _lattice_levels := PackedInt32Array()
var _lattice_points: Array = []
var _smooth_tiles := PackedByteArray()
var _gather_levels := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
var _gather_weights := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
## The blur's weight for the tile `d` (-1, 0 or 1) along from the one a lattice point is in, at
## each of the SUB places it can be in that tile: WEIGHTS[place * 3 + d + 1].
static var _weights := PackedFloat32Array()


## Fills the gather arrays with what counts at lattice point (px, pz) (see lattice) and returns how
## many there are.
func _gather(px: int, pz: int) -> int:
	if _weights.is_empty():
		for place in SUB:
			for d in [-1, 0, 1]:
				_weights.append(_spline(float(place) / SUB - d - 0.5))
	if _smooth_tiles.size() != size * size:
		_smooth_tiles.resize(size * size)
		for z in size:
			for x in size:
				_smooth_tiles[z * size + x] = 1 if smooths(x, z) else 0
	var bx := px / SUB
	var bz := pz / SUB
	var ox := (px % SUB) * 3
	var oz := (pz % SUB) * 3
	var count := 0
	var blurred := true
	for dz in 3:
		var wz := _weights[oz + dz]
		if wz <= 0.0:
			continue
		var tz := bz + dz - 1
		for dx in 3:
			var wx := _weights[ox + dx]
			if wx <= 0.0:
				continue
			var tx := bx + dx - 1
			if tx < 0 or tz < 0 or tx >= size or tz >= size or _smooth_tiles[tz * size + tx] == 0:
				blurred = false
				break
			_gather_levels[count] = heights[tz * size + tx]
			_gather_weights[count] = wx * wz
			count += 1
		if not blurred:
			break
	if blurred:
		return count
	count = 0
	for tz in ([bz - 1, bz] if pz % SUB == 0 else [bz]):
		for tx in ([bx - 1, bx] if px % SUB == 0 else [bx]):
			if tx >= 0 and tz >= 0 and tx < size and tz < size and _smooth_tiles[tz * size + tx] == 1:
				## Only the highest, at exactly a half: more would push the cliff off the point.
				_gather_levels[0] = maxi(heights[tz * size + tx], _gather_levels[0]) if count > 0 \
						else heights[tz * size + tx]
				_gather_weights[0] = 0.5
				count = 1
	return count


## How much of a lattice point is at least `level` high, 0 to 1.
static func lattice_value(point: Array, level: int) -> float:
	var levels: PackedInt32Array = point[0]
	var weights: PackedFloat32Array = point[1]
	var total := 0.0
	for i in levels.size():
		if levels[i] >= level:
			total += weights[i]
	return total


## The level drawn at a lattice point: the highest whose value there is at least a half.
static func lattice_level(point: Array) -> int:
	var levels: PackedInt32Array = point[0]
	var best := ChunkMesher.HOLE
	for level in levels:
		if level > best and lattice_value(point, level) >= 0.5:
			best = level
	return best


## The drawn ground in one lattice cell, from its four corner points (in boundary order: (x0,z0),
## (x1,z0), (x1,z1), (x0,z1)) and their positions. Returns {"faces": [[PackedVector2Array, level]]}
## -- the cell cut into convex pieces, each flat at its level -- and "cliffs": [[a, b, top, below,
## outward]], the line each cliff runs along in it and which way it faces.
##
## Each level between the lowest and highest corner is a threshold, its cliff where the corner
## values interpolated along the cell's edges cross a half; levels whose values are the same at
## all four corners trace the same line and are taken together. The lines are joined edge to edge
## into chords and the cell walked round, turning in along each chord, to find the pieces.
static func cell_shape(points: Array, corners: Array[Vector2]) -> Dictionary:
	var drawn := PackedInt32Array()
	for point: Array in points:
		drawn.append(lattice_level(point))
	var lo := mini(mini(drawn[0], drawn[1]), mini(drawn[2], drawn[3]))
	var hi := maxi(maxi(drawn[0], drawn[1]), maxi(drawn[2], drawn[3]))
	if lo == hi:
		return {"faces": [[PackedVector2Array(corners), lo]], "cliffs": []}
	var levels := PackedInt32Array()
	for point: Array in points:
		for level in (point[0] as PackedInt32Array):
			if level > lo and level <= hi and not levels.has(level):
				levels.append(level)
	levels.sort()
	if levels.size() == 1:
		var simple := _one_cliff(points, corners, levels[0], lo)
		if not simple.is_empty():
			return simple
	## Thresholds, lowest first, as [top level, level below it, corner values].
	var groups: Array = []
	for level: int in levels:
		var values := PackedFloat32Array()
		for point: Array in points:
			values.append(lattice_value(point, level))
		if not groups.is_empty() and groups[-1][2] == values:
			groups[-1][0] = level
		else:
			groups.append([level, lo if groups.is_empty() else groups[-1][0], values])

	## Round the boundary: each corner, then the crossings along the edge after it.
	var nodes: Array = []
	for edge in 4:
		var next := (edge + 1) % 4
		nodes.append([corners[edge], -1, edge, 0.0])
		var crossings: Array = []
		for g in groups.size():
			var values: PackedFloat32Array = groups[g][2]
			var a := values[edge]
			var b := values[next]
			if (a >= 0.5) == (b >= 0.5):
				continue
			var t := (0.5 - a) / (b - a)
			## Higher thresholds lie nearer the inside end; ties kept in that order.
			crossings.append([t, g if a < 0.5 else -g, g])
		if crossings.size() > 1:
			crossings.sort_custom(func(p: Array, q: Array) -> bool:
					return p[0] < q[0] or (p[0] == q[0] and p[1] < q[1]))
		for crossing: Array in crossings:
			nodes.append([corners[edge].lerp(corners[next], crossing[0]), crossing[2], edge, crossing[0]])
	var count := nodes.size()
	## The level of the boundary after each node: the highest threshold it is inside. Kept by
	## stepping in or out at each crossing, as several can fall on one point.
	var after_node := PackedInt32Array()
	var within := PackedByteArray()
	within.resize(groups.size())
	for node: Array in nodes:
		if node[1] < 0:
			for g in groups.size():
				within[g] = 1 if (groups[g][2] as PackedFloat32Array)[node[2]] >= 0.5 else 0
		else:
			within[node[1]] = 1 - within[node[1]]
		var level := lo
		for g in groups.size():
			if within[g] == 1:
				level = groups[g][0]
		after_node.append(level)
	## Each threshold's crossings paired into chords: one, or across a saddle, two -- cutting off
	## the corners outside it if the middle of the cell is inside, the corners inside it if not.
	var partner := PackedInt32Array()
	partner.resize(count)
	partner.fill(-1)
	var cliffs: Array = []
	var middle := (corners[0] + corners[2]) * 0.5
	for g in groups.size():
		var own: Array[int] = []
		for i in count:
			if nodes[i][1] == g:
				own.append(i)
		var values: PackedFloat32Array = groups[g][2]
		var pairs: Array = []
		var outside_of: Array = []
		if own.size() == 2:
			pairs.append([own[0], own[1]])
			var outside := corners[0]
			for c in 4:
				if values[c] < 0.5:
					outside = corners[c]
			outside_of.append(outside)
		elif own.size() == 4:
			var centre_in := (values[0] + values[1] + values[2] + values[3]) * 0.25 >= 0.5
			for c in 4:
				if (values[c] >= 0.5) == centre_in:
					continue
				## The crossings either side of corner c: the last on the edge before it and the
				## first on the edge after it.
				var before := -1
				var after := -1
				for i: int in own:
					if nodes[i][2] == (c + 3) % 4:
						before = i
					elif nodes[i][2] == c and after < 0:
						after = i
				pairs.append([before, after])
				## A corner outside it is cut off towards that corner; one inside, away from it.
				outside_of.append(corners[c] if centre_in else corners[c] + (middle - corners[c]) * 8.0)
		for k in pairs.size():
			var pair: Array = pairs[k]
			if pair[0] < 0 or pair[1] < 0:
				continue
			partner[pair[0]] = pair[1]
			partner[pair[1]] = pair[0]
			var a: Vector2 = nodes[pair[0]][0]
			var b: Vector2 = nodes[pair[1]][0]
			if a.distance_squared_to(b) < 0.0000001:
				continue
			var along := b - a
			var out := Vector2(along.y, -along.x).normalized()
			if out.dot((outside_of[k] as Vector2) - (a + b) * 0.5) < 0.0:
				out = -out
			cliffs.append([a, b, groups[g][0], groups[g][1], out])

	## Walk the pieces: along the boundary, in along a chord at each crossing, on round from its
	## other end. Each piece's level is that of the boundary it starts on.
	var faces: Array = []
	var used := PackedByteArray()
	used.resize(count)
	for start in count:
		if used[start] == 1:
			continue
		var polygon := PackedVector2Array()
		var at := start
		var guard := 0
		while guard < count * 2:
			guard += 1
			used[at] = 1
			polygon.append(nodes[at][0])
			var next := (at + 1) % count
			if nodes[next][1] >= 0 and partner[next] >= 0:
				polygon.append(nodes[next][0])
				at = partner[next]
			else:
				at = next
			if at == start:
				break
		if _area(polygon) > 0.000001:
			faces.append([polygon, after_node[start]])
	return {"faces": faces, "cliffs": cliffs}


## The commonest cell, quickly: one cliff, from `lo` up to `level`, crossing it once (no saddle).
## {} if it is not that simple.
static func _one_cliff(points: Array, corners: Array[Vector2], level: int, lo: int) -> Dictionary:
	var values := PackedFloat32Array()
	var inside := 0
	for point: Array in points:
		var value := lattice_value(point, level)
		values.append(value)
		if value >= 0.5:
			inside += 1
	if inside == 2 and (values[0] >= 0.5) == (values[2] >= 0.5):
		return {}
	var high := PackedVector2Array()
	var low := PackedVector2Array()
	var cut: Array[Vector2] = []
	var outside := corners[0]
	for c in 4:
		var next := (c + 1) % 4
		if values[c] >= 0.5:
			high.append(corners[c])
		else:
			low.append(corners[c])
			outside = corners[c]
		if (values[c] >= 0.5) != (values[next] >= 0.5):
			var at := corners[c].lerp(corners[next], (0.5 - values[c]) / (values[next] - values[c]))
			high.append(at)
			low.append(at)
			cut.append(at)
	var faces: Array = []
	if _area(high) > 0.000001:
		faces.append([high, level])
	if _area(low) > 0.000001:
		faces.append([low, lo])
	var cliffs: Array = []
	if cut.size() == 2 and cut[0].distance_squared_to(cut[1]) >= 0.0000001:
		var along := cut[1] - cut[0]
		var out := Vector2(along.y, -along.x).normalized()
		if out.dot(outside - (cut[0] + cut[1]) * 0.5) < 0.0:
			out = -out
		cliffs.append([cut[0], cut[1], level, lo, out])
	return {"faces": faces, "cliffs": cliffs}


static func _area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i in polygon.size():
		total += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(total) * 0.5


## The lattice points and corner positions (in tiles) of the cell at lattice (cx, cz).
func cell_at(cx: int, cz: int) -> Array:
	var points: Array = [lattice(cx, cz), lattice(cx + 1, cz), lattice(cx + 1, cz + 1), lattice(cx, cz + 1)]
	var step := 1.0 / SUB
	var corners: Array[Vector2] = [Vector2(cx, cz) * step, Vector2(cx + 1, cz) * step,
			Vector2(cx + 1, cz + 1) * step, Vector2(cx, cz + 1) * step]
	return [points, corners]


## Whether a flat tile is drawn as it stands: nothing different round it to smooth against.
func is_plain(x: int, z: int) -> bool:
	var own := heights[z * size + x]
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if in_bounds(x + dx, z + dz) and heights[(z + dz) * size + x + dx] != own:
				return false
	return true


## The ground's height in levels at a point given in tiles from the chunk's corner (fractions
## included) -- reshaped corners and the slope of a ramp taken into account, matching the mesh.
func surface_at(tx: float, tz: float) -> float:
	var x := clampi(floori(tx), 0, size - 1)
	var z := clampi(floori(tz), 0, size - 1)
	var u := clampf(tx - x, 0.0, 1.0)
	var v := clampf(tz - z, 0.0, 1.0)
	var index := z * size + x
	if heights[index] == ChunkMesher.HOLE:
		return float(ChunkMesher.HOLE)
	if water[index] == 1:
		return float(heights[index]) - sinks[index] / ChunkMesher.STEP_HEIGHT
	var at := index * 4
	if slopes[index] != Slope.FLAT:
		## The same two triangles the mesher draws, split from corner 0 to corner 2.
		if u >= v:
			return _corners[at] + (_corners[at + 1] - _corners[at]) * u \
					+ (_corners[at + 2] - _corners[at + 1]) * v
		return _corners[at] + (_corners[at + 3] - _corners[at]) * v \
				+ (_corners[at + 2] - _corners[at + 3]) * u
	if not smooths(x, z) or is_plain(x, z):
		return float(heights[index])
	## The lattice cell it is in, and the highest piece of it that holds the point.
	var cx := mini(floori(tx * SUB), size * SUB - 1)
	var cz := mini(floori(tz * SUB), size * SUB - 1)
	var flat := lattice_level_at(cx, cz)
	if lattice_level_at(cx + 1, cz) == flat and lattice_level_at(cx + 1, cz + 1) == flat \
			and lattice_level_at(cx, cz + 1) == flat:
		return float(flat)
	var cell := cell_at(cx, cz)
	var shape := cell_shape(cell[0], cell[1])
	var point := Vector2(tx, tz)
	var best := -INF
	for face: Array in shape["faces"]:
		if _holds(face[0], point):
			best = maxf(best, float(face[1]))
	if best > -INF:
		return best
	return float(heights[index])


## The heights at the two ends of one half of a tile's edge, in levels, walking the same way as
## edge(): half 0 runs from the edge's left end to its middle, half 1 from the middle on.
func half_edge(x: int, z: int, side: int, half: int) -> Vector2:
	var whole := edge(x, z, side)
	var middle := (whole.x + whole.y) * 0.5
	return Vector2(whole.x, middle) if half == 0 else Vector2(middle, whole.y)


## Whether a convex polygon holds a point, its edge included.
static func _holds(polygon: PackedVector2Array, point: Vector2) -> bool:
	var turn := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var cross := (b - a).cross(point - a)
		if absf(cross) < 0.000001:
			continue
		if turn == 0.0:
			turn = signf(cross)
		elif signf(cross) != turn:
			return false
	return true


## A smooth tile's corner rises one level if any of the four tiles meeting there is one level
## up. Every tile around that corner at the lower level is smooth too (the generator flags them
## together), so they all agree on the corner and the surface has no cracks.
func _smooth_corner(cx: int, cz: int, own: int) -> float:
	for dz in [-1, 0]:
		for dx in [-1, 0]:
			var x: int = cx + dx
			var z: int = cz + dz
			if in_bounds(x, z) and heights[z * size + x] == own + 1:
				return float(own + 1)
	return float(own)


func corner(x: int, z: int, which: int) -> float:
	return _corners[(z * size + x) * 4 + which]


## Height of a tile's middle, in levels. Half way up a ramp tile is half a level.
func surface_level(x: int, z: int) -> float:
	var at := (z * size + x) * 4
	return (_corners[at] + _corners[at + 1] + _corners[at + 2] + _corners[at + 3]) * 0.25


## The two ends of a tile's edge on `side`, in levels, walking clockwise seen from above:
## x is the end the mesher calls "left", y the "right".
func edge(x: int, z: int, side: int) -> Vector2:
	var at := (z * size + x) * 4
	return Vector2(_corners[at + (side + 1) % 4], _corners[at + (side + 2) % 4])


## Whether a body can walk from a tile to its neighbour on `side` without jumping: the two
## tiles have to meet at the same height along the whole shared edge.
func can_walk(x: int, z: int, side: int) -> bool:
	var nx := x + ChunkMesher.NEIGHBOUR_DX[side]
	var nz := z + ChunkMesher.NEIGHBOUR_DZ[side]
	if not in_bounds(nx, nz) or is_hole(x, z) or is_hole(nx, nz):
		return false
	## The river is deep: nobody wades it. A bridge is walked at its deck, one level above the bed.
	if (is_water(x, z) and not is_bridge(x, z)) or (is_water(nx, nz) and not is_bridge(nx, nz)):
		return false
	## A bridge is walked at its deck, all the way across; whatever it meets has to meet it there.
	var mine := edge(x, z, side)
	var theirs := edge(nx, nz, (side + 2) % 4)
	if is_bridge(x, z):
		mine = Vector2.ONE * _deck_or_level(x, z)
	if is_bridge(nx, nz):
		theirs = Vector2.ONE * _deck_or_level(nx, nz)
	## Their edge is walked the other way round, so its left end is at my right end.
	return absf(mine.x - theirs.y) < 0.01 and absf(mine.y - theirs.x) < 0.01


func _deck_or_level(x: int, z: int) -> int:
	return heights[z * size + x] + bridge_lift(x, z)


## Marks every tile reachable on foot from the rim, and returns how many there are. The rim is a
## continuous ring at base level that meets the neighbouring chunks, so "reachable from the rim"
## is "reachable from the rest of the map". So is any rim tile level with the ground across the
## border -- the mountain's terraces, where they spill from one chunk into the next, are walked
## to through whichever chunk their way up is in. Spans (a bluff's bridges) are crossed too.
func flood_reach() -> int:
	reach.fill(0)
	var links := {}
	for span in spans:
		var a := span.y * size + span.x
		var b := span.w * size + span.z
		links[a] = (links.get(a, []) as Array) + [b]
		links[b] = (links.get(b, []) as Array) + [a]
	var queue: Array[int] = []
	for z in size:
		for x in size:
			if rim(x, z) == 0 and not is_hole(x, z) and _joins_map(x, z):
				reach[z * size + x] = 1
				queue.append(z * size + x)
	var count := queue.size()
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var x := index % size
		var z := index / size
		var nexts: Array = (links.get(index, []) as Array).duplicate()
		for side in 4:
			if can_walk(x, z, side):
				nexts.append((z + ChunkMesher.NEIGHBOUR_DZ[side]) * size + x + ChunkMesher.NEIGHBOUR_DX[side])
		for next: int in nexts:
			if reach[next] == 0:
				reach[next] = 1
				queue.append(next)
				count += 1
	return count


## Whether a rim tile counts as joined to the rest of the map: the rim walkway at the chunk's
## level -- except across from where the mountain spills over the border, which can wall a
## stretch of it off -- or any dry tile level with the one across the border.
func _joins_map(x: int, z: int) -> bool:
	var own := heights[z * size + x]
	for side in 4:
		var on_side: bool = [x == size - 1, z == size - 1, x == 0, z == 0][side]
		if not on_side:
			continue
		if side_levels[side] == MAP_EDGE:
			if own == base_level:
				return true
			continue
		var beyond := edge_level(side, lane_of(side, x, z))
		if beyond == side_levels[side] and own == base_level:
			return true
		if own == beyond and water[z * size + x] == 0:
			return true
	return false

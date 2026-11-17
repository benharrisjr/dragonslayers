class_name TerrainData
extends RefCounted

## One chunk's ground: a level per tile, plus which tiles are slopes.
##
## Terrain is still stepped plateaus, but a player without the feather cannot jump, so a single
## 0.9 m step is a wall to them. Slopes are what join the plateaus up. A tile is either flat, a
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
## The level this chunk's rim sits at, which is also its tier's ground level.
var base_level: int = 0
## Ground level of the chunk beyond each side (+x, +z, -x, -z), or MAP_EDGE.
var side_levels: PackedInt32Array = PackedInt32Array([MAP_EDGE, MAP_EDGE, MAP_EDGE, MAP_EDGE])

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


func level(x: int, z: int) -> int:
	return heights[z * size + x]


func is_hole(x: int, z: int) -> bool:
	return heights[z * size + x] == ChunkMesher.HOLE


func is_slope(x: int, z: int) -> bool:
	return slopes[z * size + x] != Slope.FLAT


func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < size and z < size


## Distance in tiles from the nearest chunk edge; 0 on the outermost ring.
func rim(x: int, z: int) -> int:
	return mini(mini(x, z), mini(size - 1 - x, size - 1 - z))


## Works out every tile's corner heights. Call once the levels and slopes are final.
func bake() -> void:
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
	var mine := edge(x, z, side)
	var theirs := edge(nx, nz, (side + 2) % 4)
	## Their edge is walked the other way round, so its left end is at my right end.
	return absf(mine.x - theirs.y) < 0.01 and absf(mine.y - theirs.x) < 0.01


## Marks every tile reachable on foot from the rim, and returns how many there are. The rim is a
## continuous ring at base level that meets the neighbouring chunks, so "reachable from the rim"
## is "reachable from the rest of the map".
func flood_reach() -> int:
	reach.fill(0)
	var queue: Array[int] = []
	for z in size:
		for x in size:
			if rim(x, z) == 0 and not is_hole(x, z) and heights[z * size + x] == base_level:
				reach[z * size + x] = 1
				queue.append(z * size + x)
	var count := queue.size()
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var x := index % size
		var z := index / size
		for side in 4:
			if not can_walk(x, z, side):
				continue
			var next := (z + ChunkMesher.NEIGHBOUR_DZ[side]) * size + x + ChunkMesher.NEIGHBOUR_DX[side]
			if reach[next] == 0:
				reach[next] = 1
				queue.append(next)
				count += 1
	return count

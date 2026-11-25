class_name PathNetwork
extends RefCounted

## The worn paths over the map: one network joining every slope between chunks, the town and the
## mountain's road, over ground that can be walked and the bridges that cross the water.
##
## Laid out over all sixteen chunks at once, once their terrain is worked out and before anything
## stands on it, so scenery keeps off the paths (TerrainData.path). A pure function of the terrain
## and the seed, like everything else about the map.
##
## Every place to join floods outwards at once, at a cost that likes open ground away from cliffs
## and wanders with noise; where two floods meet is the cheapest way between their two places, and
## the cheapest such ways that join everything are the paths.

## A pixel of the ground's path map, in metres, and how wide a path is worn.
const PIXEL := 0.5
const HALF_WIDTH := 1.7
## Up the mountain, where the ramps are a tile wide, it is a narrow trail.
const TRAIL_HALF_WIDTH := 0.55
## How far past a ramp's foot and top a path runs straight on, in tiles.
const RAMP_APPROACH := 3
## Along a path, a torch about this often, this far to one side of its middle (in tiles).
const TORCH_EVERY := 8
const TORCH_OFF := 2

const TILES := WorldGenerator.CHUNK_TILES
const ACROSS := WorldGenerator.GRID * TILES

## Each path, as map points in metres: smoothed, broken where it goes over a bridge.
var lines: Array[PackedVector2Array] = []
var places: Array[Vector2i] = []

var _terrains: Array[TerrainData] = []
var _mountain := -1
## For every tile of the map, a bit for each side it can be walked across.
var _walk: PackedByteArray


static func lay(terrains: Array[TerrainData], biomes: Array, seed_value: int) -> PathNetwork:
	var network := PathNetwork.new()
	network._terrains = terrains
	network._mountain = biomes.find(&"mountain")
	network._find_places(biomes)
	network._lay(seed_value)
	return network


func _terrain(x: int, z: int) -> TerrainData:
	return _terrains[z / TILES * WorldGenerator.GRID + x / TILES]


func _find_places(biomes: Array) -> void:
	for cell in _terrains.size():
		var terrain := _terrains[cell]
		var corner := Vector2i(cell % WorldGenerator.GRID, cell / WorldGenerator.GRID) * TILES
		for ramp: Dictionary in terrain.ramps:
			## Its foot, and the first tile of the higher chunk beyond its top.
			var lane: int = ramp["start"] + WorldGenerator.RAMP_WIDTH / 2
			places.append(corner + WorldGenerator._from_side(TILES, ramp["side"], int(ramp["length"]) + 1, lane))
			places.append(corner + WorldGenerator._from_side(TILES, ramp["side"], -1, lane))
		if biomes[cell] == &"town":
			places.append(corner + _open_tile(terrain))
		elif biomes[cell] == &"mountain":
			var side := WorldGenerator._ascent_side(cell)
			var foot := WorldGenerator.ascent_foot_tile(side, TILES)
			places.append(corner + WorldGenerator._from_side(TILES, side, foot.z, foot.y))
			## And up the road to the platform's edge.
			places.append(corner + WorldGenerator._from_side(TILES, side,
					TILES / 2 - WorldGenerator.ARENA_RADIUS_TILES + 1, TILES / 2))


## The walkable tile nearest the middle of a chunk.
func _open_tile(terrain: TerrainData) -> Vector2i:
	var best := Vector2i(TILES / 2, TILES / 2)
	var nearest := INF
	for z in TILES:
		for x in TILES:
			var gap := Vector2(x - TILES / 2, z - TILES / 2).length()
			if gap < nearest and terrain.reach[z * TILES + x] == 1 and not terrain.is_hazard(x, z):
				nearest = gap
				best = Vector2i(x, z)
	return best


func _lay(seed_value: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value + 1213
	noise.frequency = 0.06
	## Bridges the ground alone does not show, by tile.
	var spans := {}
	for cell in _terrains.size():
		var corner := Vector2i(cell % WorldGenerator.GRID, cell / WorldGenerator.GRID) * TILES
		for span in _terrains[cell].spans:
			var a := (corner.y + span.y) * ACROSS + corner.x + span.x
			var b := (corner.y + span.w) * ACROSS + corner.x + span.z
			spans[a] = (spans.get(a, []) as Array) + [b]
			spans[b] = (spans.get(b, []) as Array) + [a]
	_walk = _walk_masks()
	var walks := _keep_to_the_middle(_walk)
	var costs := PackedInt32Array()
	costs.resize(ACROSS * ACROSS)
	var offsets := PackedInt32Array()
	for side in 4:
		offsets.append(ChunkMesher.NEIGHBOUR_DZ[side] * ACROSS + ChunkMesher.NEIGHBOUR_DX[side])
	var dist := PackedInt32Array()
	var from := PackedInt32Array()
	var root := PackedInt32Array()
	dist.resize(ACROSS * ACROSS)
	dist.fill(1 << 30)
	from.resize(ACROSS * ACROSS)
	from.fill(-1)
	root.resize(ACROSS * ACROSS)
	root.fill(-1)
	## Buckets by cost: the costs are small whole numbers, so this needs no heap.
	var buckets: Array[PackedInt32Array] = [PackedInt32Array()]
	for i in places.size():
		var at := places[i].y * ACROSS + places[i].x
		dist[at] = 0
		root[at] = i
		buckets[0].append(at)
	## The cheapest way between each pair of places whose floods meet: {pair: [cost, tile, tile]}.
	var meets := {}
	var cost := 0
	while cost < buckets.size():
		var bucket := buckets[cost]
		buckets[cost] = PackedInt32Array()
		for at in bucket:
			if dist[at] != cost:
				continue
			var mask := walks[at]
			var nexts := PackedInt32Array(spans.get(at, []))
			var bridged := nexts.size()
			for side in 4:
				if mask & (1 << side):
					nexts.append(at + offsets[side])
			var straight := nexts.size()
			## Diagonally, where both ways round the corner can be walked.
			for side in 4:
				var after := (side + 1) % 4
				if mask & (1 << side) and mask & (1 << after) \
						and walks[at + offsets[side]] & (1 << after) \
						and walks[at + offsets[after]] & (1 << side):
					nexts.append(at + offsets[side] + offsets[after])
			for i in nexts.size():
				var next := nexts[i]
				if root[next] == root[at] and dist[next] <= cost:
					continue
				var step := 90
				if i >= bridged:
					step = costs[next]
					if step == 0:
						step = _tile_cost(next % ACROSS, next / ACROSS, noise)
						costs[next] = step
					if i >= straight:
						step = step * 7 / 5
				var total := cost + step
				## Only where both are settled: a tile still to be reached more cheaply may change hands.
				if root[next] != root[at] and dist[next] <= cost:
					var pair := Vector2i(mini(root[at], root[next]), maxi(root[at], root[next]))
					var whole := total + dist[next]
					if not meets.has(pair) or whole < meets[pair][0]:
						meets[pair] = [whole, at, next]
				if total < dist[next]:
					dist[next] = total
					from[next] = at
					root[next] = root[at]
					while buckets.size() <= total:
						buckets.append(PackedInt32Array())
					buckets[total].append(next)
		cost += 1
	## Kruskal's: cheapest first, skipping any that join what is already joined.
	var ways: Array = meets.values()
	ways.sort_custom(func(a: Array, b: Array) -> bool:
			return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var group := PackedInt32Array()
	for i in places.size():
		group.append(i)
	for way: Array in ways:
		var a := _find(group, root[way[1]])
		var b := _find(group, root[way[2]])
		if a == b:
			continue
		group[a] = b
		var tiles := PackedInt32Array()
		var at: int = way[1]
		while at >= 0:
			tiles.append(at)
			at = from[at]
		tiles.reverse()
		at = way[2]
		while at >= 0:
			tiles.append(at)
			at = from[at]
		_mark(tiles)
	joined = true
	for i in places.size():
		if _find(group, i) != _find(group, 0):
			joined = false


## Whether every place could be joined.
var joined := false


static func _find(group: PackedInt32Array, i: int) -> int:
	while group[i] != i:
		i = group[i]
	return i


## The same, but a ramp's only way is up its middle lane, straight on at its foot and its top, so
## a path never runs along a ramp's edge or turns off over the side of it.
func _keep_to_the_middle(masks: PackedByteArray) -> PackedByteArray:
	var out := masks.duplicate()
	for cell in _terrains.size():
		var corner := Vector2i(cell % WorldGenerator.GRID, cell / WorldGenerator.GRID) * TILES
		for ramp: Dictionary in _terrains[cell].ramps:
			var start: int = ramp["start"]
			var middle := start + WorldGenerator.RAMP_WIDTH / 2
			for depth in range(-RAMP_APPROACH, int(ramp["length"]) + RAMP_APPROACH):
				for lane in range(start - 1, start + WorldGenerator.RAMP_WIDTH + 1):
					var tile := corner + WorldGenerator._from_side(TILES, ramp["side"], depth, lane)
					if lane == middle or tile.x < 0 or tile.y < 0 or tile.x >= ACROSS or tile.y >= ACROSS:
						continue
					out[tile.y * ACROSS + tile.x] = 0
					for side in 4:
						var next := tile + Vector2i(ChunkMesher.NEIGHBOUR_DX[side], ChunkMesher.NEIGHBOUR_DZ[side])
						if next.x >= 0 and next.y >= 0 and next.x < ACROSS and next.y < ACROSS:
							out[next.y * ACROSS + next.x] &= ~(1 << ((side + 2) % 4)) & 0xF
	return out


func _walk_masks() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(ACROSS * ACROSS)
	for cell in _terrains.size():
		var terrain := _terrains[cell]
		## Open flat dry ground, which needs nothing looked up to cross to more of the same.
		var plain := PackedByteArray()
		plain.resize(TILES * TILES)
		for z in TILES:
			for x in TILES:
				plain[z * TILES + x] = int(terrain.slopes[z * TILES + x] == 0
						and terrain.reserved[z * TILES + x] == 0 and not terrain.is_water(x, z)
						and not terrain.is_hazard(x, z))
		var cx := cell % WorldGenerator.GRID * TILES
		var cz := cell / WorldGenerator.GRID * TILES
		for z in TILES:
			for x in TILES:
				var mask := 0
				for side in 4:
					var nx := x + ChunkMesher.NEIGHBOUR_DX[side]
					var nz := z + ChunkMesher.NEIGHBOUR_DZ[side]
					if plain[z * TILES + x] and nx >= 0 and nz >= 0 and nx < TILES and nz < TILES \
							and plain[nz * TILES + nx] and terrain.heights[nz * TILES + nx] == terrain.heights[z * TILES + x]:
						mask |= 1 << side
					elif _walks(cx + x, cz + z, side):
						mask |= 1 << side
				out[(cz + z) * ACROSS + cx + x] = mask
	return out


## Whether a tile can be walked to its neighbour on `side`, chunk borders included.
func _walks(x: int, z: int, side: int) -> bool:
	var nx := x + ChunkMesher.NEIGHBOUR_DX[side]
	var nz := z + ChunkMesher.NEIGHBOUR_DZ[side]
	if nx < 0 or nz < 0 or nx >= ACROSS or nz >= ACROSS:
		return false
	var mine := _terrain(x, z)
	var theirs := _terrain(nx, nz)
	var lx := x % TILES
	var lz := z % TILES
	var mx := nx % TILES
	var mz := nz % TILES
	if theirs.is_deep(mx, mz):
		return false
	if mine == theirs:
		return mine.can_walk(lx, lz, side)
	if mine.is_hazard(lx, lz) or theirs.is_hazard(mx, mz):
		return false
	var a := mine.edge(lx, lz, side)
	var b := theirs.edge(mx, mz, (side + 2) % 4)
	return absf(a.x - b.y) < 0.01 and absf(a.y - b.x) < 0.01


## What a tile costs to cross: wandering with noise, dearer beside a drop or the water's edge.
func _tile_cost(x: int, z: int, noise: FastNoiseLite) -> int:
	var terrain := _terrain(x, z)
	var lx := x % TILES
	var lz := z % TILES
	var cost := 6 + int((noise.get_noise_2d(x, z) + 0.6) * 18.0)
	if terrain.is_slope(lx, lz) or terrain.is_bridge(lx, lz):
		return maxi(cost, 4)
	var level := terrain.level(lx, lz)
	for side in 4:
		for off in [1, 2]:
			var mx: int = lx + ChunkMesher.NEIGHBOUR_DX[side] * off
			var mz: int = lz + ChunkMesher.NEIGHBOUR_DZ[side] * off
			if terrain.in_bounds(mx, mz) and terrain.level(mx, mz) != level:
				cost += 30 if off == 1 else 9
	if level < terrain.base_level:
		cost += 25
	return maxi(cost, 2)


## Marks a way on the ground and keeps its line, broken over bridges.
func _mark(tiles: PackedInt32Array) -> void:
	var line := PackedVector2Array()
	var level := PackedInt32Array()
	var previous := -1
	for at in tiles:
		var x := at % ACROSS
		var z := at / ACROSS
		var terrain := _terrain(x, z)
		var leap := previous >= 0 and maxi(absi(x - previous % ACROSS), absi(z - previous / ACROSS)) > 1
		if leap or terrain.is_water(x % TILES, z % TILES):
			_keep(line, level)
			line = PackedVector2Array()
			level = PackedInt32Array()
		if not terrain.is_water(x % TILES, z % TILES):
			line.append(Vector2(x + 0.5, z + 0.5) * ChunkMesher.TILE_SIZE)
			var lx := x % TILES
			var lz := z % TILES
			## A slope or a bridge's end keeps the line where it is.
			level.append(-1000 if terrain.is_slope(lx, lz) or terrain.reserved[lz * TILES + lx] != 0
					else terrain.level(lx, lz))
		previous = at
	_keep(line, level)


## Keeps a line: pulled straight into long easy curves wherever that leaves it on the same open
## ground, then rounded, and the tiles it crosses marked.
func _keep(line: PackedVector2Array, level: PackedInt32Array) -> void:
	if line.size() < 2:
		return
	for _round in 12:
		var eased := line.duplicate()
		for i in range(1, line.size() - 1):
			if level[i] == -1000:
				continue
			var at := line[i].lerp((line[i - 1] + line[i + 1]) * 0.5, 0.8)
			if _clear(at, level[i]):
				eased[i] = at
		line = eased
	line = ChunkMesher._smooth_path(line, false)
	lines.append(line)
	for at in line:
		var tile := Vector2i((at / ChunkMesher.TILE_SIZE).floor())
		for d: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var near := tile + d
			if near.x >= 0 and near.y >= 0 and near.x < ACROSS and near.y < ACROSS:
				_terrain(near.x, near.y).path[near.y % TILES * TILES + near.x % TILES] = 1


## Whether a path can run over a point: flat dry ground at `level`, a path's half-width all round.
func _clear(at: Vector2, level: int) -> bool:
	for d: Vector2 in [Vector2.ZERO, Vector2(1.6, 0.0), Vector2(-1.6, 0.0), Vector2(0.0, 1.6), Vector2(0.0, -1.6)]:
		var tile := Vector2i(((at + d) / ChunkMesher.TILE_SIZE).floor())
		if tile.x < 0 or tile.y < 0 or tile.x >= ACROSS or tile.y >= ACROSS:
			return false
		var terrain := _terrain(tile.x, tile.y)
		var x := tile.x % TILES
		var z := tile.y % TILES
		if terrain.is_hazard(x, z) or terrain.is_water(x, z) or terrain.is_slope(x, z) or terrain.level(x, z) != level:
			return false
	return true


## The path map: PIXEL metres to a pixel over the whole map, 1 in the middle of a path fading to 0 a
## little beyond its edge.
func image() -> Image:
	var size := int(ACROSS * ChunkMesher.TILE_SIZE / PIXEL)
	var data := PackedByteArray()
	data.resize(size * size)
	var reach := ceili((HALF_WIDTH + 1.0) / PIXEL)
	var joins := {}
	for line in lines:
		var halves := _half_widths(line)
		for i in line.size():
			## Smoothing leaves a point every few centimetres: one every half metre is plenty.
			if i % 3 != 0 and i < line.size() - 1:
				continue
			var at := line[i]
			var half := halves[i]
			var here := Vector2i((at / ChunkMesher.TILE_SIZE).floor())
			var px := Vector2i((at / PIXEL).floor())
			for z in range(px.y - reach, px.y + reach + 1):
				for x in range(px.x - reach, px.x + reach + 1):
					if x < 0 or z < 0 or x >= size or z >= size:
						continue
					var gap := Vector2(x + 0.5, z + 0.5).distance_to(at / PIXEL) * PIXEL
					var value := int(255.0 * clampf(1.0 - (gap - half + 1.0) * 0.5, 0.0, 1.0))
					if value > data[z * size + x] and _joined_on_foot(here,
							Vector2i(int(x * PIXEL), int(z * PIXEL)) / int(ChunkMesher.TILE_SIZE), joins):
						data[z * size + x] = value
	return Image.create_from_data(size, size, false, Image.FORMAT_R8, data)


## How wide a path is at each point of its line: a narrow trail on the mountain, narrowing to it
## over the last stretch before.
func _half_widths(line: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for at in line:
		var tile := Vector2i((at / ChunkMesher.TILE_SIZE).floor())
		var terrain := _terrain(tile.x, tile.y)
		var on_it := tile.y / TILES * WorldGenerator.GRID + tile.x / TILES == _mountain \
				or (terrain.owner.size() > 0 and terrain.owner[tile.y % TILES * TILES + tile.x % TILES] == _mountain + 1)
		out.append(TRAIL_HALF_WIDTH if on_it else HALF_WIDTH)
	for i in range(1, line.size()):
		out[i] = minf(out[i], out[i - 1] + line[i].distance_to(line[i - 1]) * 0.12)
	for i in range(line.size() - 2, -1, -1):
		out[i] = minf(out[i], out[i + 1] + line[i].distance_to(line[i + 1]) * 0.12)
	return out


## Whether a path on one tile can spread onto another nearby: ground walked straight to from it,
## so it never shows below the edge of what it runs along, or above it.
func _joined_on_foot(a: Vector2i, b: Vector2i, known: Dictionary) -> bool:
	if a == b:
		return true
	var key := Vector4i(a.x, a.y, b.x, b.y)
	if known.has(key):
		return known[key]
	var result := false
	var mask := _walk[a.y * ACROSS + a.x]
	for side in 4:
		var step := Vector2i(ChunkMesher.NEIGHBOUR_DX[side], ChunkMesher.NEIGHBOUR_DZ[side])
		var gap := b - a
		if mask & (1 << side) and step.x * gap.x + step.y * gap.y > 0 and _joined_on_foot(a + step, b, known):
			result = true
			break
	known[key] = result
	return result


## Where torches stand, as {chunk: [Vector2i tile, ...]}: along the paths, first on one side and
## then the other, on flat dry ground beside them and not too near one another.
func torches() -> Dictionary:
	var out := {}
	var stood: Array[Vector2i] = []
	for line in lines:
		var turn := 1
		var since := TORCH_EVERY * 0.5 * ChunkMesher.TILE_SIZE
		for i in range(1, line.size()):
			since += line[i].distance_to(line[i - 1])
			if since < TORCH_EVERY * ChunkMesher.TILE_SIZE:
				continue
			var along := (line[i] - line[i - 1]).normalized()
			var placed := false
			for side: int in [turn, -turn]:
				for off in [TORCH_OFF, TORCH_OFF + 1]:
					var at: Vector2 = line[i] / ChunkMesher.TILE_SIZE + Vector2(-along.y, along.x) * side * off
					var tile := Vector2i(at.floor())
					if not placed and _stands(tile, line[i], stood):
						var cell := tile.y / TILES * WorldGenerator.GRID + tile.x / TILES
						if not out.has(cell):
							out[cell] = []
						(out[cell] as Array).append(tile % TILES)
						stood.append(tile)
						placed = true
			if placed:
				since = 0.0
				turn = -turn
	return out


func _stands(tile: Vector2i, beside: Vector2, stood: Array[Vector2i]) -> bool:
	if tile.x < 1 or tile.y < 1 or tile.x >= ACROSS - 1 or tile.y >= ACROSS - 1:
		return false
	var terrain := _terrain(tile.x, tile.y)
	var x := tile.x % TILES
	var z := tile.y % TILES
	var index := z * TILES + x
	if terrain.path[index] == 1 or terrain.slopes[index] != 0 or terrain.is_hazard(x, z) \
			or terrain.is_water(x, z) or terrain.reach[index] == 0 or terrain.level(x, z) < terrain.base_level:
		return false
	## Never on the dragon's platform.
	if tile.y / TILES * WorldGenerator.GRID + tile.x / TILES == _mountain:
		var half := (TILES - 1) * 0.5
		if Vector2(x - half, z - half).length() <= WorldGenerator.ARENA_RADIUS_TILES \
				+ WorldGenerator.ARENA_SKIRT_TILES + 1:
			return false
	## At the path's own height, not on a cliff over it.
	var walked := Vector2i((beside / ChunkMesher.TILE_SIZE).floor())
	var path_terrain := _terrain(clampi(walked.x, 0, ACROSS - 1), clampi(walked.y, 0, ACROSS - 1))
	if absf(path_terrain.surface_level(walked.x % TILES, walked.y % TILES) - terrain.level(x, z)) > 0.6:
		return false
	## Clear of the edges and corners round it.
	for side in 4:
		var mx := x + ChunkMesher.NEIGHBOUR_DX[side]
		var mz := z + ChunkMesher.NEIGHBOUR_DZ[side]
		if terrain.in_bounds(mx, mz) and (terrain.level(mx, mz) != terrain.level(x, z) or terrain.is_water(mx, mz)):
			return false
	for other in stood:
		if Vector2(other - tile).length() < TORCH_EVERY * 0.7:
			return false
	return true

class_name RiverCarver
extends RefCounted

## Cuts one chunk's stretch of the river into its terrain.
##
## WorldGenerator plans the whole river at chunk scale -- which chunks, where it crosses each
## border, the bends it makes inside each chunk -- and this draws one chunk's part: a smooth
## curve from where it comes in, through its bends, to where it goes out (or out into the sea).
##
## The bed is one level below the banks, and never higher than it was upstream. On flat ground
## that is simply the chunk's ground level less one; where the ground steps down -- a terrace on
## the mountain, the cliff between two tiers at a chunk border -- the bed steps down with it,
## and each of those steps is a waterfall. Where the ground rises (a mesa in the way) the river
## keeps its level and cuts a gorge through.
##
## A raft is the way along it; a bridge is the way over. Every chunk the river crosses gets one,
## on the straight stretch where it comes in (on the mountain, where it leaves across the rim):
## the river cuts each chunk in two, and one bridge per chunk is what keeps every part of the
## map walkable without a raft.

const STEP := 0.25
## How far into the chunk the bridge sits, along the straight stretch.
const BRIDGE_DEPTH := 6
const MOUNTAIN_BRIDGE_DEPTH := 1


static func carve(terrain: TerrainData, part: Dictionary) -> void:
	var size := terrain.size
	## The ground as it was before any digging: the bed is worked out against this.
	var ground := terrain.heights.duplicate()
	var points: Array[Vector2] = []
	var start_bed := terrain.base_level - 1
	## Cut deep here, or coming in from where it is.
	var sink := maxf(float(part.get("sink", 0.0)), float(part.get("entry_sink", 0.0)))
	var keeps := float(part.get("sink", 0.0)) > 0.0
	if part.has("entry"):
		## A level below the ground where it comes in -- the lower of the two sides of the border,
		## which differ where the mountain spills across it, so it never steps up into this chunk.
		var entry: Array = part["entry"]
		var rim := WorldGenerator._from_side(size, entry[0], 0, entry[1])
		start_bed = mini(terrain.level(rim.x, rim.y), terrain.edge_level(entry[0], entry[1])) - 1
		## And no higher than it left the mountain, which it may have crossed a dip on.
		start_bed = mini(start_bed, int(part.get("bed_before", start_bed)))
		terrain.side_sink[entry[0]] = float(part.get("entry_sink", 0.0))
	if part.has("exit"):
		terrain.side_sink[int(part["exit"][0])] = float(part.get("exit_sink", 0.0))
	if part.has("pond"):
		var pond: Vector2 = part["pond"]
		## Level across the whole pond, at the lowest terrace it reaches: a pond straddling a
		## terrace edge would otherwise sit at two heights, and the river leaving its lower half
		## curls back past the upper one.
		start_bed = _pond_bed(terrain, pond)
		_dig_pond(terrain, pond, start_bed, sink)
		points.append(pond)
	if part.has("entry"):
		var entry: Array = part["entry"]
		points.append_array(_straight(size, entry[0], entry[1], true))
	var tail: Array[Vector2] = []
	if part.has("exit"):
		var exit: Array = part["exit"]
		tail = _straight(size, exit[0], exit[1], false)
	elif part.has("sea"):
		## Out towards the open sea, until it meets it.
		tail = [_lane_point(size, part["sea"], 20.0, size * 0.5),
				_lane_point(size, part["sea"], -2.0, size * 0.5)]
	elif part.has("lake"):
		## On into the lake, until it meets the water.
		tail = [Vector2(size, size) * 0.5]
	## Meanders between where it comes in and where it goes out: a fraction of the way along the
	## straight line between them, swung out to one side, and kept off the chunk's edges.
	if not points.is_empty() and not tail.is_empty():
		var from := points[-1]
		var to := tail[0]
		## Straight down the mountain: a bend would take it along the terraces, through some dip
		## lower than where it leaves, and the next chunk cannot know to come in that low.
		var bends: Array = [] if part.has("pond") else part.get("bends", [])
		## Coming in on one side and leaving by the next one round, the straight line between
		## them runs along just inside a border -- where a ramp down to the next chunk has to go.
		## So it swings through the middle of the chunk instead.
		var turns_corner := part.has("entry") and part.has("exit") \
				and (int(part["entry"][0]) + 2) % 4 != int(part["exit"][0])
		if turns_corner:
			var middle := Vector2(size, size) * 0.5
			var sway: float = (bends[0] as Vector2).y * 0.5 if not bends.is_empty() else 0.0
			points.append(middle + (to - from).orthogonal().normalized() * sway)
		else:
			var across := (to - from).orthogonal().normalized()
			for bend: Vector2 in bends:
				var at := from.lerp(to, bend.x) + across * bend.y
				points.append(at.clamp(Vector2.ONE * 14.0, Vector2.ONE * (size - 14.0)))
	points.append_array(tail)
	if points.size() < 2:
		return
	var course := _dig_channel(terrain, ground, points, start_bed,
			part.has("sea") or part.has("lake"), sink, keeps)
	## The arm that splits off for the lake: from half way along, out to its own border.
	var arm: Array = part.get("branch", [])
	if not arm.is_empty() and not course.is_empty():
		var junction: Vector2 = course[course.size() / 2][0]
		var at := Vector2i(junction.floor())
		var bed := terrain.level(at.x, at.y) if terrain.is_water(at.x, at.y) else start_bed
		var arm_points: Array[Vector2] = [junction]
		arm_points.append_array(_straight(size, arm[0], arm[1], false))
		_dig_channel(terrain, ground, arm_points, bed, false, terrain.sink_at(at.x, at.y), keeps)
	if part.has("pond"):
		var exit: Array = part["exit"]
		_place_bridge(terrain, exit[0], exit[1], MOUNTAIN_BRIDGE_DEPTH)
	elif part.has("entry"):
		var entry: Array = part["entry"]
		_place_bridge(terrain, entry[0], entry[1], BRIDGE_DEPTH)
	## The arm cuts its chunk again, so it has its bridge too.
	if not arm.is_empty():
		_place_bridge(terrain, arm[0], arm[1], BRIDGE_DEPTH)
	_place_land_bridge(terrain, course)


## How low the river is when it leaves the mountain, worked out from the mountain's shape alone
## (`shape` as the mountain's own chunk sees it) for the chunk it runs into.
static func mountain_bed(shape: Dictionary, part: Dictionary) -> int:
	var size := WorldGenerator.CHUNK_TILES
	var base := WorldGenerator.base_level(WorldGenerator.Tier.SUMMIT)
	var pond: Vector2 = part["pond"]
	var exit: Array = part["exit"]
	var bed := 1000
	var radius := WorldGenerator.RIVER_POND_RADIUS
	for z in range(int(pond.y - radius) - 1, int(pond.y + radius) + 2):
		for x in range(int(pond.x - radius) - 1, int(pond.x + radius) + 2):
			if Vector2(x + 0.5, z + 0.5).distance_to(pond) <= radius:
				bed = mini(bed, maxi(base, WorldGenerator.mountain_level(shape, x, z)) - 1)
	var points: Array[Vector2] = [pond]
	points.append_array(_straight(size, exit[0], exit[1], false))
	for segment in points.size() - 1:
		var p0 := points[maxi(segment - 1, 0)]
		var p3 := points[mini(segment + 2, points.size() - 1)]
		var steps := maxi(1, int(points[segment].distance_to(points[segment + 1]) / STEP))
		for step in steps:
			var tile := Vector2i(_catmull(p0, points[segment], points[segment + 1], p3, float(step) / steps).floor())
			if tile.x >= 0 and tile.y >= 0 and tile.x < size and tile.y < size:
				bed = mini(bed, maxi(base, WorldGenerator.mountain_level(shape, tile.x, tile.y)) - 1)
	return bed


## The straight stretch at a border: from just beyond it, in to RIVER_STRAIGHT tiles deep (or the
## reverse, going out).
static func _straight(size: int, side: int, lane: int, inward: bool) -> Array[Vector2]:
	var out: Array[Vector2] = [
		_lane_point(size, side, -2.0, lane + 0.5),
		_lane_point(size, side, WorldGenerator.RIVER_STRAIGHT * 0.5, lane + 0.5),
		_lane_point(size, side, WorldGenerator.RIVER_STRAIGHT, lane + 0.5),
	]
	if not inward:
		out.reverse()
	return out


## A point `depth` tiles in from `side`, `lane` along it, in continuous tile coordinates.
static func _lane_point(size: int, side: int, depth: float, lane: float) -> Vector2:
	match side:
		0: return Vector2(size - depth, lane)
		1: return Vector2(lane, size - depth)
		2: return Vector2(depth, lane)
		_: return Vector2(lane, depth)


static func _pond_bed(terrain: TerrainData, centre: Vector2) -> int:
	var radius := WorldGenerator.RIVER_POND_RADIUS
	var lowest := terrain.level(int(centre.x), int(centre.y))
	for z in range(int(centre.y - radius) - 1, int(centre.y + radius) + 2):
		for x in range(int(centre.x - radius) - 1, int(centre.x + radius) + 2):
			if terrain.in_bounds(x, z) and not terrain.is_hole(x, z) \
					and Vector2(x + 0.5, z + 0.5).distance_to(centre) <= radius:
				lowest = mini(lowest, terrain.level(x, z))
	return lowest - 1


static func _dig_pond(terrain: TerrainData, centre: Vector2, bed: int, sink: float) -> void:
	var radius := WorldGenerator.RIVER_POND_RADIUS
	for z in range(int(centre.y - radius) - 1, int(centre.y + radius) + 2):
		for x in range(int(centre.x - radius) - 1, int(centre.x + radius) + 2):
			if not terrain.in_bounds(x, z):
				continue
			var distance := Vector2(x + 0.5, z + 0.5).distance_to(centre)
			## Only into its own terrace (and the walls above it): a terrace below is left dry,
			## rather than raised into a column of water.
			if distance <= radius and terrain.level(x, z) > bed:
				_wet(terrain, x, z, bed, Vector2.ZERO, sink)
			elif distance <= radius + 1.5:
				terrain.reserved[z * terrain.size + x] = 1


## Walks a Catmull-Rom curve through `points`, marking water within RIVER_RADIUS of it and keeping
## its banks clear. The bed is set as it goes, never rising. Returns the course it took: a
## [point, flow] every STEP along it.
static func _dig_channel(terrain: TerrainData, ground: PackedInt32Array, points: Array[Vector2],
		start_bed: int, to_sea: bool, sink: float = 0.0, keeps_sink: bool = false) -> Array:
	var size := terrain.size
	var bed := start_bed
	var course: Array = []
	for segment in points.size() - 1:
		var p0 := points[maxi(segment - 1, 0)]
		var p1 := points[segment]
		var p2 := points[segment + 1]
		var p3 := points[mini(segment + 2, points.size() - 1)]
		var steps := maxi(1, int(p1.distance_to(p2) / STEP))
		for step in steps:
			var t := float(step) / steps
			var at := _catmull(p0, p1, p2, p3, t)
			var ahead := _catmull(p0, p1, p2, p3, minf(t + 0.05, 1.0)) - at
			var flow := ahead.normalized() if ahead.length_squared() > 0.0001 \
					else (p2 - p1).normalized()
			var tile := Vector2i(at.floor())
			if terrain.in_bounds(tile.x, tile.y):
				var here := ground[tile.y * size + tile.x]
				## On the beach the river ends where it meets the sea.
				if to_sea and here < terrain.base_level:
					return course
				if here != ChunkMesher.HOLE:
					bed = mini(bed, here - 1)
				if bed < start_bed and not keeps_sink:
					sink = 0.0
			_wet_around(terrain, at, bed, flow, sink)
			course.append([at, flow])
	return course


static func _wet_around(terrain: TerrainData, at: Vector2, bed: int, flow: Vector2, sink: float) -> void:
	var reach := WorldGenerator.RIVER_BANK
	for z in range(int(at.y - reach) - 1, int(at.y + reach) + 2):
		for x in range(int(at.x - reach) - 1, int(at.x + reach) + 2):
			if not terrain.in_bounds(x, z):
				continue
			var distance := Vector2(x + 0.5, z + 0.5).distance_to(at)
			if distance <= WorldGenerator.RIVER_RADIUS:
				_wet(terrain, x, z, bed, flow, sink)
			elif distance <= reach:
				terrain.reserved[z * terrain.size + x] = 1


static func _wet(terrain: TerrainData, x: int, z: int, bed: int, flow: Vector2, sink: float) -> void:
	var index := z * terrain.size + x
	if terrain.water[index] == 1:
		## Already wet from further upstream: keep the lower bed, so the river only ever falls.
		if terrain.heights[index] <= bed:
			sink = terrain.sinks[index] if terrain.heights[index] < bed else maxf(sink, terrain.sinks[index])
		bed = mini(bed, terrain.heights[index])
	terrain.sinks[index] = sink
	terrain.water[index] = 1
	terrain.heights[index] = bed
	terrain.slopes[index] = TerrainData.Slope.FLAT
	terrain.reserved[index] = 1
	if flow != Vector2.ZERO:
		terrain.flow[index] = flow


## A bridge across the straight stretch `depth` tiles in from `side`: two tiles wide, spanning the
## water from bank to bank. The bank tiles at either end are levelled to the deck, so it can always
## be walked onto.
static func _place_bridge(terrain: TerrainData, side: int, lane: int, depth: int) -> void:
	var size := terrain.size
	var wet: Array[Vector2i] = []
	var low := lane
	var high := lane
	for along in range(lane - 4, lane + 5):
		var tile := WorldGenerator._from_side(size, side, depth, clampi(along, 0, size - 1))
		if terrain.is_water(tile.x, tile.y):
			low = mini(low, along)
			high = maxi(high, along)
	var bed := terrain.level(WorldGenerator._from_side(size, side, depth, lane).x,
			WorldGenerator._from_side(size, side, depth, lane).y)
	var deck := bed + 1
	var tiles: Array[Vector2i] = []
	for row in [depth, depth + 1]:
		for along in range(low - 1, high + 2):
			var tile := WorldGenerator._from_side(size, side, row, clampi(along, 0, size - 1))
			var index := tile.y * size + tile.x
			if terrain.water[index] == 1:
				terrain.bridge[index] = 1
				tiles.append(tile)
			else:
				## A bank: level with the deck, flat, and kept clear.
				terrain.heights[index] = deck
				terrain.slopes[index] = TerrainData.Slope.FLAT
				terrain.reserved[index] = 1
	var a := WorldGenerator._from_side(size, side, depth, clampi(low - 1, 0, size - 1))
	var b := WorldGenerator._from_side(size, side, depth + 1, clampi(high + 1, 0, size - 1))
	terrain.bridges.append({
		"from": Vector2i(mini(a.x, b.x), mini(a.y, b.y)),
		"to": Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)),
		"level": deck,
		## Which way people walk over it: across the river, i.e. along the border.
		"along_x": side == 1 or side == 3,
	})


## Besides its plank bridge, a chunk's stretch of river may have a land bridge: a broad arch of
## rock and turf left standing over it, LAND_BRIDGE_LIFT levels above the bed -- high enough for
## someone on a raft to ride under it -- rising to it from each bank in a smooth curve of its own,
## LAND_BRIDGE_APPROACH tiles long (RiverBuilder.build_land_bridge). It goes where the
## river runs straight along a row of tiles between level banks, nearest the middle of the
## stretch, and well clear of the other bridge.
const LAND_BRIDGE_WIDTH := 3
const LAND_BRIDGE_CLEAR := 14.0
const LAND_BRIDGE_RIM := WorldGenerator.BORDER + 6
## Widest a river it spans can be, in tiles.
const LAND_BRIDGE_SPAN := 5
## Its deck, in levels above the river bed: the banks are one, and two more is 3 m over them.
const LAND_BRIDGE_LIFT := 3
const LAND_BRIDGE_APPROACH := 3


static func _place_land_bridge(terrain: TerrainData, course: Array) -> void:
	var best := {}
	var best_score := INF
	var middle := course.size() * 0.5
	for i in range(0, course.size(), 4):
		var at: Vector2 = course[i][0]
		var flow: Vector2 = course[i][1]
		## Walked across the river, so along x where it runs along z.
		var walk_x := absf(flow.y) > 0.94
		if not walk_x and absf(flow.x) <= 0.94:
			continue
		var tile := Vector2i(at.floor())
		if not terrain.in_bounds(tile.x, tile.y) or terrain.rim(tile.x, tile.y) < LAND_BRIDGE_RIM:
			continue
		var score := absf(i - middle)
		if score >= best_score:
			continue
		var spec := _land_bridge_at(terrain, tile, walk_x)
		if not spec.is_empty():
			best = spec
			best_score = score
	if best.is_empty():
		return
	var size := terrain.size
	var from: Vector2i = best["from"]
	var to: Vector2i = best["to"]
	var walk_x: bool = best["along_x"]
	var span: Vector2i = best["span"]
	for z in range(from.y - (0 if walk_x else 1), to.y + (1 if walk_x else 2)):
		for x in range(from.x - (1 if walk_x else 0), to.x + (2 if walk_x else 1)):
			if not terrain.in_bounds(x, z):
				continue
			var index := z * size + x
			terrain.reserved[index] = 1
			if x >= from.x and x <= to.x and z >= from.y and z <= to.y and terrain.water[index] == 1:
				terrain.bridge[index] = LAND_BRIDGE_LIFT
	## Its curves up from the banks are its own, not the ground's: the way across, for the reach
	## flood, is from the bank before one to the bank after the other.
	var v := (from.y if walk_x else from.x) + 1
	var a := Vector2i(span.x - LAND_BRIDGE_APPROACH - 1, v) if walk_x \
			else Vector2i(v, span.x - LAND_BRIDGE_APPROACH - 1)
	var b := Vector2i(span.y + LAND_BRIDGE_APPROACH + 1, v) if walk_x \
			else Vector2i(v, span.y + LAND_BRIDGE_APPROACH + 1)
	terrain.spans.append(Vector4i(a.x, a.y, b.x, b.y))
	terrain.bridges.append(best)


## The land bridge across the river at `tile`, walked along x (`walk_x`) or z, as a bridge spec --
## or {} if the river is not straight, level and narrow enough there, between banks level with
## its deck.
static func _land_bridge_at(terrain: TerrainData, tile: Vector2i, walk_x: bool) -> Dictionary:
	var at := func(u: int, v: int) -> Vector2i:
		return Vector2i(u, v) if walk_x else Vector2i(v, u)
	var u0 := tile.x if walk_x else tile.y
	var v0 := tile.y if walk_x else tile.x
	var low := -1
	var high := -1
	var bed := ChunkMesher.HOLE
	for k in range(-1, LAND_BRIDGE_WIDTH - 1):
		var v := v0 + k
		var here: Vector2i = at.call(u0, v)
		if not terrain.is_water(here.x, here.y) or terrain.is_bridge(here.x, here.y):
			return {}
		var lo := u0
		while terrain.is_water(at.call(lo - 1, v).x, at.call(lo - 1, v).y):
			lo -= 1
		var hi := u0
		while terrain.is_water(at.call(hi + 1, v).x, at.call(hi + 1, v).y):
			hi += 1
		if k == -1:
			low = lo
			high = hi
			bed = terrain.level(here.x, here.y)
		elif lo != low or hi != high:
			return {}
		if hi - lo + 1 > LAND_BRIDGE_SPAN:
			return {}
		for u in range(lo, hi + 1):
			var wet: Vector2i = at.call(u, v)
			if terrain.level(wet.x, wet.y) != bed or terrain.is_bridge(wet.x, wet.y):
				return {}
		## Bank at each end, flat and a level above the bed: room for the curve up and a tile to
		## step onto it from.
		for u in range(1, LAND_BRIDGE_APPROACH + 2):
			for end: int in [lo - u, hi + u]:
				var bank: Vector2i = at.call(end, v)
				if not terrain.in_bounds(bank.x, bank.y) or terrain.is_hole(bank.x, bank.y) \
						or terrain.is_water(bank.x, bank.y) or terrain.is_slope(bank.x, bank.y) \
						or terrain.level(bank.x, bank.y) != bed + 1:
					return {}
	## No fall just up or downstream of it, which would pour out from under its edge.
	for v in [v0 - 2, v0 + LAND_BRIDGE_WIDTH - 1]:
		for u in range(low, high + 1):
			var wet: Vector2i = at.call(u, v)
			if terrain.is_water(wet.x, wet.y) and terrain.level(wet.x, wet.y) != bed:
				return {}
	var a: Vector2i = at.call(low - LAND_BRIDGE_APPROACH, v0 - 1)
	var b: Vector2i = at.call(high + LAND_BRIDGE_APPROACH, v0 + LAND_BRIDGE_WIDTH - 2)
	var centre := (Vector2(a) + Vector2(b)) * 0.5
	for other: Dictionary in terrain.bridges:
		var other_centre := (Vector2(other["from"]) + Vector2(other["to"])) * 0.5
		if other_centre.distance_to(centre) < LAND_BRIDGE_CLEAR:
			return {}
	return {
		"from": Vector2i(mini(a.x, b.x), mini(a.y, b.y)),
		"to": Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)),
		"level": bed + LAND_BRIDGE_LIFT,
		"lift": LAND_BRIDGE_LIFT,
		"along_x": walk_x,
		"kind": &"land",
		## The water it arches over, in tiles along the way it is walked.
		"span": Vector2i(low, high),
	}


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

class_name WorldGenerator
extends RefCounted

## Decides what the 16 chunks are and what shape each one is.
##
## Everything here is a pure function of the world seed. That is not a tidiness preference: the
## map is never sent over the network, so four machines each running this code with the same
## seed is the entire world transfer, and any hidden non-determinism would desync the game.

const GRID := 4
## 64 tiles at 2 m is a 128 m chunk, so the 4x4 map is 512 m across. Doubled from 32 to give the
## mountain room to be a mountain; everything below that is derived from it rather than being a
## separate constant, so the chunk size stays the one number to change.
const CHUNK_TILES := 64
const CHUNK_SIZE := ChunkMesher.TILE_SIZE * CHUNK_TILES
## Border tiles pinned to the chunk's own ground level, so chunks on the same tier always meet
## flush without any cross-chunk generation, and every chunk has a clear walkway round it.
const BORDER := 4
## Resolution of the random control grid the heightmap is interpolated from. Small values give
## broad plateaus; large values give noise.
## Scaled with the chunk so terrain features stay the same size in metres. Leaving it at 5 on a
## chunk twice as wide would make every plateau twice as big and the map read as emptier.
const CONTROL_POINTS := 9

## Radius in tiles of the flat platform at the mountain's summit. 12 tiles is 48 m across --
## room for a 12.6 m dragon and four players to spread out and circle it, with an edge still
## close enough that a tail sweep can put someone over it.
const ARENA_RADIUS_TILES := 12
## How far outside the platform the summit stays flat before the terraces drop away.
const ARENA_SKIRT_TILES := 3

## The map steps down from the mountain. Each chunk's tier is how far it is from the mountain
## chunk: the mountain itself, the highlands touching it, the ground beyond those, and -- for
## some of the chunks furthest away -- the sea.
enum Tier { SEA, GROUND, HIGHLANDS, SUMMIT }

## Ground level of each tier, in 0.9 m steps. The gaps are what the ramps climb: five tiles from
## the beach to the ground, eight from the ground to the highlands.
const TIER_LEVELS: Dictionary = {
	Tier.SEA: 1, Tier.GROUND: 6, Tier.HIGHLANDS: 14, Tier.SUMMIT: 14,
}
## How far the summit platform stands above the mountain chunk's rim. Twelve levels is the
## length of ascent ramp that fits between the rim and the platform.
const SUMMIT_RISE := 12
## How much each mountain terrace rises. Three steps is 2.7 m: more than the 2.3 m jump, so the
## terraces can be dropped down but not hopped back up, and the ramp is the way to the top.
const TERRACE_RISE := 3
## Tile width of every ramp.
const RAMP_WIDTH := 4
## Flat ground kept clear at the top of a ramp.
const RAMP_LANDING := 4
## Height of the sea's surface in metres: half a step, so the sand (one level) is dry and the
## shallows (level 0) are ankle deep.
const SEA_SURFACE := 0.45

const HIGHLAND_BIOMES: Array[StringName] = [&"temple", &"forest", &"plains", &"temple", &"fields"]
const GROUND_BIOMES: Array[StringName] = [
	&"plains", &"fields", &"lake", &"desert", &"forest", &"plains", &"fields", &"temple",
]


## Returns 16 biome ids in row-major order.
static func layout(world_seed: int) -> Array[StringName]:
	var biomes: Array[StringName] = []
	biomes.assign(plan(world_seed)["biomes"])
	return biomes


## Tier of each of the 16 chunks, row-major.
static func tiers(world_seed: int) -> PackedInt32Array:
	return plan(world_seed)["tiers"]


## The whole map at chunk scale: which biome and which tier each cell is.
static func plan(world_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ 0x5EED
	var cells := GRID * GRID

	## The mountain wants an edge so the summit reads as the top of something rather than a lump
	## in the middle of a field.
	var edge_cells: Array[int] = []
	for index in cells:
		if _is_edge(index):
			edge_cells.append(index)
	var mountain := edge_cells[rng.randi_range(0, edge_cells.size() - 1)]

	var tier_of := PackedInt32Array()
	tier_of.resize(cells)
	var far: Array[int] = []
	for index in cells:
		var distance := _chebyshev(index, mountain)
		if distance == 0:
			tier_of[index] = Tier.SUMMIT
		elif distance == 1:
			tier_of[index] = Tier.HIGHLANDS
		else:
			tier_of[index] = Tier.GROUND
			if distance >= 3:
				far.append(index)

	## Some of the furthest chunks drop to sea level: a connected stretch of coast, grown from
	## one cell so the beach is one place rather than scattered puddles.
	var wanted := mini(far.size(), rng.randi_range(2, 4))
	var sea: Array[int] = []
	if not far.is_empty():
		sea.append(far[rng.randi_range(0, far.size() - 1)])
	while sea.size() < wanted:
		var options: Array[int] = []
		for index in far:
			if not sea.has(index) and _touches_any(index, sea):
				options.append(index)
		if options.is_empty():
			break
		sea.append(options[rng.randi_range(0, options.size() - 1)])
	for index in sea:
		tier_of[index] = Tier.SEA

	var biomes: Array[StringName] = []
	biomes.resize(cells)
	var highland_pool := HIGHLAND_BIOMES.duplicate()
	var ground_pool := GROUND_BIOMES.duplicate()
	_shuffle(highland_pool, rng)
	_shuffle(ground_pool, rng)

	## Town far from the mountain gives the run a journey: start low, dragon last. Every ground
	## chunk is at least two cells from the mountain, so any of them will do.
	var ground_cells: Array[int] = []
	for index in cells:
		if tier_of[index] == Tier.GROUND:
			ground_cells.append(index)
	var town := ground_cells[rng.randi_range(0, ground_cells.size() - 1)]

	var highland_next := 0
	var ground_next := 0
	for index in cells:
		match tier_of[index]:
			Tier.SUMMIT:
				biomes[index] = &"mountain"
			Tier.HIGHLANDS:
				biomes[index] = highland_pool[highland_next % highland_pool.size()]
				highland_next += 1
			Tier.SEA:
				biomes[index] = &"beach"
			_:
				if index == town:
					biomes[index] = &"town"
				else:
					biomes[index] = ground_pool[ground_next % ground_pool.size()]
					ground_next += 1
	return {"biomes": biomes, "tiers": tier_of}


static func _is_edge(index: int) -> bool:
	var x := index % GRID
	var z := index / GRID
	return x == 0 or z == 0 or x == GRID - 1 or z == GRID - 1


static func _chebyshev(a: int, b: int) -> int:
	return maxi(absi(a % GRID - b % GRID), absi(a / GRID - b / GRID))


## Index of the cell beyond `side` (+x, +z, -x, -z) of a cell, or -1 at the edge of the map.
static func neighbour_cell(index: int, side: int) -> int:
	var x := index % GRID + ChunkMesher.NEIGHBOUR_DX[side]
	var z := index / GRID + ChunkMesher.NEIGHBOUR_DZ[side]
	if x < 0 or z < 0 or x >= GRID or z >= GRID:
		return -1
	return z * GRID + x


static func _touches_any(index: int, group: Array[int]) -> bool:
	for side in 4:
		if group.has(neighbour_cell(index, side)):
			return true
	return false


static func _shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = array[i]
		array[i] = array[j]
		array[j] = swap


static func base_level(tier: int) -> int:
	return TIER_LEVELS[tier]


## Level of the dragon's platform.
static func summit_level() -> int:
	return TIER_LEVELS[Tier.SUMMIT] + SUMMIT_RISE


## What a chunk needs to know about its place in the map to build its own terrain: its ground
## level, and the ground level beyond each of its four sides. Derived from the tiers alone, so
## it is as much a pure function of the seed as everything else here.
static func context(tier_of: PackedInt32Array, index: int) -> Dictionary:
	var sides := PackedInt32Array()
	for side in 4:
		var other := neighbour_cell(index, side)
		sides.append(TerrainData.MAP_EDGE if other < 0 else base_level(tier_of[other]))
	## The mountain's ascent starts on whichever landward side faces the middle of the map.
	var toward := Vector2(GRID * 0.5 - 0.5 - index % GRID, GRID * 0.5 - 0.5 - index / GRID)
	var ascent := -1
	var best := -INF
	for side in 4:
		if sides[side] == TerrainData.MAP_EDGE:
			continue
		var score := toward.dot(Vector2(ChunkMesher.NEIGHBOUR_DX[side], ChunkMesher.NEIGHBOUR_DZ[side]))
		if score > best:
			best = score
			ascent = side
	return {"base": base_level(tier_of[index]), "sides": sides, "ascent_side": ascent}


## Context for a chunk considered on its own, with level ground all round it. Used by tests and
## tools that want one biome's terrain without a whole map.
static func lone_context(biome: BiomeData) -> Dictionary:
	var base := base_level(Tier.SEA if biome.id == &"beach" else
			(Tier.SUMMIT if biome.id == &"mountain" else Tier.GROUND))
	var sides := PackedInt32Array([base, base, base, base])
	if biome.id == &"beach":
		sides[0] = TerrainData.MAP_EDGE
	return {"base": base, "sides": sides, "ascent_side": 1}


## Terrain for one chunk.
static func heightmap(biome: BiomeData, rng: RandomNumberGenerator,
		ctx: Dictionary = {}) -> TerrainData:
	if ctx.is_empty():
		ctx = lone_context(biome)
	var size := CHUNK_TILES
	var base: int = ctx["base"]
	var terrain := TerrainData.new(size, base)
	terrain.side_levels = ctx["sides"]

	## A coarse random control grid, smoothly interpolated. Thresholding it is what produces
	## broad mesas with clean edges rather than a scatter of single raised tiles.
	var control := []
	for _i in (CONTROL_POINTS * CONTROL_POINTS):
		control.append(rng.randf())

	var centre := float(size - 1) * 0.5
	for z in size:
		for x in size:
			var value := _sample_control(control, float(x) / (size - 1), float(z) / (size - 1))
			var level := base
			## Mesas: optional high ground. Without the feather a single step is a wall, so
			## these are places a jump earns rather than terrain everyone has to cross.
			if biome.height_levels > 0 and value > biome.mesa_threshold:
				level = base + 1
				if biome.height_levels > 1 and value > biome.mesa_threshold + 0.1:
					level = base + 2

			match biome.id:
				&"mountain":
					level = _mountain_level(x, z, centre, base)
				&"lake":
					## The lake bed is level with the shore, under ankle-deep water: a place to
					## wade through, not a bowl to get stuck in.
					if Vector2(x - centre, z - centre).length() / centre < 0.55:
						level = base
				&"beach":
					level = _beach_level(terrain, x, z, value, base)

			## The rim sits at the chunk's ground level wherever another chunk lies beyond it,
			## so chunks tile together. Towards the edge of the map there is nothing to match.
			if _rim_to_neighbour(terrain, x, z) < BORDER:
				level = base
			terrain.heights[z * size + x] = level

	match biome.id:
		&"mountain":
			_carve_ascent(terrain, ctx["ascent_side"], base)
		&"beach":
			_smooth_shores(terrain)
	for side in 4:
		var beyond: int = terrain.side_levels[side]
		if beyond != TerrainData.MAP_EDGE and beyond < base:
			_carve_ramp(terrain, side, beyond, base, rng)

	terrain.bake()
	_carve_pits(terrain, biome, rng)
	_fill_unreachable(terrain)
	return terrain


## Square terraces stepping up from the rim to the summit platform.
static func _mountain_level(x: int, z: int, centre: float, base: int) -> int:
	var radial := Vector2(x - centre, z - centre).length()
	if radial <= ARENA_RADIUS_TILES + ARENA_SKIRT_TILES:
		## A dead-flat arena. The fight is about being shoved off an edge, and an edge only
		## reads as one if the floor leading up to it is level -- on bumpy ground a knockback
		## stops against a step instead.
		return base + SUMMIT_RISE
	var ring := maxf(absf(x - centre), absf(z - centre))
	var inward := centre - float(BORDER) - ring
	if inward <= 0.0:
		return base
	var terrace := int(inward / TERRACE_RISE) * TERRACE_RISE
	return base + mini(terrace, SUMMIT_RISE - TERRACE_RISE)


## The one way up the mountain: a straight ramp from the rim to the platform.
static func _carve_ascent(terrain: TerrainData, side: int, base: int) -> void:
	if side < 0:
		return
	var size := terrain.size
	var middle := size / 2
	for depth in range(BORDER, BORDER + SUMMIT_RISE + 1):
		for lane in range(middle - RAMP_WIDTH / 2, middle + RAMP_WIDTH / 2):
			var tile := _from_side(size, side, depth, lane)
			var index := tile.y * size + tile.x
			var step := depth - BORDER
			if step < SUMMIT_RISE:
				terrain.heights[index] = base + step
				terrain.slopes[index] = _rise_inward(side)
			else:
				terrain.heights[index] = base + SUMMIT_RISE
			terrain.reserved[index] = 1
	## The walkway round the rim stays clear where the ramp starts.
	for depth in range(0, BORDER):
		for lane in range(middle - RAMP_WIDTH / 2, middle + RAMP_WIDTH / 2):
			var tile := _from_side(size, side, depth, lane)
			terrain.reserved[tile.y * size + tile.x] = 1


## Sand, then shallows, then deeper water, in bands running out to whichever sides face the
## open sea, with the shoreline wobbling so it does not read as ruled.
static func _beach_level(terrain: TerrainData, x: int, z: int, value: float, base: int) -> int:
	var size := terrain.size
	var to_sea := 9999.0
	for side in 4:
		if terrain.side_levels[side] != TerrainData.MAP_EDGE:
			continue
		var distance := 0.0
		match side:
			0: distance = size - 1 - x
			1: distance = size - 1 - z
			2: distance = x
			3: distance = z
		to_sea = minf(to_sea, distance)
	to_sea += (value - 0.5) * 14.0
	if to_sea > 30.0:
		return base
	if to_sea > 14.0:
		return base - 1
	return base - 2


## Flags every tile that has higher ground one level up beside it, so the shore slopes into the
## water instead of dropping off a step nobody could walk back up.
static func _smooth_shores(terrain: TerrainData) -> void:
	var size := terrain.size
	for z in size:
		for x in size:
			var own := terrain.heights[z * size + x]
			var rises := false
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var nz: int = z + dz
					if terrain.in_bounds(nx, nz) and terrain.heights[nz * size + nx] == own + 1:
						rises = true
			if rises:
				terrain.slopes[z * size + x] = TerrainData.Slope.SMOOTH


## A ramp down to a lower neighbour, cut into this chunk from the shared border inward. It rises
## one level per tile -- 24 degrees, well inside what a body can walk -- and its far end comes out
## on this chunk's own ground.
static func _carve_ramp(terrain: TerrainData, side: int, beyond: int, base: int,
		rng: RandomNumberGenerator) -> void:
	var size := terrain.size
	var length := base - beyond
	## Somewhere in the middle half of the border, so ramps never run into a corner.
	var start := rng.randi_range(size / 4, size * 3 / 4 - RAMP_WIDTH)
	for depth in length + RAMP_LANDING:
		## One spare lane either side is levelled and kept clear, so the ramp has walls to walk
		## beside rather than a mesa hanging over it.
		for lane in range(start - 1, start + RAMP_WIDTH + 1):
			var tile := _from_side(size, side, depth, lane)
			var index := tile.y * size + tile.x
			terrain.reserved[index] = 1
			var on_ramp := lane >= start and lane < start + RAMP_WIDTH
			if on_ramp and depth < length:
				terrain.heights[index] = beyond + depth
				terrain.slopes[index] = _rise_inward(side)
			else:
				terrain.heights[index] = base
				terrain.slopes[index] = TerrainData.Slope.FLAT


## Tile `depth` tiles in from `side` of the chunk, `lane` tiles along it.
static func _from_side(size: int, side: int, depth: int, lane: int) -> Vector2i:
	match side:
		0: return Vector2i(size - 1 - depth, lane)
		1: return Vector2i(lane, size - 1 - depth)
		2: return Vector2i(depth, lane)
		_: return Vector2i(lane, depth)


## The slope that rises away from `side`, towards the middle of the chunk.
static func _rise_inward(side: int) -> int:
	match side:
		0: return TerrainData.Slope.RISE_NX
		1: return TerrainData.Slope.RISE_NZ
		2: return TerrainData.Slope.RISE_PX
		_: return TerrainData.Slope.RISE_PZ


## Distance to the nearest side that has a chunk beyond it; sides facing the edge of the map do
## not count, because there is nothing there to meet flush.
static func _rim_to_neighbour(terrain: TerrainData, x: int, z: int) -> int:
	var size := terrain.size
	var nearest := size
	if terrain.side_levels[0] != TerrainData.MAP_EDGE:
		nearest = mini(nearest, size - 1 - x)
	if terrain.side_levels[1] != TerrainData.MAP_EDGE:
		nearest = mini(nearest, size - 1 - z)
	if terrain.side_levels[2] != TerrainData.MAP_EDGE:
		nearest = mini(nearest, x)
	if terrain.side_levels[3] != TerrainData.MAP_EDGE:
		nearest = mini(nearest, z)
	return nearest


## A pit is a deliberate hazard now, not a texture: a biome gets a fixed handful, each a small
## blob punched into open ground well away from the rim and from any ramp.
static func _carve_pits(terrain: TerrainData, biome: BiomeData, rng: RandomNumberGenerator) -> void:
	var size := terrain.size
	var carved := 0
	for _attempt in biome.pit_count * 40:
		if carved >= biome.pit_count:
			break
		var x := rng.randi_range(BORDER + 5, size - BORDER - 6)
		var z := rng.randi_range(BORDER + 5, size - BORDER - 6)
		var radius := rng.randi_range(1, 2)
		if not _open_ground(terrain, x, z, radius + 2):
			continue
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				terrain.heights[(z + dz) * size + x + dx] = ChunkMesher.HOLE
		carved += 1


## Whether everything within `radius` tiles is flat, unreserved ground at the chunk's level.
static func _open_ground(terrain: TerrainData, x: int, z: int, radius: int) -> bool:
	var size := terrain.size
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var index := (z + dz) * size + x + dx
			if terrain.heights[index] != terrain.base_level or terrain.slopes[index] != 0 \
					or terrain.reserved[index] != 0:
				return false
	return true


## Ground at the chunk's level that cannot be walked to -- a pocket ringed by mesas -- is raised
## to join them. That keeps the promise the rest of the game relies on: anything standing at
## ground level can be reached on foot, and only the high ground asks for a jump.
static func _fill_unreachable(terrain: TerrainData) -> void:
	terrain.flood_reach()
	var size := terrain.size
	var changed := false
	for index in size * size:
		if terrain.reach[index] == 0 and terrain.heights[index] == terrain.base_level \
				and terrain.slopes[index] == 0:
			terrain.heights[index] = terrain.base_level + 1
			changed = true
	if changed:
		terrain.bake()
		terrain.flood_reach()


static func _sample_control(control: Array, u: float, v: float) -> float:
	var fx := u * (CONTROL_POINTS - 1)
	var fz := v * (CONTROL_POINTS - 1)
	var x0 := clampi(int(fx), 0, CONTROL_POINTS - 1)
	var z0 := clampi(int(fz), 0, CONTROL_POINTS - 1)
	var x1 := mini(x0 + 1, CONTROL_POINTS - 1)
	var z1 := mini(z0 + 1, CONTROL_POINTS - 1)
	## Smoothstep rather than linear: linear interpolation leaves visible creases along the
	## control grid lines once the values are rounded into levels.
	var tx := smoothstep(0.0, 1.0, fx - x0)
	var tz := smoothstep(0.0, 1.0, fz - z0)
	var top: float = lerp(control[z0 * CONTROL_POINTS + x0], control[z0 * CONTROL_POINTS + x1], tx)
	var bottom: float = lerp(control[z1 * CONTROL_POINTS + x0], control[z1 * CONTROL_POINTS + x1], tx)
	return lerp(top, bottom, tz)



## Centre of a chunk in world space, at ground level. The summit arena is built around this.
static func chunk_centre(index: int) -> Vector3:
	return chunk_origin(index) + Vector3(CHUNK_SIZE * 0.5, 0.0, CHUNK_SIZE * 0.5)


## World-space radius of the summit platform.
static func arena_radius() -> float:
	return ARENA_RADIUS_TILES * ChunkMesher.TILE_SIZE


static func chunk_origin(index: int) -> Vector3:
	return Vector3((index % GRID) * CHUNK_SIZE, 0.0, (index / GRID) * CHUNK_SIZE)


static func map_centre() -> Vector3:
	return Vector3(GRID * CHUNK_SIZE * 0.5, 0.0, GRID * CHUNK_SIZE * 0.5)

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
## Border tiles pinned to level 0 on every chunk, so neighbouring chunks always meet flush
## without any cross-chunk generation. It also guarantees a walkable path around every chunk.
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
## How far outside the platform the ground stays clear before the terraces resume, so the drop
## reads as a deliberate edge rather than as noise.
const ARENA_SKIRT_TILES := 3

## Exactly the distribution asked for: 1 Town, 3 Temple, 1 each of Desert/Lake/Forest/Mountain,
## 4 Plains, 4 Fields.
const COUNTS := {
	&"town": 1, &"temple": 3, &"desert": 1, &"lake": 1,
	&"forest": 1, &"mountain": 1, &"plains": 4, &"fields": 4,
}


## Returns 16 biome ids in row-major order.
static func layout(world_seed: int) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ 0x5EED
	var pool: Array[StringName] = []
	for id: StringName in COUNTS:
		for _i in COUNTS[id]:
			pool.append(id)

	## Reshuffle until the placement rules hold. Bounded rather than open-ended so a pathological
	## seed cannot hang the game; the last shuffle is used as-is if the budget runs out, which
	## still produces a playable map, just a less interesting one.
	var best: Array[StringName] = pool.duplicate()
	for _attempt in 200:
		_shuffle(pool, rng)
		best = pool.duplicate()
		if _satisfies_rules(best):
			return best
	return best


static func _satisfies_rules(cells: Array[StringName]) -> bool:
	var mountain := cells.find(&"mountain")
	var town := cells.find(&"town")
	## The mountain wants an edge so the summit reads as the top of something rather than a lump
	## in the middle of a field.
	if not _is_edge(mountain):
		return false
	## Town far from the mountain gives the run a journey: shop first, dragon last.
	if _chebyshev(town, mountain) < 2:
		return false
	if _chebyshev(cells.find(&"lake"), cells.find(&"desert")) < 2:
		return false
	return true


static func _is_edge(index: int) -> bool:
	var x := index % GRID
	var z := index / GRID
	return x == 0 or z == 0 or x == GRID - 1 or z == GRID - 1


static func _chebyshev(a: int, b: int) -> int:
	return maxi(absi(a % GRID - b % GRID), absi(a / GRID - b / GRID))


static func _shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = array[i]
		array[i] = array[j]
		array[j] = swap


## Terrain for one chunk, as tile levels. HOLE marks a pit.
static func heightmap(biome: BiomeData, rng: RandomNumberGenerator) -> PackedInt32Array:
	var size := CHUNK_TILES
	var heights := PackedInt32Array()
	heights.resize(size * size)

	## A coarse random control grid, smoothly interpolated and then rounded to integer levels.
	## Rounding after interpolation is what produces plateaus with clean edges rather than a
	## staircase of single tiles.
	var control := []
	for _i in (CONTROL_POINTS * CONTROL_POINTS):
		control.append(rng.randf())

	var centre := float(size - 1) * 0.5
	for z in size:
		for x in size:
			var value := _sample_control(control, float(x) / (size - 1), float(z) / (size - 1))
			var level := int(round(value * biome.roughness * biome.height_levels))

			match biome.id:
				&"mountain":
					## A cone, so the whole chunk is one climb ending at a summit big enough to
					## hold a boss fight -- and with a long way to fall off it.
					var radial := Vector2(x - centre, z - centre).length()
					var distance := maxf(absf(x - centre), absf(z - centre)) / centre
					var cone := (1.0 - distance) * biome.height_levels
					level = int(round(maxf(0.0, cone) + value * 1.2))
					if radial <= ARENA_RADIUS_TILES:
						## A dead-flat arena. The fight is about being shoved off an edge, and
						## an edge only reads as one if the floor leading up to it is level --
						## on bumpy ground a knockback stops against a step instead.
						level = biome.height_levels + 1
					elif radial <= ARENA_RADIUS_TILES + ARENA_SKIRT_TILES:
						## Two steps down all the way round. One step is a hop, so a single-step
						## lip would make being knocked off the platform no setback at all;
						## 1.8 m has to be climbed round, and anything shoved past the skirt
						## tumbles down the terraces below.
						level = biome.height_levels - 2
				&"lake":
					## Inverted: a bowl that fills with water.
					var distance := Vector2(x - centre, z - centre).length() / centre
					level = 0 if distance < 0.55 else level + 1

			level = clampi(level, 0, biome.height_levels)
			## The rim of every chunk sits at level 0 so chunks tile together seamlessly.
			var rim := mini(mini(x, z), mini(size - 1 - x, size - 1 - z))
			if rim < BORDER:
				level = 0
			elif rim < BORDER + 1:
				level = mini(level, 1)
			heights[z * size + x] = level

	_carve_pits(heights, size, biome, rng)
	return heights


## Pits are the ledges the whole knockback design leans on, so they are punched into open ground
## rather than tucked against cliffs where nobody would be fighting.
static func _carve_pits(heights: PackedInt32Array, size: int, biome: BiomeData,
		rng: RandomNumberGenerator) -> void:
	if biome.pit_chance <= 0.0:
		return
	for z in range(BORDER + 2, size - BORDER - 2):
		for x in range(BORDER + 2, size - BORDER - 2):
			if heights[z * size + x] != 0 or rng.randf() > biome.pit_chance:
				continue
			## Grow each pit to a small blob; single-tile holes read as bugs, not hazards.
			var radius := rng.randi_range(2, 4)
			for dz in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var px := x + dx
					var pz := z + dz
					if px < BORDER or pz < BORDER or px >= size - BORDER or pz >= size - BORDER:
						continue
					if heights[pz * size + px] == 0:
						heights[pz * size + px] = ChunkMesher.HOLE


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

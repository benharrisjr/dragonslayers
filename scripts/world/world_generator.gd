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

## Radius in tiles of the flat platform at the mountain's summit. 11 tiles is 44 m across --
## room for a 12.6 m dragon and four players to spread out and circle it, with an edge still
## close enough that a tail sweep can put someone over it.
## (It is no wider because the eight terraces, two tiles deep each, take the rest of the chunk.)
const ARENA_RADIUS_TILES := 11
## How far outside the platform the summit stays flat before the terraces drop away. None: eight
## terraces take every tile between the rim and the platform.
const ARENA_SKIRT_TILES := 0

## The map steps down from the mountain. Each chunk's tier is how far it is from the mountain
## chunk: the mountain itself, the highlands touching it, the ground beyond those, and -- for
## some of the chunks furthest away -- the sea.
enum Tier { SEA, GROUND, HIGHLANDS, SUMMIT }

## Ground level of each tier, in 1.5 m steps. The gaps are what the ramps climb: five tiles from
## the beach to the ground, eight from the ground to the highlands.
const TIER_LEVELS: Dictionary = {
	Tier.SEA: 1, Tier.GROUND: 6, Tier.HIGHLANDS: 14, Tier.SUMMIT: 14,
}
## The mountain's terraces: one for each dungeon, in Dungeon.IDS order from the bottom, each
## with that dungeon's shrine on it (MountainShrine).
const TERRACES := 8
## How much each mountain terrace rises. Four steps is 6 m: far more than the 2.3 m jump, so the
## terraces can be dropped down but not hopped back up, and the ramps are the way to the top.
const TERRACE_RISE := 4
## How far the summit platform stands above the mountain chunk's rim: a rise up to each terrace
## and one more to the platform, 54 m.
const SUMMIT_RISE := (TERRACES + 1) * TERRACE_RISE
## How deep each terrace is, rim to wall, in tiles: an outer row to walk round the mountain on,
## and an inner row the ramps up to the next terrace run along.
const TERRACE_DEPTH := 2
## The strip at rim level before the first wall: just the row the first ramps run along, with the
## chunk's rim walkway outside it.
const MOUNTAIN_FOOT := 1
## How long a mountain ramp is: one tile for each level it climbs.
const MOUNTAIN_RAMP := TERRACE_RISE
## Tile width of every ramp between chunks: room for the path up its middle with ground either side.
## Odd, so there is a middle.
const RAMP_WIDTH := 7

## The mountain is not boxed in by its chunk: away from its road, its lower terraces spill over
## into the chunks round it, in curves rather than along the chunk's edge. How far past the
## border they reach, at least and at most, in tiles -- short of the middle half of those chunks'
## far borders, where their ramps down are carved.
const SPILL_MIN := 3.0
const SPILL_MAX := 12.0
## On the road's face the terraces stay straight across the middle -- the zigzag and the shrines
## beside it need straight rows -- and only start to spill this many lanes either side of it,
## blending in over the next ROAD_FACE_BLEND.
const ROAD_FACE := 18.0
const ROAD_FACE_BLEND := 12.0
## How much the corners where two faces meet are rounded, as a share of the climb, and how much
## the terraces' edges wander on the faces that spill.
const CORNER_ROUND := 0.22
const MOUNTAIN_WOBBLE := 0.035
## Where the climb is complete, in tiles from the middle: inside this, the top terrace.
const PLATFORM_EDGE := (CHUNK_TILES - 1) * 0.5 - BORDER - MOUNTAIN_FOOT - TERRACES * TERRACE_DEPTH

## Where a chunk meets a lower one, its ground does not stop square at the border: it spills over
## into the lower chunk in lobes, this many tiles deep at least and at most, wandering along the
## border -- so the cliff between the two runs in curves, as the mountain's terraces do. The
## lower chunk carves the ramp up through them. Never past where that ramp's landing ends, so the
## landing always opens onto the lower ground.
const TIER_SPILL := Vector2(2.0, 10.5)

## Bluffs: a few tall plateaus in a row, each BLUFF_RISE above the ground, a ramp up the first
## and a plank bridge across the gap to each of the next -- high ground to cross by bridge.
const BLUFF_BIOMES: Array[StringName] = [&"plains", &"fields", &"forest", &"temple", &"desert"]
const BLUFF_RISE := 3
const BLUFF_RADIUS := Vector2i(4, 6)
const BLUFF_GAP := Vector2i(4, 7)
## In a chunk with a dungeon's entrance, the bluffs leave a square of open ground this wide
## somewhere for it: the largest entrance (the grove) and a tile round it.
const BLUFF_ENTRANCE_ROOM := 17
## Besides the road up the ascent side, ramps climb from each mountain terrace to the next, this
## many per terrace, scattered round the mountain -- so there are many ways up.
const TERRACE_RAMPS := 3
## Flat ground kept clear at the top of a ramp.
const RAMP_LANDING := 4
## Height of the sea's surface in metres: half a step, so the sand (one level) is dry and the
## shallows (level 0) are ankle deep.
const SEA_SURFACE := 0.45
## The lake's water stands this far above its shallows, which are a level below the shore and
## slope up to it.
const LAKE_SHALLOWS := 0.35
## The lake fills most of its chunk: a rounded square reaching most of the way to LAKE_MARGIN
## tiles from each border, wandering (lake_scale), and always LAKE_MARGIN clear of a border --
## LAKE_RAMP_MARGIN where a ramp up to a higher chunk has to fit, its landing open onto the shore.
const LAKE_MARGIN := 9.0
const LAKE_RAMP_MARGIN := 14.5
## Still water whose bed lies more than this below its surface is too deep to stand in.
const DEEP_WATER := 0.5

## The river: a pond on one of the mountain's terraces, then down through the chunks to the sea.
## It crosses each chunk border in one of these lanes -- near the corners, well clear of the
## ramps, which are carved in the middle half of a border.
const RIVER_LANES: Array[Vector2i] = [Vector2i(6, 9), Vector2i(54, 57)]
## The lanes it takes instead at a corner the mountain spills round.
const RIVER_MOUNTAIN_LANES: Array[Vector2i] = [Vector2i(20, 23), Vector2i(40, 43)]
## How far in from a border the river runs straight before it starts to wind. A straight stretch
## is where its bridge goes.
const RIVER_STRAIGHT := 12
## Half the river's width, in tiles, and how far its banks are kept clear of props.
const RIVER_RADIUS := 1.6
const RIVER_BANK := 2.8
## Its water lies this far below the banks; the bed is one level below them.
const RIVER_SURFACE_DROP := 0.3
const RIVER_POND_RADIUS := 2.8
## The river visits at least this many chunks if it can, so it winds rather than diving straight
## for the sea.
const RIVER_MIN_CELLS := 5
## Near its source -- on the mountain and through the highlands -- the river runs in a cut this
## much deeper than elsewhere, its water down between steeper banks. Below them the cut runs on
## until the bed first drops, so the water never has to come back up.
const RIVER_SINK := 1.0

const HIGHLAND_BIOMES: Array[StringName] = [&"temple", &"forest", &"plains", &"temple", &"fields"]
## Biomes that may be in either tier, but are always somewhere.
const ANYWHERE_BIOMES: Array[StringName] = [&"forest", &"plains", &"fields"]
## Where each dungeon's entrance is: [biome, tier] (tier -1 for either).
const DUNGEON_BIOMES: Dictionary = {
	&"well": [&"town", -1],
	&"fields": [&"fields", -1],
	&"desert": [&"desert", -1],
	&"plains": [&"plains", -1],
	&"forest": [&"forest", -1],
	&"temple_low": [&"temple", Tier.GROUND],
	&"temple_high": [&"temple", Tier.HIGHLANDS],
	&"lake": [&"lake", -1],
}
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

	## Every dungeon has its entrance in a particular biome, so every map has them all: a temple in
	## the highlands and another on the ground, a lake and a desert on the ground, and forest,
	## plains and fields somewhere. The highlands are three cells (mountain in a corner) or five,
	## and the ground has room for whatever they could not take.
	var highland_cells: Array[int] = []
	var other_ground: Array[int] = []
	for index in cells:
		if tier_of[index] == Tier.HIGHLANDS:
			highland_cells.append(index)
		elif tier_of[index] == Tier.GROUND and index != town:
			other_ground.append(index)
	var highland_list: Array[StringName] = [&"temple"]
	var rest := highland_pool.duplicate()
	rest.erase(&"temple")
	for biome: StringName in rest:
		if highland_list.size() >= highland_cells.size():
			break
		highland_list.append(biome)
	var ground_list: Array[StringName] = [&"lake", &"desert", &"temple"]
	for biome: StringName in ANYWHERE_BIOMES:
		if not highland_list.has(biome):
			ground_list.append(biome)
	var pool_next := 0
	while ground_list.size() < other_ground.size():
		ground_list.append(ground_pool[pool_next % ground_pool.size()])
		pool_next += 1
	_shuffle(highland_list, rng)
	_shuffle(ground_list, rng)

	for index in cells:
		match tier_of[index]:
			Tier.SUMMIT:
				biomes[index] = &"mountain"
			Tier.HIGHLANDS:
				biomes[index] = highland_list[highland_cells.find(index)]
			Tier.SEA:
				biomes[index] = &"beach"
			_:
				if index == town:
					biomes[index] = &"town"
				else:
					biomes[index] = ground_list[other_ground.find(index)]
	## The lake fills two chunks side by side, with dry land between it and the sea.
	var lakes := _place_lake(tier_of, biomes, town, world_seed)
	## Last, from the same generator, so adding it changed nothing above.
	var river := _plan_river(rng, tier_of, biomes)
	if not river.is_empty():
		river["lake"] = lakes
	var entrances := _plan_entrances(rng, tier_of, biomes)
	## The noise the mountain's outline is drawn from: not from the generator, so it moves nothing.
	return {"biomes": biomes, "tiers": tier_of, "river": river, "entrances": entrances,
			"shape_seed": hash(world_seed) & 0x7fffffff}


## The chunk each dungeon's entrance is in: {dungeon id: cell}. Where its biome turns up twice,
## one of them, at random.
static func _plan_entrances(rng: RandomNumberGenerator, tier_of: PackedInt32Array,
		biomes: Array) -> Dictionary:
	var entrances := {}
	for id: StringName in DUNGEON_BIOMES:
		var wanted: Array = DUNGEON_BIOMES[id]
		var options: Array[int] = []
		for index in biomes.size():
			if biomes[index] == wanted[0] and (wanted[1] < 0 or tier_of[index] == wanted[1]):
				options.append(index)
		if not options.is_empty():
			entrances[id] = options[rng.randi_range(0, options.size() - 1)]
	return entrances


## The river's route at chunk scale, and its shape inside each chunk it crosses: where it comes
## in, the bends it makes, and where it goes out. Downhill only -- it never enters a chunk of a
## higher tier than the one it left -- and never through the lake.
## Returns {"cells": [index, ...], "parts": {index: part}}, each part a dictionary of:
##   "entry": [side, lane] (absent on the mountain, which has "pond": Vector2 instead)
##   "exit": [side, lane], or "sea": side facing the open sea (on the beach, its last chunk)
##   "bends": Array of Vector2(t, offset): meanders, each a fraction of the way across the chunk
##            and how far to one side of the straight line it swings, in tiles
## Moves the lake to two ground chunks side by side, neither of them touching the sea (not even
## at a corner), and returns them -- the lake's first chunk and the one beside it. The second
## takes over a chunk whose biome the map has another of, so every dungeon's biome is still
## there; the lake's old chunk takes the first's biome. Where no pair fits, one chunk clear of
## the sea; where nothing fits, the lake stays where it was. A biome there is only one of -- the
## town, the desert -- moves to a chunk whose biome the map can spare. Its own generator.
static func _place_lake(tier_of: PackedInt32Array, biomes: Array, _town: int, world_seed: int) -> Array[int]:
	var old := biomes.find(&"lake")
	if old < 0:
		return []
	## One lake: any other chunk the fillers made a lake is plains instead.
	for cell in biomes.size():
		if cell != old and biomes[cell] == &"lake":
			biomes[cell] = &"plains"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ 0x1A4E5
	var clear := func(cell: int) -> bool:
		if cell < 0 or tier_of[cell] != Tier.GROUND:
			return false
		for other in tier_of.size():
			if tier_of[other] == Tier.SEA and _chebyshev(cell, other) <= 1:
				return false
		return true
	## A biome the map can spare a chunk of: another of it in the same tier, or for one that may
	## be anywhere, another of it at all.
	var spare := func(cell: int) -> bool:
		var biome: StringName = biomes[cell]
		if biome == &"lake" or biome == &"town":
			return biome == &"lake"
		var same_tier := 0
		var anywhere := 0
		for other in biomes.size():
			if other != cell and biomes[other] == biome:
				anywhere += 1
				if tier_of[other] == tier_of[cell]:
					same_tier += 1
		return same_tier > 0 or (ANYWHERE_BIOMES.has(biome) and anywhere > 0)
	var pairs: Array = []
	for first in biomes.size():
		if not clear.call(first):
			continue
		for side in 2:
			var second := neighbour_cell(first, side)
			if not clear.call(second):
				continue
			## Whichever of the two is not already the lake gives up its biome, so has to be one
			## the map can spare (the first, if not the lake, swaps places with it instead).
			var gives := first if second == old else second
			if spare.call(gives) or _home_for(biomes, tier_of, gives, [first, second, old], spare) >= 0:
				pairs.append([first, second])
	if not pairs.is_empty():
		var pair: Array = pairs[rng.randi_range(0, pairs.size() - 1)]
		var first: int = pair[0]
		var second: int = pair[1]
		## A biome the map has only the one of moves to a chunk the map can spare.
		var gives := first if second == old else second
		if not spare.call(gives):
			var home := _home_for(biomes, tier_of, gives, [first, second, old], spare)
			biomes[home] = biomes[gives]
		if old != first and old != second:
			biomes[old] = biomes[first]
			biomes[first] = &"lake"
			biomes[second] = &"lake"
		elif old == first:
			biomes[second] = &"lake"
		else:
			biomes[first] = &"lake"
		return [first, second]
	if clear.call(old):
		return [old]
	for cell in biomes.size():
		if clear.call(cell):
			biomes[old] = biomes[cell]
			biomes[cell] = &"lake"
			return [cell]
	return [old]


## A chunk the biome of `cell` can move to: the same tier, not one of `taken`, and with a biome the
## map can spare. -1 if there is none.
static func _home_for(biomes: Array, tier_of: PackedInt32Array, cell: int, taken: Array,
		spare: Callable) -> int:
	for other in biomes.size():
		if not taken.has(other) and other != cell and tier_of[other] == tier_of[cell] \
				and spare.call(other):
			return other
	return -1


static func _plan_river(rng: RandomNumberGenerator, tier_of: PackedInt32Array,
		biomes: Array) -> Dictionary:
	var mountain := biomes.find(&"mountain")
	if mountain < 0:
		return {}
	var ascent: int = context(tier_of, mountain)["ascent_side"]
	var best: Array[int] = []
	for _attempt in 80:
		var path: Array[int] = [mountain]
		var reached := false
		for _step in 14:
			var here := path[-1]
			var options: Array[int] = []
			var seas: Array[int] = []
			for side in 4:
				var next := neighbour_cell(here, side)
				if next < 0 or path.has(next) or biomes[next] == &"lake":
					continue
				if tier_of[next] > tier_of[here]:
					continue
				## Off the mountain on any side but the one its ascent ramp climbs.
				if here == mountain and side == ascent:
					continue
				if tier_of[next] == Tier.SEA:
					seas.append(next)
				else:
					options.append(next)
			if options.is_empty() and seas.is_empty():
				break
			var pick := -1
			## Reaching the sea early ends a winding river too soon: keep going while there is room.
			if not seas.is_empty() and (path.size() + 1 >= RIVER_MIN_CELLS or options.is_empty()):
				pick = seas[rng.randi_range(0, seas.size() - 1)]
			elif path.size() >= RIVER_MIN_CELLS:
				## Long enough: head for the nearest sea rather than wandering the whole map.
				options.sort_custom(func(a: int, b: int) -> bool:
						return _to_sea(a, tier_of) < _to_sea(b, tier_of))
				pick = options[0]
			else:
				pick = options[rng.randi_range(0, options.size() - 1)]
			path.append(pick)
			if tier_of[pick] == Tier.SEA:
				reached = true
				break
		if reached and path.size() > best.size():
			best = path
			if best.size() >= RIVER_MIN_CELLS:
				break
	if best.is_empty():
		return {}

	var parts := {}
	var size := CHUNK_TILES
	for step in best.size():
		var cell := best[step]
		var part := {"bends": []}
		if step > 0:
			var from := best[step - 1]
			part["entry"] = [_side_towards(cell, from), (parts[from]["exit"] as Array)[1]]
		if step < best.size() - 1:
			var exit_side := _side_towards(cell, best[step + 1])
			## Not at a corner whose other side faces the edge of the map: there the river would cut
			## off a sliver of ground between itself and the edge with no way back to the rest.
			## Off the mountain, at a corner the mountain is at, its terraces spill round and would
			## pen in a strip of ground between themselves and the river: there it crosses further
			## along. (Every chunk at such a corner is highland, so no ramp needs that stretch.)
			var allowed: Array[Vector2i] = []
			for option: Vector2i in RIVER_LANES:
				var low := option.x < size / 2
				var corner := _corner_side(exit_side, low)
				if neighbour_cell(cell, corner) >= 0:
					if cell != mountain and _corner_cells(cell, exit_side, corner).has(mountain):
						option = RIVER_MOUNTAIN_LANES[0 if low else 1]
					allowed.append(option)
			if allowed.is_empty():
				allowed = RIVER_LANES.duplicate()
			var lanes: Vector2i = allowed[rng.randi_range(0, allowed.size() - 1)]
			## Out at the far end of the border from where it came in, so it crosses the chunk
			## rather than hooking round a corner.
			if part.has("entry"):
				var entry: Array = part["entry"]
				var came_in := Vector2(_from_side(size, entry[0], 0, entry[1]))
				var best_gap := -1.0
				for option: Vector2i in allowed:
					var gap := came_in.distance_to(Vector2(_from_side(size, exit_side, 0,
							(option.x + option.y) / 2)))
					if gap > best_gap:
						best_gap = gap
						lanes = option
			part["exit"] = [exit_side, rng.randi_range(lanes.x, lanes.y)]
		else:
			## The beach: out towards whichever side faces the open sea.
			for side in 4:
				if neighbour_cell(cell, side) < 0:
					part["sea"] = side
					break
		if cell == mountain:
			## A pond high on the terraces, on the exit side, just below the summit platform: from
			## there it falls over every terrace on its way to the rim.
			var exit: Array = part["exit"]
			var tile := _from_side(size, exit[0], 15, rng.randi_range(size / 4, size * 3 / 4))
			part["pond"] = Vector2(tile) + Vector2(0.5, 0.5)
		## Meanders: evenly along the way across, swinging alternately to either side, so the river
		## winds without ever doubling back over itself.
		var count := 1 if part.has("sea") or cell == mountain else rng.randi_range(1, 3)
		var sway := 1.0 if rng.randf() < 0.5 else -1.0
		for bend in count:
			(part["bends"] as Array).append(Vector2(float(bend + 1) / (count + 1),
					sway * rng.randf_range(6.0, 12.0)))
			sway = -sway
		parts[cell] = part
	## The cut near the source, and what each chunk needs to know of its neighbours' along the river.
	for step in best.size():
		var part: Dictionary = parts[best[step]]
		part["sink"] = _river_sink(tier_of, best[step])
		part["entry_sink"] = _river_sink(tier_of, best[step - 1]) if step > 0 else 0.0
		part["exit_sink"] = part["sink"]
		if step == 1:
			part["mountain_part"] = parts[best[0]]
	var branch := _plan_branch(tier_of, biomes, best, parts, mountain)
	return {"cells": best, "parts": parts, "branch": branch}


static func _river_sink(tier_of: PackedInt32Array, cell: int) -> float:
	return RIVER_SINK if tier_of[cell] >= Tier.HIGHLANDS else 0.0


## The river's second arm: it splits off the main river in a chunk on the way and runs down to the
## lake, ending in it. The shortest way there that only goes downhill and crosses no other part of
## the river -- [the chunk it splits in, ..., the lake] -- or [] if there is none. The chunk it
## splits in gets a "branch": [side, lane] in its part; those after it, parts of their own, the
## lake's with "lake": true. Its own generator, so the main river is planned as it always was.
static func _plan_branch(tier_of: PackedInt32Array, biomes: Array, river: Array[int],
		parts: Dictionary, mountain: int) -> Array[int]:
	var came := {}
	var queue: Array[int] = []
	for cell in biomes.size():
		if biomes[cell] == &"lake":
			if river.has(cell):
				return []
			came[cell] = cell
			queue.append(cell)
	if queue.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(river) ^ 0xB4A
	## Out from the lake, only ever uphill or level, until the river is met.
	var found := -1
	var head := 0
	while head < queue.size() and found < 0:
		var here := queue[head]
		head += 1
		for side in 4:
			var next := neighbour_cell(here, side)
			if next < 0 or came.has(next) or tier_of[next] < tier_of[here] or next == mountain:
				continue
			if river.has(next):
				var part: Dictionary = parts[next]
				if part.has("entry") and part.has("exit"):
					came[next] = here
					found = next
					break
				continue
			came[next] = here
			queue.append(next)
	if found < 0:
		return []
	var path: Array[int] = [found]
	while came[path[-1]] != path[-1]:
		path.append(came[path[-1]])
	var size := CHUNK_TILES
	for step in path.size():
		var cell := path[step]
		var sink := _river_sink(tier_of, cell)
		var part: Dictionary = parts[cell] if step == 0 else {"bends": [], "sink": sink,
				"entry_sink": _river_sink(tier_of, path[step - 1]), "exit_sink": sink}
		if step > 0:
			var from := path[step - 1]
			var came_out: Array = parts[from]["branch"] if step == 1 else parts[from]["exit"]
			part["entry"] = [_side_towards(cell, from), came_out[1]]
		if step < path.size() - 1:
			var side := _side_towards(cell, path[step + 1])
			var allowed: Array[Vector2i] = []
			for option: Vector2i in RIVER_LANES:
				var low := option.x < size / 2
				var corner := _corner_side(side, low)
				if neighbour_cell(cell, corner) >= 0:
					if _corner_cells(cell, side, corner).has(mountain):
						option = RIVER_MOUNTAIN_LANES[0 if low else 1]
					allowed.append(option)
			if allowed.is_empty():
				allowed = RIVER_LANES.duplicate()
			var lanes: Vector2i = allowed[rng.randi_range(0, allowed.size() - 1)]
			part["branch" if step == 0 else "exit"] = [side, rng.randi_range(lanes.x, lanes.y)]
			if step > 0:
				(part["bends"] as Array).append(Vector2(0.5, (1.0 if rng.randf() < 0.5 else -1.0)
						* rng.randf_range(6.0, 10.0)))
		else:
			part["lake"] = true
		parts[cell] = part
	return path


## The four cells that meet at the corner of `cell` between `side` and `corner`.
static func _corner_cells(cell: int, side: int, corner: int) -> Array[int]:
	var across := neighbour_cell(cell, side)
	return [cell, across, neighbour_cell(cell, corner),
			neighbour_cell(across, corner) if across >= 0 else -1]


## The side that meets `side` at its low-lane end (`low`) or its high-lane end.
static func _corner_side(side: int, low: bool) -> int:
	if side == 0 or side == 2:
		return 3 if low else 1
	return 2 if low else 0


## Chunks between `cell` and the nearest sea chunk.
static func _to_sea(cell: int, tier_of: PackedInt32Array) -> int:
	var best := 99
	for other in tier_of.size():
		if tier_of[other] == Tier.SEA:
			best = mini(best, _chebyshev(cell, other))
	return best


## The side of `cell` that `other` (a neighbour) lies beyond.
static func _side_towards(cell: int, other: int) -> int:
	for side in 4:
		if neighbour_cell(cell, side) == other:
			return side
	return -1


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
## `river` is plan()["river"]; a chunk the river crosses gets its part of it.
## `entrances` is plan()["entrances"]; a chunk holding a dungeon's entrance gets its id.
## `shape_seed` is plan()["shape_seed"]; the mountain's outline is drawn from it, so every chunk
## it spills into has to be given the same one.
static func context(tier_of: PackedInt32Array, index: int, river: Dictionary = {},
		entrances: Dictionary = {}, shape_seed: int = 0) -> Dictionary:
	var sides := PackedInt32Array()
	for side in 4:
		var other := neighbour_cell(index, side)
		sides.append(TerrainData.MAP_EDGE if other < 0 else base_level(tier_of[other]))
	var part: Dictionary = (river.get("parts", {}) as Dictionary).get(index, {})
	var entrance: StringName = &""
	for id: StringName in entrances:
		if entrances[id] == index:
			entrance = id
	var ctx := {"base": base_level(tier_of[index]), "sides": sides,
			"ascent_side": _ascent_side(index), "river": part, "entrance": entrance,
			"tiers": tier_of, "cell": index, "shape_seed": shape_seed}
	var mountain := tier_of.find(Tier.SUMMIT)
	if mountain >= 0 and _chebyshev(index, mountain) <= 1:
		ctx["mountain"] = mountain_shape(mountain, index, shape_seed)
	var lakes: Array = river.get("lake", [])
	if lakes.has(index):
		ctx["lake"] = {"cells": lakes, "seed": shape_seed}
	return ctx


## The mountain's ascent starts on whichever landward side faces the middle of the map.
static func _ascent_side(index: int) -> int:
	var toward := Vector2(GRID * 0.5 - 0.5 - index % GRID, GRID * 0.5 - 0.5 - index / GRID)
	var ascent := -1
	var best := -INF
	for side in 4:
		if neighbour_cell(index, side) < 0:
			continue
		var score := toward.dot(Vector2(ChunkMesher.NEIGHBOUR_DX[side], ChunkMesher.NEIGHBOUR_DZ[side]))
		if score > best:
			best = score
			ascent = side
	return ascent


## What a chunk needs to draw its share of the mountain (mountain_level): where it lies from the
## mountain's chunk, in tiles, and how each of the mountain's faces spills -- 0 not at all (the
## edge of the map), 1 freely, 2 only either side of the road (the face it climbs).
static func mountain_shape(mountain: int, index: int, shape_seed: int) -> Dictionary:
	var spills := PackedInt32Array()
	var ascent := _ascent_side(mountain)
	for side in 4:
		if neighbour_cell(mountain, side) < 0:
			spills.append(0)
		else:
			spills.append(2 if side == ascent else 1)
	return {
		"offset": Vector2((index % GRID - mountain % GRID) * CHUNK_TILES,
				(index / GRID - mountain / GRID) * CHUNK_TILES),
		"spills": spills,
		"seed": shape_seed,
	}


## A mountain on its own, all of it inside its chunk, as it was before it spilled: for tests and
## a chunk built without a map round it.
static func lone_mountain_shape() -> Dictionary:
	return {"offset": Vector2.ZERO, "spills": PackedInt32Array([0, 0, 0, 0]), "seed": 0}


## The noise a mountain shape is drawn with, made once per chunk rather than per tile.
static func _shape_noise(shape: Dictionary) -> Dictionary:
	var wobble := FastNoiseLite.new()
	wobble.seed = int(shape["seed"])
	wobble.frequency = 0.045
	var reach := FastNoiseLite.new()
	reach.seed = int(shape["seed"]) + 77
	reach.frequency = 0.035
	var out := shape.duplicate()
	out["wobble"] = wobble
	out["reach"] = reach
	return out


## The mountain's level at tile (x, z) of a chunk, or -1 where the mountain does not reach.
##
## The shape is worked out in the mountain chunk's own tile coordinates, from the same seed in
## every chunk, so two chunks agree tile for tile along their border without either knowing about
## the other. Each face is a straight climb from its foot to the platform, scaled to however far
## that face reaches; the four are joined with a smooth minimum, which rounds the corners where
## they meet, and the faces that spill wander a little. On the road's face, within ROAD_FACE
## lanes of the middle, this comes out exactly as the old square terraces: foot, then TERRACES
## rows TERRACE_DEPTH deep, then the round platform.
static func mountain_level(shape: Dictionary, x: int, z: int) -> int:
	var centre := (CHUNK_TILES - 1) * 0.5
	var offset: Vector2 = shape["offset"]
	var d := Vector2(x + offset.x - centre, z + offset.y - centre)
	if d.length() <= ARENA_RADIUS_TILES + ARENA_SKIRT_TILES:
		## A dead-flat arena. The fight is about being shoved off an edge, and an edge only
		## reads as one if the floor leading up to it is level -- on bumpy ground a knockback
		## stops against a step instead.
		return summit_level()
	if maxf(absf(d.x), absf(d.y)) > centre + 1.0 + SPILL_MAX + 2.0:
		return -1
	var spills: PackedInt32Array = shape["spills"]
	var climbs := PackedFloat32Array()
	var shares := PackedFloat32Array()
	var lowest := INF
	for side in 4:
		var proj := d.dot(Vector2(ChunkMesher.NEIGHBOUR_DX[side], ChunkMesher.NEIGHBOUR_DZ[side]))
		var lane := d.y if side % 2 == 0 else d.x
		var share := 0.0
		if spills[side] == 1:
			share = 1.0
		elif spills[side] == 2:
			share = smoothstep(ROAD_FACE, ROAD_FACE + ROAD_FACE_BLEND, absf(lane))
		var extent := centre - BORDER
		if share > 0.0:
			## Out to the border, then on into the next chunk.
			var reach: FastNoiseLite = shape["reach"]
			var amount := clampf(reach.get_noise_1d(lane + side * 1000.0) * 0.7 + 0.5, 0.0, 1.0)
			extent += share * (BORDER + 0.5 + lerpf(SPILL_MIN, SPILL_MAX, amount))
		var climb := (extent - MOUNTAIN_FOOT - proj) / (extent - MOUNTAIN_FOOT - PLATFORM_EDGE)
		climbs.append(climb)
		shares.append(share)
		lowest = minf(lowest, climb)
	var height := climbs[0]
	for side in range(1, 4):
		height = _smooth_min(height, climbs[side], CORNER_ROUND)
	## The wander, on the faces that spill: weighted towards the face this tile is on, falling to
	## nothing once another face is clearly nearer, so the road's face is left exactly straight.
	var weight := 0.0
	var total := 0.0
	for side in 4:
		var near := maxf(0.0, 1.0 - (climbs[side] - lowest) / 0.15)
		weight += near * shares[side]
		total += near
	if weight > 0.0:
		var wobble: FastNoiseLite = shape["wobble"]
		height += wobble.get_noise_2d(d.x, d.y) * MOUNTAIN_WOBBLE * weight / total
	if height < 0.0:
		return -1
	var terrace := clampi(1 + floori(height * TERRACES + 0.00001), 1, TERRACES)
	return TIER_LEVELS[Tier.SUMMIT] + terrace * TERRACE_RISE


static func _smooth_min(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


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
	## The mountain, in its own chunk and in those round it it spills into.
	var shape: Dictionary = ctx.get("mountain", {})
	if shape.is_empty() and biome.id == &"mountain":
		shape = lone_mountain_shape()
	if not shape.is_empty():
		shape = _shape_noise(shape)
	if biome.id == &"lake":
		_frame_lake(terrain, ctx, rng.seed)
	var spill := _spill_context(ctx)
	var mountain_cell := -1
	if ctx.has("tiers"):
		mountain_cell = (ctx["tiers"] as PackedInt32Array).find(Tier.SUMMIT)
	terrain.owner.resize(size * size)
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
					level = base
				&"lake":
					## A ring of ankle-deep shallows a level below the shore, to wade round,
					## then down in steps into deep water. Nobody wades the middle: like the
					## river, going in there means being fished out.
					level = _lake_level(terrain, x, z)
				&"beach":
					level = _beach_level(terrain, x, z, value, base)

			## The rim sits at the chunk's ground level wherever another chunk lies beyond it,
			## so chunks tile together. Towards the edge of the map there is nothing to match.
			## (Except across the middle of a lake that fills two chunks: the water carries on.)
			if _rim_to_neighbour(terrain, x, z) < BORDER and (level >= base or biome.id != &"lake"):
				level = base
			## Higher chunks round about spilling over the border, and the mountain over
			## everything -- the rim too, where it spills across the border into the next chunk,
			## which works out the same level for its side. Whatever spills in is coloured as the
			## chunk it came from (terrain.owner).
			if not spill.is_empty():
				var spilled := tier_spill(spill, int(ctx["cell"]), x + 0.5, z + 0.5)
				if spilled.x > level:
					level = spilled.x
					terrain.owner[z * size + x] = spilled.y + 1
			if not shape.is_empty():
				var peak := mountain_level(shape, x, z)
				if peak >= level and peak >= 0:
					level = peak
					terrain.owner[z * size + x] = (mountain_cell if mountain_cell >= 0 else 0) + 1
			terrain.heights[z * size + x] = level
	_find_edge_levels(terrain, shape, spill, ctx)

	match biome.id:
		&"mountain":
			_carve_ascent(terrain, ctx["ascent_side"], base)
		&"beach":
			_shelve_sea(terrain)
			_smooth_shores(terrain)
		&"lake":
			_raise_islands(terrain, rng.seed)
			_smooth_lake_shores(terrain)
	## The river before the ramps, so each ramp can find a stretch of border the river is not on.
	var river: Dictionary = ctx.get("river", {})
	if river.has("mountain_part") and ctx.has("cell"):
		river = river.duplicate()
		river["bed_before"] = RiverCarver.mountain_bed(_shape_noise(mountain_shape(mountain_cell,
				mountain_cell, int(ctx.get("shape_seed", 0)))), river["mountain_part"])
	if not river.is_empty():
		RiverCarver.carve(terrain, river)
	if biome.id == &"mountain":
		_carve_terrace_ramps(terrain, rng)
	for side in 4:
		var beyond: int = terrain.side_levels[side]
		if beyond != TerrainData.MAP_EDGE and beyond > base:
			_carve_ramp(terrain, side, beyond, base, rng)
	## Once they are all cut, so none closes another's way out.
	for ramp in terrain.ramps:
		_open_landing(terrain, ramp)
	if biome.id == &"lake" or biome.id == &"beach":
		_smooth_landing_shores(terrain)
	## The desert dungeon's stairwell, after everything else that shapes the ground so it finds
	## somewhere left open, and before the pits so they keep clear of it. No random numbers: it
	## changes nothing else about the chunk.
	if ctx.get("entrance", &"") == &"desert":
		_carve_stairwell(terrain)
	## Last of the shaping, on whatever open ground is left, from a generator of its own.
	var entrance: StringName = ctx.get("entrance", &"")
	var room := 0 if entrance == &"" or entrance == &"desert" or entrance == &"lake" \
			else BLUFF_ENTRANCE_ROOM
	if room > 0 and not _has_open_square(terrain, room):
		_make_room(terrain, room)
	_raise_bluffs(terrain, biome, rng.seed, room)

	terrain.bake()
	_carve_pits(terrain, biome, rng)
	_fill_unreachable(terrain)
	_mark_deep_water(terrain, biome)
	_mark_ledges(terrain, biome, rng.seed)
	if ctx.has("layout") and ctx.has("tiers"):
		terrain.paint = GroundPaint.make(ctx["layout"], ctx["tiers"], int(ctx["cell"]), terrain,
				int(ctx.get("shape_seed", 0)))
	return terrain


## Shares of a chunk's cliffs that carry a ledge, and of a ledge's tiles left open as a gap.
const LEDGE_THRESHOLD := 0.12
const LEDGE_GAP_CHANCE := 0.12


## Picks the cliff tops that carry a ledge -- long runs of them, picked out by noise, with the
## odd tile left open as a gap to drop through. The foot of a ledged cliff is always ground that
## can be walked to anyway, so a ledge never cuts anywhere off from below; and high ground that
## can only be jumped up to always keeps an open stretch to jump up at. Never on the dragon's
## arena, pits, the river, deep water, ramps or their landings. Seeded from the chunk's
## generator without drawing from it, so nothing else about the chunk moves.
static func _mark_ledges(terrain: TerrainData, biome: BiomeData, seed_value: int) -> void:
	terrain.ledge.fill(0)
	if biome.id == &"beach":
		return
	var noise := FastNoiseLite.new()
	noise.seed = hash(seed_value) & 0x7fffffff
	noise.frequency = 0.07
	var size := terrain.size
	var half := (size - 1) * 0.5
	for z in range(1, size - 1):
		for x in range(1, size - 1):
			if not _ledge_top(terrain, x, z):
				continue
			if biome.id == &"mountain" and Vector2(x - half, z - half).length() \
					<= ARENA_RADIUS_TILES + ARENA_SKIRT_TILES + 1:
				continue
			if not _over_cliff(terrain, x, z) or noise.get_noise_2d(x, z) < LEDGE_THRESHOLD:
				continue
			var roll := float(hash(Vector3i(x, z, seed_value)) % 1000) / 1000.0
			if roll < LEDGE_GAP_CHANCE:
				continue
			terrain.ledge[z * size + x] = 1
	_keep_a_way_up(terrain)


## Ground a ledge may stand on: flat, dry, solid, shallow, and not a ramp's landing.
static func _ledge_top(terrain: TerrainData, x: int, z: int) -> bool:
	var index := z * terrain.size + x
	return terrain.heights[index] != ChunkMesher.HOLE and terrain.water[index] == 0 \
			and terrain.deep[index] == 0 and terrain.reserved[index] == 0 \
			and terrain.slopes[index] == TerrainData.Slope.FLAT


## Whether a tile stands over a cliff whose foot is ground anyone can walk to.
static func _over_cliff(terrain: TerrainData, x: int, z: int) -> bool:
	var own := terrain.heights[z * terrain.size + x]
	for side in 4:
		var nx := x + ChunkMesher.NEIGHBOUR_DX[side]
		var nz := z + ChunkMesher.NEIGHBOUR_DZ[side]
		if _ledge_footing(terrain, nx, nz) and terrain.heights[nz * terrain.size + nx] <= own - 1:
			return true
	return false


## High ground nobody can walk up to is reached by jumping up its cliffs; a ledge would stop
## that. Every such stretch keeps at least one open tile over walkable ground to jump up at --
## where none was left as a gap, the middle one of its cliff tops is opened.
static func _keep_a_way_up(terrain: TerrainData) -> void:
	var size := terrain.size
	var seen := PackedByteArray()
	seen.resize(size * size)
	for start in size * size:
		if seen[start] == 1 or terrain.reach[start] == 1 or terrain.ledge[start] == 0:
			continue
		## The stretch of high ground this ledged tile is on: everything walkable from it.
		var queue: Array[int] = [start]
		seen[start] = 1
		var head := 0
		var edges: Array[int] = []
		var open := false
		while head < queue.size():
			var index := queue[head]
			head += 1
			var x := index % size
			var z := index / size
			if _over_cliff(terrain, x, z):
				edges.append(index)
				if terrain.ledge[index] == 0:
					open = true
			for side in 4:
				if not terrain.can_walk(x, z, side):
					continue
				var next := (z + ChunkMesher.NEIGHBOUR_DZ[side]) * size + x + ChunkMesher.NEIGHBOUR_DX[side]
				if seen[next] == 0:
					seen[next] = 1
					queue.append(next)
		if not open and not edges.is_empty():
			terrain.ledge[edges[edges.size() / 2]] = 0


## Ground either end of a ledge may stand on: dry, solid, shallow and reachable on foot.
static func _ledge_footing(terrain: TerrainData, x: int, z: int) -> bool:
	if not terrain.in_bounds(x, z):
		return false
	var index := z * terrain.size + x
	return terrain.heights[index] != ChunkMesher.HOLE and terrain.water[index] == 0 \
			and terrain.deep[index] == 0 and terrain.reach[index] == 1


## Flags the still water too deep to stand in: wherever the lake's or the sea's bed lies more
## than DEEP_WATER below the surface. The river keeps its own rules (RiverCarver).
static func _mark_deep_water(terrain: TerrainData, biome: BiomeData) -> void:
	if biome.id == &"beach":
		terrain.still_surface = SEA_SURFACE
	elif biome.water_level >= 0:
		terrain.still_surface = ChunkMesher.height_to_world(terrain.base_level - 1) + LAKE_SHALLOWS
	else:
		return
	var size := terrain.size
	for z in size:
		for x in size:
			if terrain.is_hole(x, z) or terrain.is_water(x, z):
				continue
			if terrain.surface_level(x, z) * ChunkMesher.STEP_HEIGHT < terrain.still_surface - DEEP_WATER:
				terrain.deep[z * size + x] = 1


## How far the lake reaches in each direction, as a share of its usual radius, round the compass:
## a few slow swells and a quicker ripple, so its shore wanders in bays and points rather than
## running round a circle. Its own generator, seeded from the chunk's without drawing from it.
const LAKE_SHAPE_POINTS := 48
const LAKE_SCALE := Vector2(0.78, 1.15)


static func _lake_shape(seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(seed_value & 0x7fffffff, 0x1A4E))
	var waves: Array = []
	for frequency in [2, 3, 5]:
		waves.append([frequency, rng.randf() * TAU, rng.randf_range(0.5, 1.0) / frequency])
	var raw := PackedFloat32Array()
	var lowest := INF
	var highest := -INF
	for i in LAKE_SHAPE_POINTS:
		var angle := TAU * i / LAKE_SHAPE_POINTS
		var value := 0.0
		for wave: Array in waves:
			value += sin(angle * float(wave[0]) + float(wave[1])) * float(wave[2])
		raw.append(value)
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	var shape := PackedFloat32Array()
	for value in raw:
		shape.append(lerpf(LAKE_SCALE.x, LAKE_SCALE.y, (value - lowest) / maxf(highest - lowest, 0.001)))
	return shape


## The lake's reach at `angle` (radians, as Vector2.angle()), as a share of its usual radius; 1
## where the chunk has no lake shape.
static func lake_scale(terrain: TerrainData, angle: float) -> float:
	var shape := terrain.lake_shape
	if shape.is_empty():
		return 1.0
	var at := fposmod(angle, TAU) / TAU * shape.size()
	var i := int(at) % shape.size()
	var t := at - floorf(at)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(shape[i], shape[(i + 1) % shape.size()], t)


## The lake's bed at (x, z): a level down for the shallows, then two steps into deep water;
## the chunk's own level outside it.
static func _lake_level(terrain: TerrainData, x: float, z: float) -> int:
	var inward := lake_inward(terrain, x, z)
	var base := terrain.base_level
	if inward >= 4.5:
		return base - 3
	if inward >= 2.0:
		return base - 2
	if inward >= 0.0:
		return base - 1
	return base


## Where this chunk sits in its lake: "offset" (its corner in the lake's tile coordinates),
## "extent" (the lake's chunks, in tiles) and "shared" (the side the other half lies beyond, or -1),
## and the lake's outline, from a seed both halves share.
static func _frame_lake(terrain: TerrainData, ctx: Dictionary, seed_value: int) -> void:
	var lake: Dictionary = ctx.get("lake", {})
	var cells: Array = lake.get("cells", [])
	if cells.size() < 2 or not ctx.has("cell"):
		terrain.lake_shape = _lake_shape(seed_value)
		return
	var own: int = ctx["cell"]
	var a: int = cells[0]
	var b: int = cells[1]
	var corner := Vector2i(mini(a % GRID, b % GRID), mini(a / GRID, b / GRID))
	var extent := Vector2(CHUNK_TILES, CHUNK_TILES)
	if a / GRID == b / GRID:
		extent.x *= 2
	else:
		extent.y *= 2
	var shared := _side_towards(own, b if own == a else a)
	## How far it keeps from each border: the far end is this chunk's own, but along the sides
	## the two halves share, the wider of their two, so the shore runs straight on across.
	var margins := PackedFloat32Array([LAKE_MARGIN, LAKE_MARGIN, LAKE_MARGIN, LAKE_MARGIN])
	var tiers: PackedInt32Array = ctx.get("tiers", PackedInt32Array())
	for side in 4:
		if side == shared:
			continue
		var cells_for: Array = [own] if side == (shared + 2) % 4 else [a, b]
		for cell: int in cells_for:
			var beyond := neighbour_cell(cell, side)
			if beyond >= 0 and not tiers.is_empty() and tiers[beyond] > tiers[cell]:
				margins[side] = LAKE_RAMP_MARGIN
	terrain.lake_frame = {
		"offset": Vector2((own % GRID - corner.x) * CHUNK_TILES, (own / GRID - corner.y) * CHUNK_TILES),
		"extent": extent,
		"shared": shared,
		"margins": margins,
	}
	terrain.lake_shape = _lake_shape(int(lake.get("seed", 0)) ^ hash(cells))


## How far inside the lake a point is, in tiles (fractions and all, in the same tile coordinates as
## the heightmap): negative outside it. Its wandering edge, kept clear of the borders.
static func lake_inward(terrain: TerrainData, x: float, z: float) -> float:
	var size := terrain.size
	var frame := terrain.lake_frame
	## In the lake's own coordinates: one chunk, or two side by side.
	var extent: Vector2 = frame.get("extent", Vector2(size, size))
	var point := Vector2(x, z) + (frame.get("offset", Vector2.ZERO) as Vector2)
	var offset := point - (extent - Vector2.ONE) * 0.5
	var scale := lake_scale(terrain, offset.angle())
	## A rounded rectangle rather than an ellipse, so it reaches well into the corners, its
	## reach wandering round the compass.
	var half := extent * 0.5 - Vector2.ONE * LAKE_MARGIN
	var rounded := pow(pow(absf(offset.x) / half.x, 3.0) + pow(absf(offset.y) / half.y, 3.0), 1.0 / 3.0)
	var reach := remap(scale, LAKE_SCALE.x, LAKE_SCALE.y, 0.88, 1.12)
	var inward := (reach - rounded) * minf(half.x, half.y)
	var shared: int = frame.get("shared", -1)
	var margins: PackedFloat32Array = frame.get("margins", PackedFloat32Array())
	for side in 4:
		if side == shared:
			continue
		var beyond: int = terrain.side_levels[side]
		var margin := LAKE_RAMP_MARGIN if beyond != TerrainData.MAP_EDGE and beyond > terrain.base_level \
				else LAKE_MARGIN
		if not margins.is_empty():
			margin = margins[side]
		var from_edge: float = [size - 1 - x, size - 1 - z, x, z][side]
		inward = minf(inward, from_edge - margin)
	return inward


## Islands in the lake -- three to five, out in its deep water and clear of its middle, where the
## dungeon's way in is -- each joined by a plank bridge to the shore or to an island that is,
## so all of them can be walked to. Each bridge is a span for the reach flood. Its own generator.
static func _raise_islands(terrain: TerrainData, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(seed_value & 0x7fffffff, 0x151A))
	var size := terrain.size
	var base := terrain.base_level
	var centre := Vector2.ONE * (size - 1) * 0.5
	var islands: Array = []
	var owner := PackedInt32Array()
	owner.resize(size * size)
	owner.fill(-1)
	var wanted := rng.randi_range(3, 5)
	for _attempt in 160:
		if islands.size() >= wanted:
			break
		var angle := rng.randf() * TAU
		var middle := centre + Vector2(cos(angle), sin(angle)) * rng.randf_range(9.0, 22.0)
		var radius := rng.randf_range(2.2, 4.4)
		if not _island_fits(terrain, middle, radius, islands):
			continue
		for z in range(floori(middle.y - radius - 2), ceili(middle.y + radius + 3)):
			for x in range(floori(middle.x - radius - 2), ceili(middle.x + radius + 3)):
				var gap := Vector2(x, z).distance_to(middle)
				var index := z * size + x
				if gap <= radius:
					terrain.heights[index] = base
					owner[index] = islands.size()
				elif gap <= radius + 1.6 and terrain.heights[index] < base - 1:
					terrain.heights[index] = base - 1
		islands.append([middle, radius])
	## Bridges, shortest first, each from an island not yet joined to land that is.
	var joined := PackedByteArray()
	joined.resize(islands.size())
	for _round in islands.size():
		var best := {}
		for i in islands.size():
			if joined[i] == 1:
				continue
			for direction in 4:
				var bridge := _island_bridge(terrain, owner, i, islands[i][0], direction)
				if bridge.is_empty():
					continue
				var target: int = bridge["target"]
				if target >= 0 and joined[target] == 0:
					continue
				if best.is_empty() or int(bridge["length"]) < int(best["length"]):
					best = bridge
					best["island"] = i
		if best.is_empty():
			break
		joined[best["island"]] = 1
		var from: Vector2i = best["from"]
		var to: Vector2i = best["to"]
		for z in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				terrain.reserved[z * size + x] = 1
		var ends: Array = best["ends"]
		terrain.spans.append(Vector4i(ends[0].x, ends[0].y, ends[1].x, ends[1].y))
		terrain.bridges.append({"from": from, "to": to, "level": base,
				"along_x": best["along_x"]})


## Whether an island of `radius` fits at `middle`: on deep water all round, clear of the lake's
## middle and of the other islands.
static func _island_fits(terrain: TerrainData, middle: Vector2, radius: float, islands: Array) -> bool:
	var centre := Vector2.ONE * (terrain.size - 1) * 0.5
	if middle.distance_to(centre) < radius + 7.0:
		return false
	for other: Array in islands:
		if middle.distance_to(other[0]) < radius + float(other[1]) + 5.0:
			return false
	for z in range(floori(middle.y - radius - 3), ceili(middle.y + radius + 4)):
		for x in range(floori(middle.x - radius - 3), ceili(middle.x + radius + 4)):
			if not terrain.in_bounds(x, z) or terrain.level(x, z) > terrain.base_level - 2:
				return false
	return true


## A two-tile-wide bridge straight out from island `island` (centred at `middle`) in one of the
## four directions, over the water to the first land: {"from", "to" (tiles), "along_x", "length"
## (tiles of water), "target" (the island it lands on, or -1 for the shore), "ends" ([island
## tile, land tile])}, or {} if there is no land within reach that way.
static func _island_bridge(terrain: TerrainData, owner: PackedInt32Array, island: int,
		middle: Vector2, direction: int) -> Dictionary:
	var size := terrain.size
	var base := terrain.base_level
	var along_x := direction % 2 == 0
	var step := 1 if direction < 2 else -1
	var row := floori(middle.y if along_x else middle.x)
	var start := floori(middle.x if along_x else middle.y)
	var edges: Array[int] = []
	var lands: Array[int] = []
	var target := -2
	for lane in [row, row + 1]:
		var u := start
		var at := func(u_at: int) -> Vector2i:
			return Vector2i(u_at, lane) if along_x else Vector2i(lane, u_at)
		while terrain.in_bounds(at.call(u).x, at.call(u).y) and owner[at.call(u).y * size + at.call(u).x] == island:
			u += step
		var edge := u - step
		var water := 0
		while true:
			var tile: Vector2i = at.call(u)
			if not terrain.in_bounds(tile.x, tile.y) or water > 16:
				return {}
			var level := terrain.level(tile.x, tile.y)
			if level == base and not terrain.is_slope(tile.x, tile.y):
				break
			if level > base or level == ChunkMesher.HOLE:
				return {}
			water += 1
			u += step
		if water == 0:
			return {}
		var landed: int = owner[at.call(u).y * size + at.call(u).x]
		if target != -2 and landed != target:
			return {}
		target = landed
		edges.append(edge)
		lands.append(u)
	var lo := mini(mini(edges[0], edges[1]), mini(lands[0], lands[1]))
	var hi := maxi(maxi(edges[0], edges[1]), maxi(lands[0], lands[1]))
	var a := Vector2i(lo, row) if along_x else Vector2i(row, lo)
	var b := Vector2i(hi, row + 1) if along_x else Vector2i(row + 1, hi)
	return {
		"from": a, "to": b, "along_x": along_x, "length": hi - lo, "target": target,
		"ends": [Vector2i(edges[0], row) if along_x else Vector2i(row, edges[0]),
				Vector2i(lands[0], row) if along_x else Vector2i(row, lands[0])],
	}


## The lake's shallows slope up to whatever dry ground they meet -- the shore and the islands --
## so they can be waded into and out of.
static func _smooth_lake_shores(terrain: TerrainData) -> void:
	var size := terrain.size
	var base := terrain.base_level
	for z in size:
		for x in size:
			if terrain.heights[z * size + x] != base - 1:
				continue
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var nz: int = z + dz
					if terrain.in_bounds(nx, nz) and terrain.heights[nz * size + nx] == base:
						terrain.slopes[z * size + x] = TerrainData.Slope.SMOOTH


## The level of the ground just beyond each side, lane by lane (TerrainData.edge_levels): the next
## chunk's rim, which is its ground level -- or the mountain, where it spills across.
static func _find_edge_levels(terrain: TerrainData, shape: Dictionary, spill: Dictionary,
		ctx: Dictionary) -> void:
	var size := terrain.size
	terrain.edge_levels.clear()
	for side in 4:
		var levels := PackedInt32Array()
		levels.resize(size)
		levels.fill(terrain.side_levels[side])
		if terrain.side_levels[side] != TerrainData.MAP_EDGE:
			var other := neighbour_cell(int(ctx.get("cell", 0)), side) if ctx.has("cell") else -1
			for lane in size:
				var beyond := _from_side(size, side, -1, lane)
				if not shape.is_empty():
					levels[lane] = maxi(levels[lane], mountain_level(shape, beyond.x, beyond.y))
				if terrain.lake_frame.get("shared", -1) == side:
					## The lake carries on across: the other half works out the same water there.
					var water := _lake_level(terrain, beyond.x, beyond.y)
					if water < terrain.base_level:
						levels[lane] = water
						continue
				if not spill.is_empty() and other >= 0:
					## The tile as the next chunk sees it, in its own coordinates.
					var theirs := Vector2(beyond.x - ChunkMesher.NEIGHBOUR_DX[side] * size + 0.5,
							beyond.y - ChunkMesher.NEIGHBOUR_DZ[side] * size + 0.5)
					levels[lane] = maxi(levels[lane], tier_spill(spill, other, theirs.x, theirs.y).x)
		terrain.edge_levels.append(levels)


## What tier_spill needs: the tiers and the noise its lobes wander by. Empty without a map.
static func _spill_context(ctx: Dictionary) -> Dictionary:
	if not ctx.has("tiers") or not ctx.has("cell"):
		return {}
	var noise := FastNoiseLite.new()
	noise.seed = int(ctx.get("shape_seed", 0)) + 311
	## Slow enough that the lobes' edge never turns faster than the border it follows, so it
	## leaves no one-tile notches of low ground between them.
	noise.frequency = 0.02
	return {"tiers": ctx["tiers"], "noise": noise}


## How high the chunks round `cell` spill over into it at (x, z) -- in its tiles, fractions and
## all -- and which one: (level, cell), or (-1, -1) where nothing higher reaches. A higher chunk
## reaches TIER_SPILL tiles in, the depth wandering with noise taken over the whole map, so the
## two chunks either side of a border agree on it without knowing about each other.
static func tier_spill(spill: Dictionary, cell: int, x: float, z: float) -> Vector2i:
	var tiers: PackedInt32Array = spill["tiers"]
	var own := base_level(tiers[cell])
	var cx := cell % GRID
	var cz := cell / GRID
	var size := float(CHUNK_TILES)
	var best := Vector2i(-1, -1)
	var reach := -1.0
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nx: int = cx + dx
			var nz: int = cz + dz
			if nx < 0 or nz < 0 or nx >= GRID or nz >= GRID:
				continue
			var other := nz * GRID + nx
			var level := base_level(tiers[other])
			if level <= own or level <= best.x:
				continue
			var gap_x := maxf(maxf(dx * size - x, x - (dx * size + size)), 0.0)
			var gap_z := maxf(maxf(dz * size - z, z - (dz * size + size)), 0.0)
			var gap := Vector2(gap_x, gap_z).length()
			if gap >= TIER_SPILL.y:
				continue
			if reach < 0.0:
				var noise: FastNoiseLite = spill["noise"]
				reach = clampf(noise.get_noise_2d(cx * size + x, cz * size + z) * 0.8 + 0.5, 0.0, 1.0)
			## Short of the landing of a ramp up this high: its length, and the landing, less a
			## tile and a half to spare.
			var deepest := minf(TIER_SPILL.y, level - own + RAMP_LANDING - 1.5)
			if gap < lerpf(TIER_SPILL.x, deepest, reach):
				best = Vector2i(level, other)
	return best


## Bluffs: two or three tall plateaus in a row across open ground, BLUFF_RISE above it, with a ramp
## up the first and a plank bridge over the gap to each of the next -- so the far ones are reached
## along the top, and the ground under the bridges stays open to walk beneath. Each bridge is
## recorded in terrain.bridges ("kind" sky) and as a span the reach flood crosses. Its own
## generator, seeded from the chunk's without drawing from it. With `room`, only where they leave
## a square of open ground that wide.
static func _raise_bluffs(terrain: TerrainData, biome: BiomeData, seed_value: int,
		room: int = 0) -> void:
	if not BLUFF_BIOMES.has(biome.id):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(seed_value & 0x7fffffff, 0xB1F))
	var size := terrain.size
	var margin := BORDER + 3
	for _attempt in 60:
		var count := rng.randi_range(2, 3)
		var radii: Array[int] = []
		for i in count:
			radii.append(rng.randi_range(BLUFF_RADIUS.x, BLUFF_RADIUS.y))
		var gaps: Array[int] = []
		for i in count - 1:
			gaps.append(rng.randi_range(BLUFF_GAP.x, BLUFF_GAP.y))
		var along_x := rng.randf() < 0.5
		## Along the row: an approach and a ramp of BLUFF_RISE tiles, then each plateau and gap.
		var total := 2 + BLUFF_RISE
		for i in count:
			total += radii[i] * 2 + 1 + (gaps[i] if i < count - 1 else 0)
		if size - margin - total <= margin:
			continue
		var start := rng.randi_range(margin, size - margin - total)
		var row := rng.randi_range(margin + BLUFF_RADIUS.y + 1, size - margin - BLUFF_RADIUS.y - 2)
		var centres: Array[int] = []
		var at := start + 2 + BLUFF_RISE
		for i in count:
			centres.append(at + radii[i])
			at += radii[i] * 2 + 1 + (gaps[i] if i < count - 1 else 0)
		var phases := Vector2(rng.randf() * TAU, rng.randf() * TAU)
		if not _bluffs_fit(terrain, along_x, start, row, centres, radii, margin):
			continue
		var heights := terrain.heights.duplicate()
		var slopes := terrain.slopes.duplicate()
		var reserved := terrain.reserved.duplicate()
		var bridges := terrain.bridges.size()
		_carve_bluffs(terrain, along_x, start, row, centres, radii, phases)
		if room <= 0 or _has_open_square(terrain, room):
			return
		terrain.heights = heights
		terrain.slopes = slopes
		terrain.reserved = reserved
		terrain.bridges.resize(bridges)
		terrain.spans.resize(terrain.spans.size() - (centres.size() - 1))


## Where a dungeon's way in needs a square of open ground and the mesas have left none, the low
## mesas in the best place for one -- nearest the middle, with the fewest to level -- are
## levelled to the chunk's ground. Nothing else is moved: the river, ramps, the mountain and
## anything higher than a mesa are left where they are.
static func _make_room(terrain: TerrainData, width: int) -> void:
	var size := terrain.size
	var base := terrain.base_level
	var stride := size + 1
	var blocked := PackedInt32Array()
	var raised := PackedInt32Array()
	blocked.resize(stride * stride)
	raised.resize(stride * stride)
	for z in size:
		for x in size:
			var index := z * size + x
			var level := terrain.heights[index]
			var stops := 1 if terrain.water[index] != 0 or terrain.reserved[index] != 0 \
					or terrain.slopes[index] != 0 or level < base or level > base + 2 \
					or terrain.owner[index] != 0 or terrain.rim(x, z) < BORDER else 0
			var up := 1 if level > base else 0
			var at := (z + 1) * stride + x + 1
			blocked[at] = stops + blocked[z * stride + x + 1] + blocked[at - 1] - blocked[z * stride + x]
			raised[at] = up + raised[z * stride + x + 1] + raised[at - 1] - raised[z * stride + x]
	var best := Vector2i(-1, -1)
	var best_score := INF
	var middle := (size - width) * 0.5
	for z in range(0, size - width + 1):
		for x in range(0, size - width + 1):
			var corner := [z * stride + x, z * stride + x + width, (z + width) * stride + x,
					(z + width) * stride + x + width]
			if blocked[corner[3]] - blocked[corner[1]] - blocked[corner[2]] + blocked[corner[0]] > 0:
				continue
			var count: int = raised[corner[3]] - raised[corner[1]] - raised[corner[2]] + raised[corner[0]]
			var score := count * 4.0 + Vector2(x - middle, z - middle).length()
			if score < best_score:
				best_score = score
				best = Vector2i(x, z)
	if best.x < 0:
		return
	for z in range(best.y, best.y + width):
		for x in range(best.x, best.x + width):
			terrain.heights[z * size + x] = base


## Whether a square `width` tiles across of open ground -- flat, dry, unclaimed, at the chunk's
## level and off its rim -- is left anywhere in the chunk.
static func _has_open_square(terrain: TerrainData, width: int) -> bool:
	var size := terrain.size
	## Counts of open tiles above and to the left of each corner, so any square is four lookups.
	var sums := PackedInt32Array()
	sums.resize((size + 1) * (size + 1))
	for z in size:
		for x in size:
			var index := z * size + x
			var open := 1 if terrain.heights[index] == terrain.base_level \
					and terrain.slopes[index] == 0 and terrain.reserved[index] == 0 \
					and terrain.water[index] == 0 and terrain.rim(x, z) >= BORDER else 0
			sums[(z + 1) * (size + 1) + x + 1] = open + sums[z * (size + 1) + x + 1] \
					+ sums[(z + 1) * (size + 1) + x] - sums[z * (size + 1) + x]
	for z in range(0, size - width + 1):
		for x in range(0, size - width + 1):
			var count := sums[(z + width) * (size + 1) + x + width] - sums[z * (size + 1) + x + width] \
					- sums[(z + width) * (size + 1) + x] + sums[z * (size + 1) + x]
			if count == width * width:
				return true
	return false


## Tile (u, v) of a bluff row: u along it, v across it.
static func _bluff_tile(along_x: bool, u: int, v: int) -> Vector2i:
	return Vector2i(u, v) if along_x else Vector2i(v, u)


## Whether everything the bluffs take, and two tiles round it, is open, flat, dry ground at the
## chunk's level that nothing else has claimed.
static func _bluffs_fit(terrain: TerrainData, along_x: bool, start: int, row: int,
		centres: Array[int], radii: Array[int], margin: int) -> bool:
	var size := terrain.size
	var last := centres[-1] + radii[-1]
	for u in range(start - 1, last + 3):
		var reach := 4
		var on_bluff := false
		for i in centres.size():
			if absi(u - centres[i]) <= radii[i] + 2:
				reach = maxi(reach, radii[i] + 2)
				on_bluff = on_bluff or absi(u - centres[i]) <= radii[i]
		for v in range(row - reach, row + reach + 2):
			var tile := _bluff_tile(along_x, u, v)
			if not terrain.in_bounds(tile.x, tile.y) or terrain.rim(tile.x, tile.y) < margin - 1:
				return false
			var index := tile.y * size + tile.x
			if terrain.slopes[index] != 0 or terrain.reserved[index] != 0 \
					or terrain.water[index] != 0:
				return false
			## A bluff may rise over the low mesas; the way up it and the ground under its bridges
			## are open ground.
			var rise := terrain.heights[index] - terrain.base_level
			var open := not on_bluff and v >= row - 2 and v <= row + 3
			if rise < 0 or rise > (0 if open else 2):
				return false
	return true


static func _carve_bluffs(terrain: TerrainData, along_x: bool, start: int, row: int,
		centres: Array[int], radii: Array[int], phases: Vector2) -> void:
	var size := terrain.size
	var base := terrain.base_level
	var top := base + BLUFF_RISE
	## The plateaus: rounded blobs, their edges wandering by up to a tile, centred on the line
	## between the bridge's two rows (row and row + 1).
	for i in centres.size():
		var middle := Vector2(centres[i] + 0.5, row + 1.0)
		var r := radii[i]
		for u in range(centres[i] - r - 1, centres[i] + r + 2):
			for v in range(row - r - 1, row + r + 3):
				var offset := Vector2(u + 0.5, v + 0.5) - middle
				var angle := offset.angle()
				var edge := r + 0.55 * sin(3.0 * angle + phases.x + i) + 0.35 * sin(5.0 * angle + phases.y)
				## Square to the row where the bridges and the ramp meet it, so they meet a
				## straight edge exactly where they are built.
				var on_line := v >= row - 1 and v <= row + 2
				var inside := offset.length() <= edge
				if on_line:
					inside = absi(u - centres[i]) <= r
				if inside:
					var tile := _bluff_tile(along_x, u, v)
					terrain.heights[tile.y * size + tile.x] = top
	var reserve := func(u: int, v: int) -> void:
		var tile := _bluff_tile(along_x, u, v)
		terrain.reserved[tile.y * size + tile.x] = 1
	## The ramp up onto the first, rising along the row, with its landing and approach kept clear.
	var rise := TerrainData.Slope.RISE_PX if along_x else TerrainData.Slope.RISE_PZ
	var foot := centres[0] - radii[0] - BLUFF_RISE
	for v in range(row - 2, row + 4):
		for u in range(foot - 2, centres[0] - radii[0] + 2):
			reserve.call(u, v)
	for v in range(row - 1, row + 3):
		for step in BLUFF_RISE:
			var tile := _bluff_tile(along_x, foot + step, v)
			terrain.heights[tile.y * size + tile.x] = base + step
			terrain.slopes[tile.y * size + tile.x] = rise
	## A bridge across each gap, resting on the edge tile of the plateau at either end.
	for i in centres.size() - 1:
		var near := centres[i] + radii[i]
		var far := centres[i + 1] - radii[i + 1]
		for v in range(row - 1, row + 3):
			for u in range(near - 1, far + 2):
				reserve.call(u, v)
		var a := _bluff_tile(along_x, near, row)
		var b := _bluff_tile(along_x, far, row + 1)
		terrain.bridges.append({
			"from": Vector2i(mini(a.x, b.x), mini(a.y, b.y)),
			"to": Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)),
			"level": top,
			"along_x": along_x,
			"kind": &"sky",
		})
		var end := _bluff_tile(along_x, far, row)
		terrain.spans.append(Vector4i(a.x, a.y, end.x, end.y))


## The road up: on the ascent side, one ramp up every terrace, each turning back the way the one
## below came, so it zigzags up the middle of that face from the rim to the platform.
static func _carve_ascent(terrain: TerrainData, side: int, _base: int) -> void:
	if side < 0:
		return
	var middle := terrain.size / 2
	for step in SUMMIT_RISE / TERRACE_RISE:
		var heading := 1 if step % 2 == 0 else -1
		_carve_terrace_ramp(terrain, side, middle - 2 * heading, heading, step)


## Where the road up starts, as [side, lane, depth]: the rim tile at the foot of its first ramp.
static func ascent_foot_tile(side: int, size: int) -> Vector3i:
	return Vector3i(side, size / 2 - 3, BORDER - 1)


## More ramps from each terrace to the one above -- the summit platform counting as the last --
## TERRACE_RAMPS of them per terrace, wherever round the mountain they fit: clear of the road,
## the river and each other.
static func _carve_terrace_ramps(terrain: TerrainData, rng: RandomNumberGenerator) -> void:
	var size := terrain.size
	for step in SUMMIT_RISE / TERRACE_RISE:
		var placed: Array[Vector2i] = []
		var made := 0
		for _attempt in 80:
			if made >= TERRACE_RAMPS:
				break
			var side := rng.randi_range(0, 3)
			var lane := rng.randi_range(BORDER + 4, size - BORDER - 5)
			var crowded := false
			for other in placed:
				if other.x == side and absi(other.y - lane) < 10:
					crowded = true
			if crowded:
				continue
			var heading := 1 if rng.randf() < 0.5 else -1
			if _carve_terrace_ramp(terrain, side, lane, heading, step):
				placed.append(Vector2i(side, lane))
				made += 1


## One ramp up the `step`th rise, on the face of the mountain seen from `side`. It runs along the
## terrace, not into it: MOUNTAIN_RAMP tiles from `lane` in the direction `heading` (+1 or -1
## along the lanes), up the inner row of the lower terrace beside the wall, to a landing tile
## level with the terrace above, which is a step inward from it. The outer row is left as the way
## round. False, and nothing carved, if it does not fit there.
static func _carve_terrace_ramp(terrain: TerrainData, side: int, lane: int, heading: int,
		step: int) -> bool:
	var size := terrain.size
	var low := terrain.base_level + step * TERRACE_RISE
	var high := low + TERRACE_RISE
	var landing_lane := lane + MOUNTAIN_RAMP * heading
	var approach_lane := lane - heading
	if mini(landing_lane, approach_lane) < BORDER or maxi(landing_lane, approach_lane) >= size - BORDER:
		return false
	## The row: the last at the lower level before the wall, found where the landing goes.
	var row := -1
	for depth in range(BORDER, size / 2):
		var here := _from_side(size, side, depth, landing_lane)
		var inner := _from_side(size, side, depth + 1, landing_lane)
		if terrain.level(here.x, here.y) == low and terrain.level(inner.x, inner.y) == high:
			row = depth
			break
	if row < 0:
		return false
	## Every lane it uses: dry, flat and at the lower level along the row, with a walkway outside
	## it, and the terrace above (or the wall) inside it.
	for i in range(-1, MOUNTAIN_RAMP + 1):
		var along := lane + i * heading
		for depth in [row, row - 1]:
			var tile := _from_side(size, side, depth, along)
			var index := tile.y * size + tile.x
			if terrain.level(tile.x, tile.y) != low or terrain.water[index] == 1 \
					or terrain.slopes[index] != TerrainData.Slope.FLAT \
					or (depth == row and terrain.reserved[index] == 1):
				return false
		## Inside it, the wall up to the next terrace -- or, beside the round platform, a little
		## more of this terrace before the platform's edge; never a drop. The landing itself has
		## to step straight onto the terrace above.
		var inside := _from_side(size, side, row + 1, along)
		var beyond := terrain.level(inside.x, inside.y)
		if beyond < low or (along == landing_lane and beyond != high):
			return false
	var rise := _rise_along(side, heading)
	for i in MOUNTAIN_RAMP:
		var tile := _from_side(size, side, row, lane + i * heading)
		var index := tile.y * size + tile.x
		terrain.heights[index] = low + i
		terrain.slopes[index] = rise
		terrain.reserved[index] = 1
	var top := _from_side(size, side, row, landing_lane)
	terrain.heights[top.y * size + top.x] = high
	terrain.reserved[top.y * size + top.x] = 1
	var foot := _from_side(size, side, row, approach_lane)
	terrain.reserved[foot.y * size + foot.x] = 1
	return true


## The slope flag for a ramp rising along the lanes of `side`, in the direction `heading`.
static func _rise_along(side: int, heading: int) -> int:
	## Sides 0 and 2 count their lanes along z, sides 1 and 3 along x (see _from_side).
	if side == 0 or side == 2:
		return TerrainData.Slope.RISE_PZ if heading > 0 else TerrainData.Slope.RISE_NZ
	return TerrainData.Slope.RISE_PX if heading > 0 else TerrainData.Slope.RISE_NX


## Sand, then shallows, then a shelf dropping in two steps into deep water, in bands running out
## to whichever sides face the open sea, with the shoreline wobbling so it does not read as ruled.
## The shallows can be waded; past the drop the sea is too deep to stand in.
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
	if to_sea > 12.0:
		return base - 1
	if to_sea > 5.0:
		return base - 2
	return base - 3


## The stairwell down to the desert dungeon: STAIRWELL_WIDTH tiles across, walked down along +z
## -- three ramp tiles dropping a level each, then a landing at the bottom -- to the door in the
## wall at its far end. Placed on the open, flat ground nearest the chunk's middle, with a ring
## of it kept clear; recorded in terrain.stairwell.
const STAIRWELL_WIDTH := 3
const STAIRWELL_LENGTH := 6
const STAIRWELL_DEPTH := 3


static func _carve_stairwell(terrain: TerrainData) -> void:
	var size := terrain.size
	var centre := size / 2
	for radius in range(0, size / 2):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var x0 := centre + dx
				var z0 := centre + dz
				if _stairwell_fits(terrain, x0, z0):
					_dig_stairwell(terrain, x0, z0)
					return


## Whether the stairwell and two tiles of flat ground all round it fit with its corner at (x0, z0).
static func _stairwell_fits(terrain: TerrainData, x0: int, z0: int) -> bool:
	for z in range(z0 - 3, z0 + STAIRWELL_LENGTH + 2):
		for x in range(x0 - 2, x0 + STAIRWELL_WIDTH + 2):
			if not terrain.in_bounds(x, z) or terrain.rim(x, z) < BORDER + 1:
				return false
			var index := z * terrain.size + x
			if terrain.heights[index] != terrain.base_level or terrain.slopes[index] != 0 \
					or terrain.reserved[index] != 0 or terrain.water[index] != 0:
				return false
	return true


static func _dig_stairwell(terrain: TerrainData, x0: int, z0: int) -> void:
	var size := terrain.size
	for z in range(z0 - 3, z0 + STAIRWELL_LENGTH + 2):
		for x in range(x0 - 2, x0 + STAIRWELL_WIDTH + 2):
			terrain.reserved[z * size + x] = 1
	for row in STAIRWELL_LENGTH:
		for x in range(x0, x0 + STAIRWELL_WIDTH):
			var index := (z0 + row) * size + x
			if row < STAIRWELL_DEPTH:
				## High at its -z edge, a level lower at its +z edge.
				terrain.heights[index] = terrain.base_level - row - 1
				terrain.slopes[index] = TerrainData.Slope.RISE_NZ
			else:
				terrain.heights[index] = terrain.base_level - STAIRWELL_DEPTH
	terrain.stairwell = Rect2i(x0, z0, STAIRWELL_WIDTH, STAIRWELL_LENGTH)


## Deep water never meets the sand: wherever it comes within SEA_SHELF tiles of dry ground --
## mostly where a chunk's rim runs out as a sand walkway -- the sea bed is raised to the
## shallows, so there is always some wading between the beach and the drop.
const SEA_SHELF := 2


static func _shelve_sea(terrain: TerrainData) -> void:
	var size := terrain.size
	var base := terrain.base_level
	var raised := PackedInt32Array()
	for z in size:
		for x in size:
			if terrain.heights[z * size + x] >= base - 1:
				continue
			var near_sand := false
			for dz in range(-SEA_SHELF, SEA_SHELF + 1):
				for dx in range(-SEA_SHELF, SEA_SHELF + 1):
					if terrain.in_bounds(x + dx, z + dz) \
							and terrain.heights[(z + dz) * size + x + dx] >= base:
						near_sand = true
			if near_sand:
				raised.append(z * size + x)
	for index in raised:
		terrain.heights[index] = base - 1


## Flags every tile that has higher ground one level up beside it, so the shore slopes into the
## water instead of dropping off a step nobody could walk back up. Only the beach and its
## shallows: the shelf beyond them is meant to drop away, so deep water has an edge to see.
static func _smooth_shores(terrain: TerrainData) -> void:
	var size := terrain.size
	for z in size:
		for x in size:
			var own := terrain.heights[z * size + x]
			if own < terrain.base_level - 1:
				continue
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
	var length := beyond - base
	## Somewhere in the middle half of the border, so ramps never run into a corner -- and,
	## where the river is near, somewhere it is not.
	var start := rng.randi_range(size / 4, size * 3 / 4 - RAMP_WIDTH)
	if _ramp_meets_river(terrain, side, start, length):
		## Every position along the middle half, nearest the roll first, until one is clear.
		var rolled := start
		for offset in range(1, size / 2):
			var found := false
			for candidate in [rolled + offset, rolled - offset]:
				if candidate >= size / 4 and candidate <= size * 3 / 4 - RAMP_WIDTH \
						and not _ramp_meets_river(terrain, side, candidate, length):
					start = candidate
					found = true
					break
			if found:
				break
	terrain.ramps.append({"side": side, "start": start, "length": length})
	for depth in length + RAMP_LANDING:
		## Up from this chunk's ground to the border, through the higher chunk's lobes, its top
		## flush with the higher chunk's rim. A spare lane either side is kept clear, and the
		## landing at its foot levelled, so it always opens onto this chunk's own ground.
		for lane in range(start - 1, start + RAMP_WIDTH + 1):
			var tile := _from_side(size, side, depth, lane)
			var index := tile.y * size + tile.x
			terrain.reserved[index] = 1
			var on_ramp := lane >= start and lane < start + RAMP_WIDTH
			if on_ramp and depth < length:
				terrain.heights[index] = beyond - 1 - depth
				terrain.slopes[index] = _rise_outward(side)
			elif depth >= length:
				terrain.heights[index] = base
				terrain.slopes[index] = TerrainData.Slope.FLAT
				terrain.owner[index] = 0


## A landing reaching out into the lake's or the sea's shallows has a shore too.
static func _smooth_landing_shores(terrain: TerrainData) -> void:
	var size := terrain.size
	for ramp in terrain.ramps:
		for depth in range(int(ramp["length"]), int(ramp["length"]) + RAMP_LANDING):
			for lane in range(int(ramp["start"]) - 1, int(ramp["start"]) + RAMP_WIDTH + 1):
				var tile := _from_side(size, ramp["side"], depth, lane)
				for dz in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var x: int = tile.x + dx
						var z: int = tile.y + dz
						var index := z * size + x
						if terrain.in_bounds(x, z) and terrain.heights[index] == terrain.base_level - 1 \
								and terrain.slopes[index] == TerrainData.Slope.FLAT \
								and terrain.water[index] == 0 and terrain.reserved[index] == 0:
							terrain.slopes[index] = TerrainData.Slope.SMOOTH


## Mesas can box a ramp's landing in. Where they do, the way out through the fewest of them is
## levelled to the chunk's ground, so the ramp always leads somewhere.
static func _open_landing(terrain: TerrainData, ramp: Dictionary) -> void:
	var size := terrain.size
	var base := terrain.base_level
	var takes := func(index: int) -> bool:
		var level := terrain.heights[index]
		return terrain.slopes[index] == TerrainData.Slope.FLAT and terrain.water[index] == 0 \
				and (level == base or (level > base and level <= base + 2
				and terrain.owner[index] == 0 and terrain.reserved[index] == 0))
	## The ground joined to the rim already.
	var open := PackedByteArray()
	open.resize(size * size)
	var queue: Array[int] = []
	for z in size:
		for x in size:
			var index := z * size + x
			if terrain.rim(x, z) == 0 and terrain.heights[index] == base and takes.call(index):
				open[index] = 1
				queue.append(index)
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for side in 4:
			var x := at % size + ChunkMesher.NEIGHBOUR_DX[side]
			var z := at / size + ChunkMesher.NEIGHBOUR_DZ[side]
			if not terrain.in_bounds(x, z):
				continue
			var next := z * size + x
			if open[next] == 0 and terrain.heights[next] == base and takes.call(next):
				open[next] = 1
				queue.append(next)
	var foot := _from_side(size, ramp["side"], int(ramp["length"]) + 1, int(ramp["start"]) + RAMP_WIDTH / 2)
	if open[foot.y * size + foot.x] == 1:
		return
	var from := {foot.y * size + foot.x: -1}
	var now: Array[int] = [foot.y * size + foot.x]
	var later: Array[int] = []
	var done := {}
	while not now.is_empty() or not later.is_empty():
		if now.is_empty():
			now = later
			later = []
		var at: int = now.pop_back()
		if done.has(at):
			continue
		done[at] = true
		if open[at] == 1:
			while at >= 0:
				for dz in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var x: int = at % size + dx
						var z: int = at / size + dz
						if terrain.in_bounds(x, z) and takes.call(z * size + x):
							terrain.heights[z * size + x] = base
							terrain.reserved[z * size + x] = 1
				at = from[at]
			return
		for side in 4:
			var x := at % size + ChunkMesher.NEIGHBOUR_DX[side]
			var z := at / size + ChunkMesher.NEIGHBOUR_DZ[side]
			var next := z * size + x
			if not terrain.in_bounds(x, z) or done.has(next) or not takes.call(next):
				continue
			var free: bool = terrain.heights[next] == base
			if free or not from.has(next):
				from[next] = at
				(now if free else later).append(next)


static func _ramp_meets_river(terrain: TerrainData, side: int, start: int, length: int) -> bool:
	for depth in length + RAMP_LANDING + 1:
		for lane in range(start - 2, start + RAMP_WIDTH + 2):
			var tile := _from_side(terrain.size, side, depth, clampi(lane, 0, terrain.size - 1))
			if terrain.is_water(tile.x, tile.y):
				return true
	return false


## Tile `depth` tiles in from `side` of the chunk, `lane` tiles along it.
static func _from_side(size: int, side: int, depth: int, lane: int) -> Vector2i:
	match side:
		0: return Vector2i(size - 1 - depth, lane)
		1: return Vector2i(lane, size - 1 - depth)
		2: return Vector2i(depth, lane)
		_: return Vector2i(lane, depth)


## The slope that rises towards `side`, out of the chunk.
static func _rise_outward(side: int) -> int:
	match side:
		0: return TerrainData.Slope.RISE_PX
		1: return TerrainData.Slope.RISE_PZ
		2: return TerrainData.Slope.RISE_NX
		_: return TerrainData.Slope.RISE_NZ


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

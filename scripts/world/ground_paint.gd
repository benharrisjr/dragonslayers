class_name GroundPaint
extends RefCounted

## How a chunk's ground is coloured where it meets its neighbours, so there is no hard cut from
## one biome's colours to the next along the chunk's straight edge.
##
## The map is painted in order of height, the mountain first. Ground that came from another chunk
## -- the mountain's terraces where they spill over, a higher chunk's lobes over a border
## (TerrainData.owner) -- takes that chunk's colours, so the colours change at the cliff it ends
## in. Between chunks at the same height the colours blend across a border that wanders: each
## point is coloured as whichever chunk lies under it once it has been pushed about by noise taken
## over the whole map, softened over a few metres either side.
##
## The mesher works out each vertex's colour for its own chunk as before; this shifts it by the
## difference between what is painted there and the chunk's own colours (tint).

## How far the border between two chunks wanders, and how wide the blend across it is, in tiles.
const WANDER := 11.0
const BLEND := 4.0

enum Kind { GROUND, CLIFF }

var cell: int = 0
var base_level: int = 0
## Per chunk of the map: [ground, low ground, cliff] colours, and its ground level.
var _palettes: Array = []
var _bases := PackedInt32Array()
var _owner := PackedByteArray()
var _size: int = 0
## The blended [ground, low, cliff] at every tile corner of the chunk, for chunk-local lookups.
var _grid: Array = [PackedColorArray(), PackedColorArray(), PackedColorArray()]
var _plain := true


static func make(layout: Array, tiers: PackedInt32Array, cell_index: int, terrain: TerrainData,
		seed_value: int) -> GroundPaint:
	var paint := GroundPaint.new()
	paint.cell = cell_index
	paint.base_level = terrain.base_level
	paint._size = terrain.size
	paint._owner = terrain.owner
	for index in layout.size():
		var biome := BiomeLibrary.get_biome(layout[index])
		paint._palettes.append([Season.ground_color(biome.id, biome.ground_color),
				Season.ground_color(biome.id, biome.low_color),
				Season.cliff_color(biome.id, biome.cliff_color)])
		paint._bases.append(WorldGenerator.base_level(tiers[index]))
	paint._paint_grid(seed_value)
	return paint


## The blend at every tile corner of this chunk.
func _paint_grid(seed_value: int) -> void:
	var warp_x := FastNoiseLite.new()
	warp_x.seed = seed_value + 501
	warp_x.frequency = 0.022
	var warp_z := FastNoiseLite.new()
	warp_z.seed = seed_value + 907
	warp_z.frequency = 0.022
	var tiles := float(WorldGenerator.CHUNK_TILES)
	var grid := WorldGenerator.GRID
	var origin := Vector2(cell % grid, cell / grid) * tiles
	var own: Array = _palettes[cell]
	var layers: Array[PackedColorArray] = []
	for k in 3:
		var layer := PackedColorArray()
		layer.resize((_size + 1) * (_size + 1))
		layers.append(layer)
	for z in _size + 1:
		for x in _size + 1:
			var point := origin + Vector2(x, z)
			var pushed := point + Vector2(warp_x.get_noise_2d(point.x, point.y),
					warp_z.get_noise_2d(point.x, point.y)) * WANDER * 1.6
			## Which chunks it falls between, and how far across: blended only near a border.
			var u := pushed / tiles - Vector2(0.5, 0.5)
			var i0 := Vector2i(floori(u.x), floori(u.y))
			var f := u - Vector2(i0)
			var soft := BLEND / tiles
			var wx := smoothstep(0.5 - soft, 0.5 + soft, f.x)
			var wz := smoothstep(0.5 - soft, 0.5 + soft, f.y)
			var sums: Array[Color] = [Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]
			var total := 0.0
			for dz in 2:
				for dx in 2:
					var cx := clampi(i0.x + dx, 0, grid - 1)
					var cz := clampi(i0.y + dz, 0, grid - 1)
					var other := cz * grid + cx
					## Only chunks at this one's height: a higher or lower one meets it at a cliff.
					if _bases[other] != base_level:
						continue
					var weight := (wx if dx == 1 else 1.0 - wx) * (wz if dz == 1 else 1.0 - wz)
					if weight <= 0.0:
						continue
					for k in 3:
						sums[k] += (_palettes[other][k] as Color) * weight
					total += weight
			for k in 3:
				var color: Color = own[k] if total <= 0.0001 else sums[k] / total
				layers[k][z * (_size + 1) + x] = color
				if not color.is_equal_approx(own[k]):
					_plain = false
	_grid = [layers[0], layers[1], layers[2]]


## `color`, worked out from this chunk's own colours, shifted to what is painted at `point`
## (chunk-local metres). `kind` is ground or cliff; `tile` is the tile whose ground it belongs to.
func tint(color: Color, point: Vector3, kind: int, tile: Vector2i) -> Color:
	var which := 2 if kind == Kind.CLIFF else (1 if point.y < base_level * ChunkMesher.STEP_HEIGHT - 0.01 else 0)
	var own: Color = _palettes[cell][which]
	var target: Color
	var x := clampi(tile.x, 0, _size - 1)
	var z := clampi(tile.y, 0, _size - 1)
	var owner := _owner[z * _size + x] if not _owner.is_empty() else 0
	if owner > 0 and owner - 1 != cell:
		target = _palettes[owner - 1][which]
	elif owner > 0 or _plain:
		return color
	else:
		var at := Vector2(point.x, point.z) / ChunkMesher.TILE_SIZE
		at = at.clamp(Vector2.ZERO, Vector2(_size, _size))
		var x0 := mini(floori(at.x), _size - 1)
		var z0 := mini(floori(at.y), _size - 1)
		var fx := at.x - x0
		var fz := at.y - z0
		var grid: PackedColorArray = _grid[which]
		var width := _size + 1
		target = grid[z0 * width + x0].lerp(grid[z0 * width + x0 + 1], fx).lerp(
				grid[(z0 + 1) * width + x0].lerp(grid[(z0 + 1) * width + x0 + 1], fx), fz)
	var shifted := color + (target - own)
	shifted.a = color.a
	return shifted

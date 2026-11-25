class_name MapScreen
extends Control

## The whole map from overhead, opened with M.
##
## It is a picture painted from the generated terrain rather than a second camera looking down:
## one pixel per tile, coloured by biome and shaded by height, with cliffs, water, pits, trees
## and rocks marked. That costs nothing while it is open -- a top-down render of a 512 m world
## would draw every chunk again -- and it reads better than the real thing does from a kilometre
## up. Players and the dragon are drawn over it live.
##
## The match keeps running underneath and nobody's controls are taken away: it is a glance, not
## a pause. North is the top of the picture (world -Z).

const BACKDROP := Color(0.03, 0.05, 0.07, 0.78)
const WATER := Color(0.25, 0.5, 0.75)
const PIT := Color(0.06, 0.05, 0.07)
const TREE := Color(0.1, 0.32, 0.16)
const ROCK := Color(0.42, 0.42, 0.44)
## How much of the smaller window dimension the map fills.
const FILL := 0.82

var world: GameWorld

var _texture: ImageTexture
## World-space rectangle the picture covers, on the XZ plane.
var _world_rect: Rect2


func setup(game_world: GameWorld) -> void:
	world = game_world
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	_paint()


func toggle() -> void:
	visible = not visible
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## Paints the terrain once. Nothing drawn here changes during a match except burnt trees, which
## are not worth repainting for.
func _paint() -> void:
	var tiles := WorldGenerator.CHUNK_TILES
	var side := tiles * WorldGenerator.GRID
	var span := side * ChunkMesher.TILE_SIZE
	_world_rect = Rect2(Vector2.ZERO, Vector2(span, span))
	var image := Image.create(side, side, false, Image.FORMAT_RGB8)
	image.fill(PIT)
	var top := float(WorldGenerator.summit_level())

	for chunk in world.chunks:
		var origin := Vector2i(roundi(chunk.global_position.x / ChunkMesher.TILE_SIZE),
				roundi(chunk.global_position.z / ChunkMesher.TILE_SIZE))
		var lake := chunk.biome.id == &"lake"
		var sea := chunk.biome.id == &"beach"
		var half := (tiles - 1) * 0.5
		for z in tiles:
			for x in tiles:
				var level := chunk.heights[z * tiles + x]
				var color := PIT
				if level != ChunkMesher.HOLE:
					## Higher ground is lighter, so the tiers read at a glance.
					color = Season.ground_color(chunk.biome.id, chunk.biome.ground_color).lerp(Color.WHITE, 0.4 * level / top) \
							.darkened(0.25 * (1.0 - level / top))
					## A drop to the south or east draws a dark edge: the cliffs and mesas.
					if _drops(chunk, x + 1, z, level) or _drops(chunk, x, z + 1, level):
						color = color.darkened(0.35)
					if chunk.terrain.is_bridge(x, z):
						color = RiverBuilder.WOOD
					elif chunk.terrain.is_water(x, z):
						color = Color(0.2, 0.5, 0.85)
					elif chunk.terrain.slopes[z * tiles + x] != 0:
						color = color.darkened(0.1)
					var wet := sea and ChunkMesher.height_to_world(level) < WorldGenerator.SEA_SURFACE
					wet = wet or (lake and Vector2(x - half, z - half).length() < tiles * 0.5 * 0.55
							and level <= chunk.terrain.base_level)
					if wet:
						color = color.lerp(WATER, 0.75)
				image.set_pixel(origin.x + x, origin.y + z, color)
		for at: Dictionary in chunk.prop_marks():
			var pixel := Vector2i((at["position"] as Vector3).x / ChunkMesher.TILE_SIZE,
					(at["position"] as Vector3).z / ChunkMesher.TILE_SIZE)
			if pixel.x >= 0 and pixel.y >= 0 and pixel.x < side and pixel.y < side:
				image.set_pixelv(pixel, TREE if at["tree"] else ROCK)
	_texture = ImageTexture.create_from_image(image)


func _drops(chunk: Chunk, x: int, z: int, level: int) -> bool:
	var tiles := WorldGenerator.CHUNK_TILES
	if x >= tiles or z >= tiles:
		return false
	var other := chunk.heights[z * tiles + x]
	return other != ChunkMesher.HOLE and other < level - 1


func _draw() -> void:
	if _texture == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	var edge := minf(size.x, size.y) * FILL
	var rect := Rect2((size - Vector2(edge, edge)) * 0.5, Vector2(edge, edge))
	draw_rect(rect.grow(4.0), Color(0.75, 0.68, 0.5))
	draw_texture_rect(_texture, rect, false)

	var font := get_theme_default_font()
	var title := "Map  ·  %s" % Season.display_name()
	draw_string_outline(font, rect.position + Vector2(0, -14), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color.BLACK)
	draw_string(font, rect.position + Vector2(0, -14), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.9, 0.6))
	_text(font, Vector2(rect.end.x - 130, rect.end.y + 24), "M / Esc: close", 15,
			Color(0.75, 0.8, 0.8))

	if world == null or not is_instance_valid(world):
		return
	## Place names, one per chunk that is somewhere in particular.
	for chunk in world.chunks:
		if chunk.biome.id == &"town" or chunk.biome.id == &"mountain":
			var centre := _to_screen(rect, chunk.centre_tile_position())
			_text(font, centre + Vector2(-30, -16), chunk.biome.display_name, 16, Color.WHITE)

	if world.dragon != null and is_instance_valid(world.dragon) and not world.dragon.is_dead:
		var at := _to_screen(rect, world.dragon.global_position)
		draw_circle(at, 9.0, Color.BLACK)
		draw_circle(at, 7.0, Color(0.9, 0.2, 0.15))
		_text(font, at + Vector2(12, 5), "Dragon", 14, Color(1.0, 0.6, 0.55))

	for pid in PlayerRegistry.all_pids():
		var body := PlayerRegistry.body_of(pid) as PlayerCharacter
		if body == null or not is_instance_valid(body):
			continue
		## Down in a dungeon, they are shown at its way in.
		var where := body.global_position
		var dungeon := Dungeon.containing(get_tree(), where)
		if dungeon != null:
			var entrance := DungeonEntrance.for_dungeon(get_tree(), dungeon.dungeon_id)
			if entrance != null:
				where = entrance.global_position
		var at := _to_screen(rect, where)
		## An arrowhead pointing the way the player faces (+Z is "down" on the map).
		var facing := body.facing()
		var forward := Vector2(facing.x, facing.z).normalized() * 11.0
		var sideways := Vector2(-forward.y, forward.x) * 0.6
		var arrow := PackedVector2Array([at + forward, at - forward * 0.7 + sideways,
				at - forward * 0.7 - sideways])
		var outline := PackedVector2Array(arrow)
		outline.append(arrow[0])
		draw_colored_polygon(arrow, body.archetype.color if not body.is_dead
				else Color(0.4, 0.4, 0.4))
		draw_polyline(outline, Color.BLACK, 2.0, true)
		_text(font, at + Vector2(12, 5), "P%d" % (PlayerRegistry.all_pids().find(pid) + 1), 14,
				Color.WHITE)


func _to_screen(rect: Rect2, at: Vector3) -> Vector2:
	var unit := (Vector2(at.x, at.z) - _world_rect.position) / _world_rect.size
	return rect.position + unit.clamp(Vector2.ZERO, Vector2.ONE) * rect.size


func _text(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

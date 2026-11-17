class_name WorldBoundary
extends Node3D

## The ring of cliffs around the 4x4 chunk grid.
##
## Two jobs. It stops the party walking off the edge of the generated world, and -- more
## importantly for how the game looks -- it fills the horizon, so standing at the rim of an
## outer chunk you see mountains rather than the map ending in mid-air with sky underneath it.
##
## Built as terraces rather than one wall so it reads as the same landscape as everything else:
## the chunks are stepped plateaus, and the border is the same idea continuing outward and up.
## Each step is taller than a player can jump, so it is scenery you look at, not terrain you climb.

## Steps out from the map edge. Together they set how much of the horizon is filled.
const STEPS := 14
## Width of each terrace. STEPS x this is how far the ring extends beyond the map.
const STEP_WIDTH := 11.0
## Where the innermost wall starts. Below the sea bed, so the wall meets every edge chunk
## whatever tier it sits on -- the deep water included -- with no gap to see under.
const FLOOR := -3.0
## How far above the map's ground the innermost wall rises. The chunks along the edge stand at
## anything from sea level to the highlands, 12.6 m up, so the first wall has to clear the
## tallest of them with room to spare or the party could simply step off the map onto it.
const INNER_WALL_TOP := 24.0
## Rise of the first and shortest terrace. The best jump in the game clears 2.71 m, so this is
## the number that decides whether the ring can be scaled at all -- it keeps a margin over that
## rather than sitting just above it.
const STEP_RISE := 3.6
## Each terrace rises a little more than the one inside it, so the ring reads as foothills
## climbing into peaks instead of a single slab. Fourteen steps come to about 100 m, comfortably
## over the 23 m summit -- from the top of the mountain you look at cliffs, not past them -- and
## the outermost terrace is a believable 10 m rather than a skyscraper.
const RISE_GROWTH := 0.15

const BASE_COLOR := Color(0.50, 0.52, 0.48)
const TOP_COLOR := Color(0.74, 0.77, 0.82)
## Deliberately not much darker than the tops. These faces are in shadow for most of the day and
## a dark cliff colour on top of that turns the whole ring into a black band around the sky.
const CLIFF_COLOR := Color(0.42, 0.43, 0.44)


func build() -> void:
	name = "WorldBoundary"
	var span := WorldGenerator.GRID * WorldGenerator.CHUNK_SIZE
	var mesh := _build_mesh(span)

	var instance := MeshInstance3D.new()
	instance.name = "Cliffs"
	instance.mesh = mesh
	instance.material_override = ChunkMesher.make_material()
	add_child(instance)

	var body := StaticBody3D.new()
	body.name = "CliffBody"
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


func _build_mesh(span: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bottom := FLOOR
	for step in STEPS:
		## Each terrace is a rectangular frame around the previous one: `inner` is where it
		## starts, `outer` where the next one begins.
		var inner := step * STEP_WIDTH
		var outer := inner + STEP_WIDTH
		var top := INNER_WALL_TOP if step == 0 else bottom + rise_of(step)
		## Higher terraces are paler, which reads as distance and stops the ring becoming one
		## flat silhouette.
		var tint: float = float(step) / maxf(1.0, float(STEPS - 1))
		var top_color := BASE_COLOR.lerp(TOP_COLOR, tint)

		_frame_top(surface, top_color, span, inner, outer, top)
		_frame_wall(surface, CLIFF_COLOR.lerp(top_color, tint * 0.35), span, inner, bottom, top)
		bottom = top

	surface.generate_normals()
	return surface.commit()


## The flat top of one terrace: four bands forming a rectangular ring. The north and south bands
## run the full width so the corners are covered exactly once.
func _frame_top(surface: SurfaceTool, color: Color, span: float, inner: float, outer: float,
		y: float) -> void:
	var i0 := -inner
	var i1 := span + inner
	var o0 := -outer
	var o1 := span + outer

	_flat_quad(surface, color, y, o0, o1, o0, i0)   # north band, full width
	_flat_quad(surface, color, y, o0, o1, i1, o1)   # south band, full width
	_flat_quad(surface, color, y, o0, i0, i0, i1)   # west band, between them
	_flat_quad(surface, color, y, i1, o1, i0, i1)   # east band, between them


## The vertical face a terrace presents inward -- the part that is actually unclimbable.
func _frame_wall(surface: SurfaceTool, color: Color, span: float, inner: float, bottom: float,
		top: float) -> void:
	var a := -inner
	var b := span + inner

	## Wound so each face points in towards the play area.
	_wall_quad(surface, color, Vector3(a, bottom, a), Vector3(b, bottom, a), top)
	_wall_quad(surface, color, Vector3(b, bottom, b), Vector3(a, bottom, b), top)
	_wall_quad(surface, color, Vector3(a, bottom, b), Vector3(a, bottom, a), top)
	_wall_quad(surface, color, Vector3(b, bottom, a), Vector3(b, bottom, b), top)


func _flat_quad(surface: SurfaceTool, color: Color, y: float, x0: float, x1: float,
		z0: float, z1: float) -> void:
	if x1 - x0 <= 0.0 or z1 - z0 <= 0.0:
		return
	for vertex in [
		Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1),
		Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1),
	]:
		surface.set_color(color)
		surface.add_vertex(vertex)


func _wall_quad(surface: SurfaceTool, color: Color, from: Vector3, to: Vector3,
		top: float) -> void:
	var rise := Vector3(0.0, top - from.y, 0.0)
	for vertex in [from, from + rise, to + rise, from, to + rise, to]:
		surface.set_color(color)
		surface.add_vertex(vertex)


## Rise of one terrace. Growing outward is what gives the ring its foothills-into-peaks profile.
static func rise_of(step: int) -> float:
	return STEP_RISE * (1.0 + RISE_GROWTH * float(step))


## How far the ring reaches beyond the map, and how tall it stands. Used by the tests, and by
## anything that needs to know where the world genuinely ends.
static func extent() -> float:
	return STEPS * STEP_WIDTH


static func height() -> float:
	var total := INNER_WALL_TOP
	for step in range(1, STEPS):
		total += rise_of(step)
	return total

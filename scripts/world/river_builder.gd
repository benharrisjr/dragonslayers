class_name RiverBuilder
extends RefCounted

## Builds what can be seen and stood on of a chunk's stretch of river: the water's surface, a
## waterfall wherever the bed steps down, the raft's footing on the water, and the bridge.
##
## The terrain (RiverCarver) already has the channel cut and its tiles marked; this only reads
## them. Like everything else in a chunk it is built the same on every machine from the seed.

const BRIDGE_PLANK := 0.5
const BRIDGE_THICKNESS := 0.1
const BRIDGE_LIFT := 0.1
## How far in from each end the deck's collision ramps up the lift, so anything walking on
## meets a gentle slope rather than a lip.
const BRIDGE_RAMP := 0.5
const RAIL_HEIGHT := 1.1
const WOOD := Color(0.55, 0.36, 0.2)
const WOOD_DARK := Color(0.38, 0.24, 0.13)

static var _fall_material: ShaderMaterial


static func build(chunk: Chunk) -> void:
	var terrain := chunk.terrain
	if not terrain.water.has(1):
		if not terrain.bridges.is_empty():
			## A bluff's bridges, with no river under them.
			var bridges := Node3D.new()
			bridges.name = "Bridges"
			chunk.add_child(bridges)
			for spec: Dictionary in terrain.bridges:
				bridges.add_child(build_bridge(spec))
		return
	var river := Node3D.new()
	river.name = "River"
	chunk.add_child(river)
	_build_surface(terrain, river)
	_build_falls(terrain, river)
	_build_footing(terrain, river)
	for spec: Dictionary in terrain.bridges:
		if spec.get("kind", &"plank") == &"land":
			river.add_child(build_land_bridge(spec, terrain, chunk.biome))
		else:
			river.add_child(build_bridge(spec))


## The river's water: the same as the lake's and the sea's, carried along by its current.
static func water_material() -> ShaderMaterial:
	var material := Chunk.still_water_material()
	material.set_shader_parameter("use_vertex_flow", true)
	return material


static func fall_material() -> ShaderMaterial:
	if _fall_material == null:
		_fall_material = ShaderMaterial.new()
		_fall_material.shader = preload("res://scripts/world/waterfall.gdshader")
	return _fall_material


## One flat quad per water tile at its surface, coloured with its flow and its foam.
static func _build_surface(terrain: TerrainData, parent: Node3D) -> void:
	var size := terrain.size
	var tile_size := ChunkMesher.TILE_SIZE
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in size:
		for x in size:
			if not terrain.is_water(x, z):
				continue
			var y := terrain.water_surface(x, z)
			var x0 := x * tile_size
			var z0 := z * tile_size
			var corners := [Vector3(x0, y, z0), Vector3(x0 + tile_size, y, z0),
					Vector3(x0 + tile_size, y, z0 + tile_size), Vector3(x0, y, z0 + tile_size)]
			var at := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]
			var colours: Array[Color] = []
			for corner: Vector2i in at:
				colours.append(_corner_colour(terrain, corner, y))
			for index in [0, 1, 2, 0, 2, 3]:
				surface.set_color(colours[index])
				surface.set_normal(Vector3.UP)
				surface.add_vertex(corners[index])
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = surface.commit()
	instance.material_override = water_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


## The flow and foam at a corner of the water's surface, averaged over the water tiles at this
## surface height that share it -- so the current turns smoothly round a bend, rather than in a
## step at each tile's edge, and the foam under a fall thins out instead of stopping square.
static func _corner_colour(terrain: TerrainData, corner: Vector2i, surface: float) -> Color:
	var flow := Vector2.ZERO
	var foam := 0.0
	var count := 0
	for dz in [-1, 0]:
		for dx in [-1, 0]:
			var x: int = corner.x + dx
			var z: int = corner.y + dz
			if not terrain.in_bounds(x, z) or not terrain.is_water(x, z) \
					or not is_equal_approx(terrain.water_surface(x, z), surface):
				continue
			flow += terrain.flow[z * terrain.size + x]
			foam += 1.0 if is_below_fall(terrain, x, z) else 0.0
			count += 1
	if count > 0:
		flow /= count
		foam /= count
	if flow.length() > 1.0:
		flow = flow.normalized()
	return Color(flow.x * 0.5 + 0.5, flow.y * 0.5 + 0.5, 0.0, foam)


## The level of the river bed beyond `side` of a tile: the next tile's, or -- across a chunk
## border the river runs over -- the next chunk's, one below its ground. NAN where no water lies
## beyond.
static func bed_beyond(terrain: TerrainData, x: int, z: int, side: int) -> float:
	var nx := x + ChunkMesher.NEIGHBOUR_DX[side]
	var nz := z + ChunkMesher.NEIGHBOUR_DZ[side]
	if terrain.in_bounds(nx, nz):
		return float(terrain.heights[nz * terrain.size + nx]) if terrain.is_water(nx, nz) else NAN
	if terrain.side_levels[side] == TerrainData.MAP_EDGE:
		return NAN
	return float(terrain.edge_level(side, TerrainData.lane_of(side, x, z)) - 1)


## The height of the water's surface beyond `side` of a tile, in metres: as bed_beyond, but taking
## in how deep the river is cut there. NAN where no water lies beyond.
static func surface_beyond(terrain: TerrainData, x: int, z: int, side: int) -> float:
	var nx := x + ChunkMesher.NEIGHBOUR_DX[side]
	var nz := z + ChunkMesher.NEIGHBOUR_DZ[side]
	if terrain.in_bounds(nx, nz):
		if terrain.is_water(nx, nz):
			return terrain.water_surface(nx, nz)
		## Into the lake or the sea: down to its still water.
		if terrain.still_surface > -INF and not terrain.is_hole(nx, nz) \
				and terrain.level(nx, nz) < terrain.base_level:
			return terrain.still_surface
		return NAN
	var bed := bed_beyond(terrain, x, z, side)
	if is_nan(bed):
		return NAN
	return (bed + 1.0) * ChunkMesher.STEP_HEIGHT - WorldGenerator.RIVER_SURFACE_DROP \
			- terrain.side_sink[side]


## Whether a waterfall comes down onto this tile from any side.
static func is_below_fall(terrain: TerrainData, x: int, z: int) -> bool:
	var own := terrain.water_surface(x, z)
	for side in 4:
		var beyond := surface_beyond(terrain, x, z, side)
		if not is_nan(beyond) and beyond > own + 0.01:
			return true
	return false


## A falling sheet over every edge where the bed steps down, from this tile's surface to the
## surface below.
static func _build_falls(terrain: TerrainData, parent: Node3D) -> void:
	var size := terrain.size
	var tile_size := ChunkMesher.TILE_SIZE
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for z in size:
		for x in size:
			if not terrain.is_water(x, z):
				continue
			var top := terrain.water_surface(x, z)
			for side in 4:
				var bottom := surface_beyond(terrain, x, z, side)
				if is_nan(bottom) or bottom >= top - 0.01:
					continue
				any = true
				## The edge, nudged a little out over the drop so it hangs in front of the rock.
				var centre := Vector3((x + 0.5) * tile_size, 0.0, (z + 0.5) * tile_size)
				var out := Vector3(ChunkMesher.NEIGHBOUR_DX[side], 0.0, ChunkMesher.NEIGHBOUR_DZ[side])
				var along := Vector3(-out.z, 0.0, out.x)
				var lip := centre + out * (tile_size * 0.5 + 0.06)
				var a := lip - along * tile_size * 0.5
				var b := lip + along * tile_size * 0.5
				var u0 := a.x + a.z
				var u1 := u0 + tile_size
				var height := top - bottom
				var quad := [
					[Vector3(a.x, top, a.z), Vector2(u0, 0.0)],
					[Vector3(b.x, top, b.z), Vector2(u1, 0.0)],
					[Vector3(b.x, bottom, b.z), Vector2(u1, height)],
					[Vector3(a.x, bottom, a.z), Vector2(u0, height)],
				]
				for index in [0, 1, 2, 0, 2, 3]:
					surface.set_uv(quad[index][1])
					surface.set_normal(out)
					surface.add_vertex(quad[index][0])
	if not any:
		return
	var instance := MeshInstance3D.new()
	instance.name = "Waterfalls"
	instance.mesh = surface.commit()
	instance.material_override = fall_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


## What a raft floats on: a slab over every water tile, its top level with the banks, on a layer
## only a player carrying a raft collides with. Everyone else goes straight through into the
## water. Runs of tiles in a row at the same level share one box.
static func _build_footing(terrain: TerrainData, parent: Node3D) -> void:
	var size := terrain.size
	var tile_size := ChunkMesher.TILE_SIZE
	var body := StaticBody3D.new()
	body.name = "RaftWater"
	body.collision_layer = Combatant.LAYER_WATER
	body.collision_mask = 0
	parent.add_child(body)
	for z in size:
		var x := 0
		while x < size:
			if not terrain.is_water(x, z):
				x += 1
				continue
			var level := terrain.level(x, z)
			var run := 1
			while x + run < size and terrain.is_water(x + run, z) \
					and terrain.level(x + run, z) == level \
					and terrain.sink_at(x + run, z) == terrain.sink_at(x, z):
				run += 1
			var top := (level + 1) * ChunkMesher.STEP_HEIGHT - terrain.sink_at(x, z)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(run * tile_size, 0.4, tile_size)
			shape.shape = box
			shape.position = Vector3((x + run * 0.5) * tile_size, top - 0.2, (z + 0.5) * tile_size)
			body.add_child(shape)
			x += run


## A plank bridge over the water, its deck level with the banks it rests on, with a rail along
## each side so nobody walks off it into the river.
static func build_bridge(spec: Dictionary) -> Node3D:
	var tile_size := ChunkMesher.TILE_SIZE
	var from: Vector2i = spec["from"]
	var to: Vector2i = spec["to"]
	## The banks it rests on are at the deck's level, so a deck flush with them sinks its planks
	## and beams into the ground at both ends. It sits a plank's thickness up instead -- low enough
	## that the capsule's rounded foot rides up onto it without a step.
	var deck_y: float = int(spec["level"]) * ChunkMesher.STEP_HEIGHT + BRIDGE_LIFT
	var along_x: bool = spec["along_x"]
	var x0 := from.x * tile_size
	var x1 := (to.x + 1) * tile_size
	var z0 := from.y * tile_size
	var z1 := (to.y + 1) * tile_size
	var length := (x1 - x0) if along_x else (z1 - z0)
	var width := (z1 - z0) if along_x else (x1 - x0)
	var bridge := Node3D.new()
	bridge.name = "Bridge"
	bridge.position = Vector3((x0 + x1) * 0.5, deck_y, (z0 + z1) * 0.5)
	## Built along local X, then turned to run whichever way it spans.
	if not along_x:
		bridge.rotation.y = PI * 0.5
	var planks := int(length / BRIDGE_PLANK)
	for index in planks:
		var plank := BoxMesh.new()
		plank.size = Vector3(BRIDGE_PLANK * 0.9, BRIDGE_THICKNESS, width - 0.2)
		_part(bridge, plank, WOOD if index % 2 == 0 else WOOD.darkened(0.1),
				Vector3(-length * 0.5 + (index + 0.5) * BRIDGE_PLANK, -BRIDGE_THICKNESS * 0.5, 0.0))
	for side in [-1.0, 1.0]:
		var beam := BoxMesh.new()
		beam.size = Vector3(length, BRIDGE_LIFT, 0.2)
		_part(bridge, beam, WOOD_DARK, Vector3(0.0, -BRIDGE_LIFT * 0.5, side * (width * 0.5 - 0.1)))
		var rail := BoxMesh.new()
		rail.size = Vector3(length, 0.12, 0.12)
		_part(bridge, rail, WOOD, Vector3(0.0, RAIL_HEIGHT, side * (width * 0.5 - 0.1)))
		var posts := int(length / 2.0) + 1
		for index in posts:
			var post := BoxMesh.new()
			post.size = Vector3(0.16, RAIL_HEIGHT, 0.16)
			_part(bridge, post, WOOD_DARK, Vector3(-length * 0.5 + index * length / (posts - 1),
					RAIL_HEIGHT * 0.5, side * (width * 0.5 - 0.1)))
	## The deck is ground to walk on; the rails are walls to walk into.
	var deck := StaticBody3D.new()
	deck.name = "Deck"
	deck.collision_layer = Combatant.LAYER_WORLD
	deck.collision_mask = 0
	## A slab whose top ramps down by the lift at both ends, to meet the banks flush.
	var deck_shape := CollisionShape3D.new()
	var deck_hull := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	var half_l := length * 0.5
	var half_w := width * 0.5
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			points.append(Vector3(x_side * half_l, -0.6, z_side * half_w))
			points.append(Vector3(x_side * half_l, -BRIDGE_LIFT, z_side * half_w))
			points.append(Vector3(x_side * (half_l - BRIDGE_RAMP), 0.0, z_side * half_w))
	deck_hull.points = points
	deck_shape.shape = deck_hull
	deck.add_child(deck_shape)
	bridge.add_child(deck)
	deck.add_to_group("plank_decks")
	var rails := StaticBody3D.new()
	rails.add_to_group("plank_decks")
	rails.name = "Rails"
	rails.collision_layer = Combatant.LAYER_SCENERY
	rails.collision_mask = 0
	for side in [-1.0, 1.0]:
		var rail_shape := CollisionShape3D.new()
		var rail_box := BoxShape3D.new()
		## Short of the ends, so the bridge can be walked onto from the banks.
		rail_box.size = Vector3(length - tile_size * 1.5, RAIL_HEIGHT + 0.6, 0.3)
		rail_shape.shape = rail_box
		rail_shape.position = Vector3(0.0, (RAIL_HEIGHT + 0.6) * 0.5 - 0.3, side * (width * 0.5 - 0.1))
		rails.add_child(rail_shape)
	bridge.add_child(rails)
	return bridge


## How thick a land bridge's arch is at its crown, and how many pieces its curve is drawn in.
const ARCH_CROWN := 0.55
const ARCH_SEGMENTS := 12
## Pieces each curve up from a bank is drawn in.
const APPROACH_SEGMENTS := 8


## A land bridge: a broad arch of rock left standing over the river, high enough to raft under,
## turf on top, meeting the ramps up from the banks; drawn with the terrain's own material. A stone kerb runs along each side with
## the ledges' invisible wall over it, so nobody walks -- or is knocked -- off it into the water.
static func build_land_bridge(spec: Dictionary, terrain: TerrainData, biome: BiomeData) -> Node3D:
	var tile := ChunkMesher.TILE_SIZE
	var from: Vector2i = spec["from"]
	var to: Vector2i = spec["to"]
	var along_x: bool = spec["along_x"]
	var span: Vector2i = spec["span"]
	var deck := int(spec["level"]) * ChunkMesher.STEP_HEIGHT
	var bed := deck - int(spec.get("lift", 1)) * ChunkMesher.STEP_HEIGHT - terrain.sink_at(
			span.x if along_x else from.x + 1, from.y + 1 if along_x else span.x)
	## u runs the way it is walked, v across it, both in chunk-local metres.
	var u0 := span.x * tile
	var u1 := (span.y + 1) * tile
	var v0 := float(from.y if along_x else from.x) * tile
	var v1 := float((to.y if along_x else to.x) + 1) * tile
	var point := func(u: float, v: float) -> Vector2:
		return Vector2(u, v) if along_x else Vector2(v, u)
	var turf := Season.ground_color(biome.id, biome.ground_color)
	turf.a = 1.0 if Season.snows_on(biome.id) else 0.0
	var rock := Season.cliff_color(biome.id, biome.cliff_color)
	rock.a = 0.0
	var middle := (u0 + u1) * 0.5
	var half := (u1 - u0) * 0.5
	## The arch's underside: thin at the crown, curving down to meet the bed at each bank.
	var under := func(u: float) -> float:
		var q := clampf(absf(u - middle) / half, 0.0, 1.0)
		return deck - ARCH_CROWN - (deck - ARCH_CROWN - bed) * pow(q, 6.0)
	## Up from each bank in an S-curve -- level where it leaves the bank, level where it meets the
	## deck, steepest (about 37 degrees, as a ramp) half way -- so neither end has an edge to it.
	## A hair over the bank it starts from, so the two never flicker through each other.
	var bank := deck - (int(spec.get("lift", 1)) - 1) * ChunkMesher.STEP_HEIGHT + 0.03
	var approach := RiverCarver.LAND_BRIDGE_APPROACH * tile
	var top := func(u: float) -> float:
		var t := 1.0
		if u < u0:
			t = clampf((u - (u0 - approach)) / approach, 0.0, 1.0)
		elif u > u1:
			t = clampf(((u1 + approach) - u) / approach, 0.0, 1.0)
		return lerpf(bank, deck, t * t * (3.0 - 2.0 * t))
	## Under it: the arch over the water, down to just below the bank under the approaches.
	var foot := func(u: float) -> float:
		return under.call(u) if u >= u0 and u <= u1 else bank - 0.05
	var stations := PackedFloat32Array()
	for i in APPROACH_SEGMENTS:
		stations.append(lerpf(u0 - approach, u0, float(i) / APPROACH_SEGMENTS))
	for i in ARCH_SEGMENTS:
		stations.append(lerpf(u0, u1, float(i) / ARCH_SEGMENTS))
	for i in APPROACH_SEGMENTS + 1:
		stations.append(lerpf(u1, u1 + approach, float(i) / APPROACH_SEGMENTS))
	var ground: Array = []
	var walls: Array = []
	var solid := PackedVector3Array()
	var across := Vector2(0.0, 1.0) if along_x else Vector2(1.0, 0.0)
	for i in stations.size() - 1:
		var ua := stations[i]
		var ub := stations[i + 1]
		var ta: float = top.call(ua)
		var tb: float = top.call(ub)
		var ya: float = foot.call(ua)
		var yb: float = foot.call(ub)
		var corners: Array[Vector2] = [point.call(ua, v0), point.call(ub, v0), point.call(ub, v1),
				point.call(ua, v1)]
		var tops: Array[Vector3] = []
		var bottoms: Array[Vector3] = []
		for c in 4:
			var first := c == 0 or c == 3
			tops.append(Vector3(corners[c].x, ta if first else tb, corners[c].y))
			bottoms.append(Vector3(corners[c].x, ya if first else yb, corners[c].y))
		ground.append([tops[0], tops[1], tops[2], turf, rock, false])
		ground.append([tops[0], tops[2], tops[3], turf, rock, false])
		solid.append_array([tops[0], tops[1], tops[2], tops[0], tops[2], tops[3]])
		if ua >= u0 - 0.001 and ub <= u1 + 0.001:
			ground.append([bottoms[0], bottoms[1], bottoms[2], rock, rock, false, Vector3.DOWN])
			ground.append([bottoms[0], bottoms[2], bottoms[3], rock, rock, false, Vector3.DOWN])
		var shade := rock * (0.94 + 0.06 * sin(i * 2.3))
		shade.a = 0.0
		walls.append([corners[0], corners[1], ta, tb, ya, yb,
				Vector3(-across.x, 0.0, -across.y), shade, turf])
		walls.append([corners[3], corners[2], ta, tb, ya, yb,
				Vector3(across.x, 0.0, across.y), shade, turf])
		## Its sides are solid too, so nobody on the bank walks in under the curve.
		for side: Array in [[corners[0], corners[1]], [corners[3], corners[2]]]:
			var p: Vector2 = side[0]
			var q: Vector2 = side[1]
			## Over the water only as thick as the crown: the arch's feet never snag a raft.
			var over := ua >= u0 - 0.001 and ub <= u1 + 0.001
			var fa := deck - ARCH_CROWN if over else ya
			var fb := deck - ARCH_CROWN if over else yb
			solid.append_array([Vector3(p.x, ta, p.y), Vector3(q.x, tb, q.y), Vector3(q.x, fb, q.y),
					Vector3(p.x, ta, p.y), Vector3(q.x, fb, q.y), Vector3(p.x, fa, p.y)])
	var bridge := Node3D.new()
	bridge.name = "LandBridge"
	var arch := MeshInstance3D.new()
	arch.name = "Arch"
	arch.mesh = ChunkMesher._commit(ground, walls)
	arch.material_override = ChunkMesher.make_material()
	bridge.add_child(arch)

	## The kerbs, running a little onto the banks at each end.
	var paths: Array = []
	for edge: Array in [[v0, 1.0], [v1, -1.0]]:
		var points := PackedVector2Array()
		var normals := PackedVector2Array()
		for u in [u0 - 0.05, middle, u1 + 0.05]:
			points.append(point.call(u, edge[0]))
			normals.append(across * float(edge[1]))
		## Run with the bridge on the left, as the ledges' paths do.
		var heading := points[1] - points[0]
		if Vector2(-heading.y, heading.x).dot(normals[0]) < 0.0:
			points.reverse()
		paths.append([points, normals, deck, false])
	var kerbs := MeshInstance3D.new()
	kerbs.name = "Kerbs"
	kerbs.mesh = ChunkMesher.build_ledges(paths, biome)
	kerbs.material_override = ChunkMesher.make_material()
	bridge.add_child(kerbs)
	var guard := StaticBody3D.new()
	guard.name = "KerbBody"
	guard.collision_layer = Combatant.LAYER_LEDGE
	guard.collision_mask = 0
	var guard_shape := CollisionShape3D.new()
	guard_shape.shape = ChunkMesher.ledge_shape(paths)
	guard.add_child(guard_shape)
	bridge.add_child(guard)

	## Its top and sides are ground to walk on and walls to walk into.
	var body := StaticBody3D.new()
	body.name = "Deck"
	body.collision_layer = Combatant.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var faces := ConcavePolygonShape3D.new()
	faces.set_faces(solid)
	faces.backface_collision = true
	shape.shape = faces
	body.add_child(shape)
	bridge.add_child(body)
	return bridge


static func _part(parent: Node3D, mesh: Mesh, colour: Color, at: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)


## A little raft of lashed logs, `scale` times full size (full size: 2 m square), its deck at y 0.
static func raft_model(scale: float = 1.0) -> Node3D:
	var raft := Node3D.new()
	raft.name = "Raft"
	for index in 5:
		var log := CylinderMesh.new()
		log.top_radius = 0.2 * scale
		log.bottom_radius = 0.2 * scale
		log.height = 2.1 * scale
		log.radial_segments = 7
		var at := Vector3((index - 2) * 0.4 * scale, -0.2 * scale, 0.0)
		_part(raft, log, WOOD if index % 2 == 0 else WOOD.darkened(0.12), at)
		raft.get_child(raft.get_child_count() - 1).rotation.x = PI * 0.5
	for end in [-1.0, 1.0]:
		var beam := BoxMesh.new()
		beam.size = Vector3(2.0 * scale, 0.1 * scale, 0.22 * scale)
		_part(raft, beam, WOOD_DARK, Vector3(0.0, 0.0, end * 0.75 * scale))
	return raft

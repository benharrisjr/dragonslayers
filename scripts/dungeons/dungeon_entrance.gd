class_name DungeonEntrance
extends Node3D

## The way into one of the eight dungeons, standing somewhere on the map.
##
## Each is built by its chunk, last, from the seed (Entrance_<dungeon id>), so it is the same node
## on every machine. Some are there to be walked into from the start -- the town well, the two
## temples' buildings, the cave in the heart of a forest grove, and the portal on the lake bed --
## and three are secrets: a marked rock in the desert hides a stairwell (lift it), a great tree
## in the fields has a door in its trunk (hit it), and a cracked wall in the plains gives way to a
## bomb. Revealing one is the host's call, sent to everyone and kept in a saved world.
##
## The node faces its door down local +z: the door is at `door_local`, and someone leaving the
## dungeon comes out at `exit_local`, a few steps in front of it.

enum Kind { WELL, ROCK, TREE, WALL, BUILDING, GROVE, LAKE }

const GROUP := &"dungeon_entrances"
## Which kind of entrance each dungeon has.
const KINDS: Dictionary = {
	&"well": Kind.WELL, &"desert": Kind.ROCK, &"fields": Kind.TREE, &"plains": Kind.WALL,
	&"forest": Kind.GROVE, &"temple_low": Kind.BUILDING, &"temple_high": Kind.BUILDING,
	&"lake": Kind.LAKE,
}
## How close to a door a player has to be to go through it with the interact button.
const ENTER_RADIUS := 3.4
## How close to the lake portal a diver has to get, across and above it.
const PORTAL_REACH := 2.8
const PORTAL_ABOVE := 1.8
## How far off a blow or a blast still finds the tree trunk or the cracked wall.
const TRUNK_RADIUS := 1.6
const WALL_REACH := 2.4
## How far out from the wall entrance's middle the cracked masonry's face stands.
const WALL_FACE := 4.3

const ART := "res://art/"
const CRYPT := ART + "kenney_graveyard-kit_5/Models/GLB format/crypt-large.glb"
const CRYPT_DOOR := ART + "kenney_graveyard-kit_5/Models/GLB format/crypt-large-door.glb"
const CRYPT_ROOF := ART + "kenney_graveyard-kit_5/Models/GLB format/crypt-large-roof.glb"
const OBELISK := ART + "kenney_graveyard-kit_5/Models/GLB format/pillar-obelisk.glb"
const COLUMN := ART + "kenney_graveyard-kit_5/Models/GLB format/column-large.glb"
const GREAT_TREE := ART + "kenney_fantasy-town-kit_2/Models/GLB format/tree-high-round.glb"
const MOUND := ART + "kenney_fantasy-town-kit_2/Models/GLB format/rock-large.glb"
const CRACKED_WALL := ART + "kenney_graveyard-kit_5/Models/GLB format/stone-wall-damaged.glb"
const GROVE_TREE := ART + "kenney_survival-kit/Models/GLB format/tree-tall.glb"
const CAVE_MOUTH := ART + "kenney_modular-cave-kit_1/Models/GLB format/gate-rock.glb"
const SAND_ROCK := ART + "kenney_survival-kit/Models/GLB format/rock-sand-a.glb"
const DOOR_GATE := ART + "kenney_modular-dungeon-kit_1/Models/GLB format/gate-door.glb"

const STONE := Color(0.58, 0.56, 0.52)
const DARK := Color(0.03, 0.03, 0.05)
const WOOD := Color(0.42, 0.28, 0.16)
const PORTAL_GLOW := Color(0.35, 0.95, 1.0)

## Footprint, in tiles from the centre, that each kind keeps clear around itself.
const FOOTPRINT: Dictionary = {
	Kind.WELL: 2, Kind.TREE: 3, Kind.WALL: 5, Kind.BUILDING: 5, Kind.GROVE: 7,
}

var dungeon_id: StringName = &""
var kind: Kind = Kind.WELL
var revealed: bool = false
var door_local := Vector3.ZERO
var exit_local := Vector3(0.0, 0.0, 3.0)

var _chunk: Chunk
## Shown once revealed (the doorway in the trunk, the hole in the wall).
var _secret_parts: Array[Node3D] = []
## Gone once revealed (the cracked wall, the lid over the stairwell), with their colliders.
var _cover_parts: Array[Node] = []
var _label: Label3D
## The desert's marked rock: its index among the chunk's props, so the glove can lift it.
var _rock_index: int = -1


# --- placing ---------------------------------------------------------------------------------

## Builds the entrance to dungeon `id` in `chunk`, somewhere fitting, and returns it; null if
## nowhere was found (the tests make sure that never happens).
static func place(chunk: Chunk, id: StringName) -> DungeonEntrance:
	var entrance := DungeonEntrance.new()
	entrance.name = "Entrance_%s" % id
	entrance.dungeon_id = id
	entrance.kind = KINDS.get(id, Kind.WELL)
	entrance._chunk = chunk
	var rng := GameState.chunk_rng(chunk.index + 9000)
	match entrance.kind:
		Kind.ROCK:
			var well := chunk.terrain.stairwell
			if well.size == Vector2i.ZERO:
				return null
			chunk.add_child(entrance)
			## At the stairwell's far wall, facing back up it (-z).
			var tile := ChunkMesher.TILE_SIZE
			entrance.position = Vector3((well.position.x + well.size.x * 0.5) * tile,
					ChunkMesher.height_to_world(chunk.terrain.base_level - WorldGenerator.STAIRWELL_DEPTH),
					(well.position.y + well.size.y) * tile)
			entrance.rotation.y = PI
		Kind.LAKE:
			var half := WorldGenerator.CHUNK_TILES / 2
			chunk.add_child(entrance)
			entrance.position = chunk.tile_surface(half, half)
		_:
			var spot := _find_spot(chunk, entrance.kind, id, rng)
			if spot.x < 0:
				entrance.free()
				return null
			chunk.add_child(entrance)
			entrance.position = chunk.tile_surface(spot.x, spot.y)
			entrance.rotation.y = rng.randi_range(0, 3) * PI * 0.5
			var radius: int = FOOTPRINT[entrance.kind]
			chunk.clear_props_within(spot, radius + 1)
			for child in chunk.get_children():
				if child is Torch and (child as Torch).position.distance_to(chunk.tile_surface(spot.x, spot.y)) \
						< (radius + 1.5) * ChunkMesher.TILE_SIZE:
					child.free()
			chunk._mark_occupied(spot.x, spot.y, radius + 1)
	entrance.add_to_group(GROUP)
	entrance._build()
	return entrance


## Flat, open ground at the chunk's own level, clear of ramps, water, chests and the rim, with the
## whole footprint around it; scenery standing there is cleared away. The well goes beside the
## shop, everything else near the middle of its chunk.
static func _find_spot(chunk: Chunk, which: Kind, id: StringName, rng: RandomNumberGenerator) -> Vector2i:
	var tiles := WorldGenerator.CHUNK_TILES
	var radius: int = FOOTPRINT[which]
	var start := Vector2i(tiles / 2 + rng.randi_range(-10, 10), tiles / 2 + rng.randi_range(-10, 10))
	if id == &"well" and chunk.shop != null:
		start = Vector2i((chunk.shop.position / ChunkMesher.TILE_SIZE).x,
				(chunk.shop.position / ChunkMesher.TILE_SIZE).z)
	## Off the paths if it can be.
	for off_paths in [true, false]:
		for ring in range(0, tiles / 2):
			for dz in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dz)) != ring:
						continue
					var at := start + Vector2i(dx, dz)
					if _fits(chunk, at, radius, off_paths):
						return at
	return Vector2i(-1, -1)


static func _fits(chunk: Chunk, at: Vector2i, radius: int, off_paths: bool = false) -> bool:
	var terrain := chunk.terrain
	if not terrain.in_bounds(at.x, at.y) or terrain.reach[at.y * terrain.size + at.x] == 0:
		return false
	for z in range(at.y - radius, at.y + radius + 1):
		for x in range(at.x - radius, at.x + radius + 1):
			if not terrain.in_bounds(x, z) or terrain.rim(x, z) < WorldGenerator.BORDER:
				return false
			var index := z * terrain.size + x
			if terrain.heights[index] != terrain.base_level or terrain.slopes[index] != 0 \
					or terrain.reserved[index] != 0 or terrain.water[index] != 0 \
					or chunk.is_arena_tile(x, z):
				return false
			if off_paths and terrain.path[index] != 0:
				return false
	## Clear of the shop, which is not scenery to be swept aside.
	if chunk.shop != null:
		var middle := Vector2((at.x + 0.5) * ChunkMesher.TILE_SIZE, (at.y + 0.5) * ChunkMesher.TILE_SIZE)
		if middle.distance_to(Vector2(chunk.shop.position.x, chunk.shop.position.z)) \
				< 6.0 + radius * ChunkMesher.TILE_SIZE:
			return false
	for chest in chunk.chests:
		var tile := Vector2i((chest.position / ChunkMesher.TILE_SIZE).x, (chest.position / ChunkMesher.TILE_SIZE).z)
		if absi(tile.x - at.x) <= radius + 1 and absi(tile.y - at.y) <= radius + 1:
			return false
	return true


# --- building --------------------------------------------------------------------------------

func _build() -> void:
	match kind:
		Kind.WELL:
			_build_well()
		Kind.ROCK:
			_build_stairwell()
		Kind.TREE:
			_build_tree()
		Kind.WALL:
			_build_wall()
		Kind.BUILDING:
			if dungeon_id == &"temple_high":
				_build_tower()
			else:
				_build_crypt()
		Kind.GROVE:
			_build_grove()
		Kind.LAKE:
			_build_portal()
	_label = Label3D.new()
	_label.text = "Enter"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 64
	_label.outline_size = 14
	_label.pixel_size = 0.01
	_label.no_depth_test = true
	_label.visibility_range_end = 32.0
	_label.position = door_local + Vector3.UP * 2.6
	_label.visible = false
	add_child(_label)
	if kind in [Kind.WELL, Kind.BUILDING, Kind.GROVE, Kind.LAKE]:
		_apply_reveal(false)


func _build_well() -> void:
	var ring := CylinderMesh.new()
	ring.top_radius = 1.4
	ring.bottom_radius = 1.5
	ring.height = 1.0
	ring.radial_segments = 16
	_part(ring, STONE, Vector3(0, 0.5, 0))
	var water := CylinderMesh.new()
	water.top_radius = 1.05
	water.bottom_radius = 1.05
	water.height = 0.04
	water.radial_segments = 16
	_part(water, DARK, Vector3(0, 0.99, 0), true)
	for side in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(0.22, 2.4, 0.22)
		_part(post, WOOD, Vector3(side * 1.3, 2.1, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(3.4, 1.0, 2.2)
	_part(roof, Color(0.55, 0.25, 0.2), Vector3(0, 3.6, 0)).rotation.y = PI * 0.5
	var beam := CylinderMesh.new()
	beam.top_radius = 0.08
	beam.bottom_radius = 0.08
	beam.height = 2.6
	_part(beam, WOOD, Vector3(0, 2.7, 0)).rotation.z = PI * 0.5
	_solid(_cylinder_shape(1.5, 1.0), Vector3(0, 0.5, 0))
	door_local = Vector3(0, 0.6, 0)
	exit_local = Vector3(0, 0, 2.8)


func _build_crypt() -> void:
	var scale := 4.0
	_model(CRYPT, scale, Vector3.ZERO)
	_model(CRYPT_DOOR, scale, Vector3(0, 0, 1.2 * scale))
	_model(CRYPT_ROOF, scale, Vector3(0, 1.0 * scale, 0))
	_solid(_box_shape(Vector3(1.85, 1.0, 2.4) * scale), Vector3(0, 0.5 * scale, 0))
	door_local = Vector3(0, 1.4, 1.2 * scale + 0.4)
	exit_local = Vector3(0, 0, 1.2 * scale + 3.0)


## The highlands temple's shrine: the crypt kit's building, smaller, between two tall obelisks
## and behind a pair of columns, so it is not mistaken for the crypt down on the ground.
func _build_tower() -> void:
	var scale := 3.4
	_model(CRYPT, scale, Vector3.ZERO)
	_model(CRYPT_DOOR, scale, Vector3(0, 0, 1.2 * scale))
	_model(CRYPT_ROOF, scale, Vector3(0, 1.0 * scale, 0))
	_solid(_box_shape(Vector3(1.85, 1.0, 2.4) * scale), Vector3(0, 0.5 * scale, 0))
	for side in [-1.0, 1.0]:
		_model(OBELISK, 5.0, Vector3(side * 4.6, 0, 1.6))
		_solid(_cylinder_shape(0.9, 6.0), Vector3(side * 4.6, 3.0, 1.6))
		_model(COLUMN, 3.6, Vector3(side * 2.4, 0, 1.2 * scale + 2.4))
		_solid(_cylinder_shape(0.6, 4.0), Vector3(side * 2.4, 2.0, 1.2 * scale + 2.4))
	door_local = Vector3(0, 1.4, 1.2 * scale + 0.4)
	exit_local = Vector3(0, 0, 1.2 * scale + 3.6)


func _build_tree() -> void:
	_model(GREAT_TREE, 6.0, Vector3.ZERO)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 1.0
	trunk.bottom_radius = 1.5
	trunk.height = 6.0
	trunk.radial_segments = 14
	_part(trunk, Color(0.4, 0.27, 0.17), Vector3(0, 3.0, 0))
	var body := _solid(_cylinder_shape(TRUNK_RADIUS, 8.0), Vector3(0, 4.0, 0))
	body.collision_layer = Combatant.LAYER_SCENERY
	## The door in the trunk, hidden until the tree is struck.
	var doorway := BoxMesh.new()
	doorway.size = Vector3(1.3, 2.3, 0.3)
	_secret_parts.append(_part(doorway, DARK, Vector3(0, 1.15, 1.32), true))
	var frame := BoxMesh.new()
	frame.size = Vector3(1.6, 2.55, 0.2)
	_secret_parts.append(_part(frame, WOOD.darkened(0.3), Vector3(0, 1.27, 1.26)))
	for part in _secret_parts:
		part.visible = false
	door_local = Vector3(0, 1.0, 1.6)
	exit_local = Vector3(0, 0, 3.6)


func _build_wall() -> void:
	## A boulder mound with a stretch of cracked masonry standing against its face. The kit's
	## wall sits behind its own origin (z -0.5..-0.3), so it is placed by where its face lands.
	_model(MOUND, 5.0, Vector3(0, 0, -1.5))
	_solid(_box_shape(Vector3(7.6, 5.0, 6.6)), Vector3(0, 2.5, -1.5))
	var doorway := BoxMesh.new()
	doorway.size = Vector3(2.4, 2.8, 0.4)
	var hole := _part(doorway, DARK, Vector3(0, 1.4, 2.4), true)
	hole.visible = false
	_secret_parts.append(hole)
	var depth := 4.4 * 1.6
	var wall := _model(CRACKED_WALL, 4.4, Vector3(0, 0, WALL_FACE + 0.3 * depth))
	wall.scale.z = depth
	_cover_parts.append(wall)
	_cover_parts.append(_solid(_box_shape(Vector3(4.4, 3.2, 1.4)), Vector3(0, 1.6, WALL_FACE - 0.7)))
	door_local = Vector3(0, 1.2, WALL_FACE + 0.4)
	exit_local = Vector3(0, 0, WALL_FACE + 2.8)


func _build_grove() -> void:
	## A ring of tall trees with one gap, round a cave mouth in a boulder.
	var count := 16
	for index in count:
		var angle := TAU * index / count
		var around := Vector3(sin(angle), 0.0, cos(angle))
		if around.z > 0.86:
			continue
		var at := around * 10.0
		var tree := _model(GROVE_TREE, 7.0 + float(index % 3) * 0.8, at)
		tree.rotation.y = angle * 3.0
		_solid(_cylinder_shape(1.0, 8.0), at + Vector3(0, 4.0, 0)).collision_layer = Combatant.LAYER_SCENERY
	_model(MOUND, 3.4, Vector3(0, 0, -2.6))
	_solid(_box_shape(Vector3(5.6, 3.8, 4.6)), Vector3(0, 1.9, -2.8))
	_model(CAVE_MOUTH, 1.0, Vector3(0, 0, 0.2))
	var dark := BoxMesh.new()
	dark.size = Vector3(2.6, 3.0, 0.2)
	_part(dark, DARK, Vector3(0, 1.5, -0.5), true)
	door_local = Vector3(0, 1.2, 0.8)
	exit_local = Vector3(0, 0, 4.0)


func _build_stairwell() -> void:
	var tile := ChunkMesher.TILE_SIZE
	var width := WorldGenerator.STAIRWELL_WIDTH * tile
	var length := WorldGenerator.STAIRWELL_LENGTH * tile
	var depth := ChunkMesher.height_to_world(WorldGenerator.STAIRWELL_DEPTH)
	## The door, set into the wall at the bottom.
	var gate := _model(DOOR_GATE, 0.6, Vector3(0, 0, -0.42))
	gate.rotation.y = PI
	var dark := BoxMesh.new()
	dark.size = Vector3(1.9, 2.3, 0.1)
	_part(dark, DARK, Vector3(0, 1.15, 0.02), true)
	## The lid: ground-coloured, flush with the sand, across the whole stairwell.
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(width + 0.2, 0.3, length + 0.2)
	var sand := Season.ground_color(_chunk.biome.id, _chunk.biome.ground_color)
	var lid_at := Vector3(0, depth - 0.15, length * 0.5)
	_cover_parts.append(_part(lid_mesh, sand, lid_at))
	_cover_parts.append(_solid(_box_shape(lid_mesh.size), lid_at))
	## The marked rock on top: a prop like any other, so the glove can lift it.
	var packed := load(SAND_ROCK) as PackedScene
	if packed != null:
		var rock := packed.instantiate() as Node3D
		rock.name = "MarkedRock"
		rock.scale = Vector3.ONE * 6.0
		add_child(rock)
		rock.position = Vector3(0, depth, length * 0.5)
		var body := _solid(_cylinder_shape(1.4, 4.0), rock.position + Vector3(0, 2.0, 0))
		body.collision_layer = Combatant.LAYER_SCENERY
		_rock_index = _chunk.add_liftable(rock, body, 3.0)
		_chunk.prop_lifted.connect(_on_prop_lifted)
	door_local = Vector3(0, 1.0, 0.6)
	exit_local = Vector3(0, 0, 2.6)


func _build_portal() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 1.3
	ring.outer_radius = 1.75
	ring.rings = 24
	_part(ring, PORTAL_GLOW, Vector3(0, 0.12, 0), true)
	var swirl := CylinderMesh.new()
	swirl.top_radius = 1.3
	swirl.bottom_radius = 1.3
	swirl.height = 0.05
	swirl.radial_segments = 24
	_part(swirl, Color(0.1, 0.3, 0.55), Vector3(0, 0.08, 0), true)
	## A pale shaft up to the surface, and a ring on it, so the spot can be found from above.
	var surface := _chunk.terrain.still_surface - position.y
	var shaft := CylinderMesh.new()
	shaft.top_radius = 1.4
	shaft.bottom_radius = 1.4
	shaft.height = surface
	shaft.radial_segments = 16
	shaft.cap_top = false
	shaft.cap_bottom = false
	var beam := _part(shaft, Color(PORTAL_GLOW, 0.18), Vector3(0, surface * 0.5, 0), true)
	(beam.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(beam.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	var marker := TorusMesh.new()
	marker.inner_radius = 1.5
	marker.outer_radius = 1.65
	marker.rings = 24
	_part(marker, PORTAL_GLOW, Vector3(0, surface + 0.03, 0), true)
	var light := OmniLight3D.new()
	light.light_color = PORTAL_GLOW
	light.light_energy = 2.0
	light.omni_range = 6.0
	light.position = Vector3(0, 0.8, 0)
	add_child(light)
	door_local = Vector3.ZERO
	## Back out on the shallows, on the shore side.
	var half := WorldGenerator.CHUNK_TILES / 2
	var shore := half
	var terrain := _chunk.terrain
	while shore < terrain.size - 1 and terrain.level(half, shore) < terrain.base_level - 1:
		shore += 1
	exit_local = _chunk.tile_surface(half, shore) - position


func _model(path: String, scale: float, at: Vector3) -> Node3D:
	var packed := load(path) as PackedScene
	var node: Node3D = packed.instantiate() as Node3D if packed != null else Node3D.new()
	node.scale = Vector3.ONE * scale
	node.position = at
	add_child(node)
	return node


func _part(mesh: Mesh, tint: Color, at: Vector3, glow: bool = false) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	if glow:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance


func _solid(shape: Shape3D, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.position = at
	add_child(body)
	return body


static func _box_shape(size: Vector3) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = size
	return box


static func _cylinder_shape(radius: float, height: float) -> CylinderShape3D:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	return cylinder


# --- revealing -------------------------------------------------------------------------------

## Host: opens the secret, on every peer, and writes it into a saved world.
func reveal() -> void:
	if revealed or not NetworkManager.is_host():
		return
	if NetworkManager.is_networked():
		_net_reveal.rpc()
	else:
		_net_reveal()
	var world := GameWorld.of(self)
	if world != null:
		world.save_progress.call_deferred()


@rpc("authority", "call_local", "reliable")
func _net_reveal() -> void:
	_apply_reveal(true)


## Already open: a saved world loading, or someone joining.
func reveal_quietly() -> void:
	if kind == Kind.ROCK and _rock_index >= 0 and _chunk.can_lift(_rock_index):
		var rock := _chunk.lift_prop(_rock_index)
		if rock != null:
			rock.queue_free()
	_apply_reveal(false)


func _apply_reveal(loud: bool) -> void:
	if revealed:
		return
	revealed = true
	if loud and kind == Kind.WALL:
		_crumble()
	for part in _cover_parts:
		if is_instance_valid(part):
			part.queue_free()
	_cover_parts.clear()
	for part in _secret_parts:
		part.visible = true
		if loud:
			part.scale = Vector3(1.0, 0.05, 1.0)
			part.create_tween().tween_property(part, "scale", Vector3.ONE, 0.5) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _label != null and kind != Kind.LAKE:
		_label.visible = true
	if loud:
		GameSfx.play_at(&"secret", global_position + door_local)


## The cracked wall bursts into pieces of itself.
func _crumble() -> void:
	for part in _cover_parts:
		if not part is Node3D or part is StaticBody3D:
			continue
		var meshes := Culling.meshes_under(part as Node3D)
		if meshes.is_empty() or meshes[0].mesh == null:
			continue
		var shards := RockShards.new()
		GameWorld.effects_root(get_tree()).add_child(shards)
		shards.burst(meshes[0], (part as Node3D).global_position + Vector3.UP * 1.4,
				meshes[0].global_transform.basis.get_scale().x)
	GameSfx.play_at(&"rock_shatter", global_position + door_local)


## The marked rock has been lifted (on every peer, as part of the lift): the stairwell opens.
func _on_prop_lifted(index: int) -> void:
	if index != _rock_index or revealed:
		return
	_apply_reveal(true)
	if NetworkManager.is_host():
		var world := GameWorld.of(self)
		if world != null:
			world.save_progress.call_deferred()


# --- finding ---------------------------------------------------------------------------------

func door_position() -> Vector3:
	return to_global(door_local)


func exit_position() -> Vector3:
	return to_global(exit_local)


static func all(tree: SceneTree) -> Array[DungeonEntrance]:
	var found: Array[DungeonEntrance] = []
	for node in tree.get_nodes_in_group(GROUP):
		if node is DungeonEntrance:
			found.append(node)
	return found


static func for_dungeon(tree: SceneTree, id: StringName) -> DungeonEntrance:
	for entrance in all(tree):
		if entrance.dungeon_id == id:
			return entrance
	return null


## The open door a player standing at `at` could go through, or null.
static func near_door(tree: SceneTree, at: Vector3) -> DungeonEntrance:
	for entrance in all(tree):
		if entrance.revealed and entrance.kind != Kind.LAKE \
				and entrance.door_position().distance_to(at) < ENTER_RADIUS:
			return entrance
	return null


## The lake portal, if a diver at `at` is down at it.
static func portal_near(tree: SceneTree, at: Vector3) -> DungeonEntrance:
	for entrance in all(tree):
		if entrance.kind != Kind.LAKE:
			continue
		var offset := at - entrance.global_position
		if Vector2(offset.x, offset.z).length() < PORTAL_REACH and offset.y < PORTAL_ABOVE:
			return entrance
	return null


## Host: something hit hard at `point` -- a blade, an arrow, a bolt, a thrown rock. A great tree
## with a door in it gives the door up.
static func struck(tree: SceneTree, point: Vector3, radius: float) -> void:
	if not NetworkManager.is_host():
		return
	## A crate in reach breaks open too.
	Chunk.struck(tree, point, radius)
	for entrance in all(tree):
		if entrance.kind != Kind.TREE or entrance.revealed:
			continue
		var offset := point - entrance.global_position
		if Vector2(offset.x, offset.z).length() <= radius + TRUNK_RADIUS and offset.y > -2.0 \
				and offset.y < 6.0:
			entrance.reveal()


## Host: a bomb went off at `at`. A cracked wall in reach gives way.
static func blasted(tree: SceneTree, at: Vector3, radius: float) -> void:
	if not NetworkManager.is_host():
		return
	for entrance in all(tree):
		if entrance.kind != Kind.WALL or entrance.revealed:
			continue
		var wall := entrance.to_global(Vector3(0, 1.6, WALL_FACE - 0.7))
		if wall.distance_to(at) <= radius + WALL_REACH:
			entrance.reveal()


## Names of the entrances opened so far, for a saved world and for someone joining.
static func revealed_names(tree: SceneTree) -> PackedStringArray:
	var names := PackedStringArray()
	for entrance in all(tree):
		if entrance.revealed and KINDS.get(entrance.dungeon_id) in [Kind.ROCK, Kind.TREE, Kind.WALL]:
			names.append(String(entrance.name))
	return names


static func reveal_named(tree: SceneTree, names: PackedStringArray) -> void:
	for entrance in all(tree):
		if names.has(String(entrance.name)):
			entrance.reveal_quietly()

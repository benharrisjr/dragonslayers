class_name BugSwarm
extends Node3D

## The bugs flying about one chunk, there to be caught with a bug net and traded at the shop.
##
## Every peer builds the same bugs in the same places from the seed, so a bug's index names it
## across the network. Their flight is decoration -- each machine loops them about their home
## point on its own clock -- and only which ones have been caught is shared, by the player who
## caught them (PlayerCharacter._net_catch_bugs).
##
## One node runs the whole chunk's worth rather than each bug running itself, and it stops
## altogether while nobody is near.

## How many each kind of chunk has. None on the mountain: the dragon's arena is not a meadow.
const COUNTS: Dictionary = {
	&"town": 5, &"plains": 6, &"fields": 8, &"forest": 8, &"lake": 7,
	&"desert": 3, &"beach": 3, &"temple": 2,
}
## A caught bug is replaced after this long, so the shop never runs out of customers.
const RESPAWN_TIME := 50.0
const ACTIVE_RANGE := 120.0
const DRAW_RANGE := 70.0
const COLORS: Array[Color] = [
	Color(0.95, 0.8, 0.2), Color(0.4, 0.75, 0.95), Color(0.95, 0.45, 0.6), Color(0.6, 0.9, 0.4),
]

static var _body_mesh: SphereMesh
static var _wing_mesh: BoxMesh
static var _wing_material: StandardMaterial3D
static var _body_materials: Array[StandardMaterial3D] = []

## Each: {"home", "phase", "speed", "radius", "node", "wings", "away"}; "away" is the seconds
## left before a caught bug comes back, 0 while it is flying.
var _bugs: Array[Dictionary] = []
var _time: float = 0.0
var _check: float = randf() * Culling.CHECK_INTERVAL
var _active: bool = true


## `homes` are chunk-local positions on the ground.
func build(homes: Array[Vector3], rng: RandomNumberGenerator) -> void:
	add_to_group("bug_swarms")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ensure_shared()
	for home in homes:
		var node := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = _body_mesh
		body.material_override = _body_materials[rng.randi() % _body_materials.size()]
		body.scale = Vector3(0.7, 0.7, 1.5)
		node.add_child(body)
		var wings: Array[MeshInstance3D] = []
		for side in [-1.0, 1.0]:
			var wing := MeshInstance3D.new()
			wing.mesh = _wing_mesh
			wing.material_override = _wing_material
			wing.position = Vector3(side * 0.16, 0.06, 0.0)
			node.add_child(wing)
			wings.append(wing)
		for mesh: MeshInstance3D in [body, wings[0], wings[1]]:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.visibility_range_end = DRAW_RANGE
		add_child(node)
		_bugs.append({
			"home": home + Vector3.UP * rng.randf_range(1.1, 1.9),
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.7, 1.3),
			"radius": rng.randf_range(1.2, 2.6),
			"node": node, "wings": wings, "away": 0.0,
		})
	_place(0.0)


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = Culling.CHECK_INTERVAL
		var middle := global_position \
				+ Vector3(WorldGenerator.CHUNK_SIZE, 0.0, WorldGenerator.CHUNK_SIZE) * 0.5
		_active = Culling.distance_to_nearest_player(middle) <= ACTIVE_RANGE
	if _active:
		_time += delta
		_place(delta)


func _place(delta: float) -> void:
	var flap := sin(_time * 38.0) * 0.9
	for bug in _bugs:
		var node := bug["node"] as Node3D
		if bug["away"] > 0.0:
			bug["away"] = maxf(0.0, float(bug["away"]) - delta)
			if bug["away"] <= 0.0:
				node.visible = true
			continue
		var at := _time * float(bug["speed"]) + float(bug["phase"])
		var radius: float = bug["radius"]
		## A wobbling loop: two sines a little out of step, so no two bugs trace the same path.
		var offset := Vector3(cos(at) * radius, sin(at * 1.7) * 0.35, sin(at * 1.3) * radius)
		var next := (bug["home"] as Vector3) + offset
		var heading := next - node.position
		node.position = next
		if heading.length_squared() > 0.000001:
			node.rotation.y = atan2(heading.x, heading.z)
		var wings: Array[MeshInstance3D] = bug["wings"]
		wings[0].rotation.z = flap
		wings[1].rotation.z = -flap


func count() -> int:
	return _bugs.size()


func is_flying(index: int) -> bool:
	return index >= 0 and index < _bugs.size() and _bugs[index]["away"] <= 0.0


func bug_position(index: int) -> Vector3:
	return (_bugs[index]["node"] as Node3D).global_position


## The bugs a net swung from `at` towards `facing` would catch: flying, within `reach` across
## the ground, not behind the swing, and not far above or below it.
func in_reach(at: Vector3, facing: Vector3, reach: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	for index in _bugs.size():
		if not is_flying(index):
			continue
		var offset := bug_position(index) - at
		if offset.y < -1.0 or offset.y > 4.0:
			continue
		offset.y = 0.0
		var distance := offset.length()
		if distance <= reach and (distance < 1.0 or facing.dot(offset / distance) > 0.1):
			found.append(index)
	return found


## Takes a bug out of the air on this peer. False if it was already gone, which is what stops
## two nets counting the same bug twice.
func take(index: int) -> bool:
	if not is_flying(index):
		return false
	_bugs[index]["away"] = RESPAWN_TIME
	(_bugs[index]["node"] as Node3D).visible = false
	return true


static func _ensure_shared() -> void:
	if _body_mesh != null:
		return
	_body_mesh = SphereMesh.new()
	_body_mesh.radius = 0.13
	_body_mesh.height = 0.26
	_body_mesh.radial_segments = 6
	_body_mesh.rings = 3
	_wing_mesh = BoxMesh.new()
	_wing_mesh.size = Vector3(0.3, 0.015, 0.2)
	_wing_material = StandardMaterial3D.new()
	_wing_material.albedo_color = Color(0.95, 0.97, 1.0)
	_wing_material.emission_enabled = true
	_wing_material.emission = Color(0.8, 0.85, 0.9)
	_wing_material.emission_energy_multiplier = 0.4
	for tint in COLORS:
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = 0.7
		_body_materials.append(material)

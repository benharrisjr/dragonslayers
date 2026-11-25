class_name FlameStream
extends Node3D

## A gout of dragon fire, from the mouth to a point on the ground: a stream of glowing blobs that
## swell and fade as they fly. Picture only -- what burns is the FirePatch the dragon lays where it
## lands, and only the host decides what that hurts.

const BLOBS := 30
const FLIGHT := 0.45
const LIFE := 1.3
const COLOURS: Array[Color] = [Color(1.0, 0.85, 0.3), Color(1.0, 0.55, 0.15), Color(0.95, 0.3, 0.08)]

static var _mesh: SphereMesh
static var _materials: Array[StandardMaterial3D] = []

var _mouth: Callable
var _target: Vector3
var _age: float = 0.0
## Each: [MeshInstance3D, start delay, sideways offset at the far end].
var _blobs: Array[Array] = []


## `mouth` is called every frame for where the fire comes from, so it follows a moving head.
func pour(mouth: Callable, target: Vector3, spread: float = 1.2) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	_mouth = mouth
	_target = target
	_build_shared()
	for index in BLOBS:
		var blob := MeshInstance3D.new()
		blob.mesh = _mesh
		blob.material_override = _materials[index % _materials.size()]
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blob.visible = false
		add_child(blob)
		_blobs.append([blob, randf() * (LIFE - FLIGHT - 0.1),
				Vector3(randf_range(-1, 1), randf_range(0, 0.6), randf_range(-1, 1)) * spread])


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFE:
		queue_free()
		return
	var from: Vector3 = _mouth.call() if _mouth.is_valid() else _target
	for entry in _blobs:
		var blob: MeshInstance3D = entry[0]
		var t: float = (_age - float(entry[1])) / FLIGHT
		if t < 0.0 or t > 1.0:
			blob.visible = false
			continue
		blob.visible = true
		blob.global_position = from.lerp(_target + (entry[2] as Vector3), t)
		blob.scale = Vector3.ONE * lerpf(0.4, 1.6, t) * (1.0 - t * 0.3)


static func _build_shared() -> void:
	if _mesh != null:
		return
	_mesh = SphereMesh.new()
	_mesh.radius = 0.5
	_mesh.height = 1.0
	_mesh.radial_segments = 8
	_mesh.rings = 4
	for colour in COLOURS:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = colour
		material.emission_enabled = true
		material.emission = colour
		_materials.append(material)

class_name Gust
extends Node3D

## The look of a fan's gust: a handful of pale streaks rushing away from whoever waved it.
##
## Picture only. The shove itself is worked out on the host (PlayerCharacter._request_gust);
## this is built on every peer so everyone sees the wind they were just hit by.

const LIFE := 0.4
const STREAKS := 7

static var _mesh: BoxMesh
static var _material: StandardMaterial3D

var _age: float = 0.0
var _reach: float = 7.0
## Each: [MeshInstance3D, sideways offset, height, head start].
var _streaks: Array[Array] = []


func blow(origin: Vector3, aim: Vector3, reach: float, half_angle: float) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_reach = reach
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3(0.08, 0.08, 1.6)
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.9, 0.97, 1.0)
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flat := Vector3(aim.x, 0.0, aim.z)
	flat = flat.normalized() if flat.length_squared() > 0.001 else Vector3.BACK
	global_transform = Transform3D(Basis.looking_at(-flat, Vector3.UP), origin)
	for index in STREAKS:
		var streak := MeshInstance3D.new()
		streak.mesh = _mesh
		streak.material_override = _material
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(streak)
		var across := (float(index) / float(STREAKS - 1) - 0.5) * 2.0
		_streaks.append([streak, tan(half_angle) * across, 0.5 + fmod(index * 0.61, 1.0) * 1.4,
				fmod(index * 0.37, 1.0) * 0.25])
	_place()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	_place()


func _place() -> void:
	for entry in _streaks:
		var streak := entry[0] as MeshInstance3D
		var t := clampf(_age / LIFE + float(entry[3]), 0.0, 1.0)
		var along := 0.8 + t * _reach
		## Fans out as it goes, and thins to nothing at the end of its reach.
		streak.position = Vector3(float(entry[1]) * along, float(entry[2]), along)
		streak.scale = Vector3(1.0 - t, 1.0 - t, 1.0)

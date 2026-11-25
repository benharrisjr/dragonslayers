class_name Torch
extends Node3D

## A torch on a post beside a path. Its flame burns from dusk to dawn (DayNight). It has no light of
## its own: there are far more torches than a renderer wants lights, so DayNight keeps a few and
## moves them to the torches nearest the players.

const GROUP := &"torches"
const HEIGHT := 1.9
const FLAME := Vector3(0.0, 2.15, 0.0)

var _flame: Node3D


func _init() -> void:
	add_to_group(GROUP)
	_part(_cylinder(0.07, 0.1, HEIGHT), Color(0.36, 0.23, 0.13), HEIGHT * 0.5)
	_part(_cylinder(0.2, 0.1, 0.22), Color(0.22, 0.2, 0.2), HEIGHT + 0.06)
	_flame = Node3D.new()
	add_child(_flame)
	for layer: Array in [[0.17, 0.5, Color(1.0, 0.45, 0.08), 2.38], [0.1, 0.32, Color(1.0, 0.85, 0.35), 2.32]]:
		var mesh := _cylinder(0.0, layer[0], layer[1])
		var material := StandardMaterial3D.new()
		material.albedo_color = layer[2]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.position.y = layer[3]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = 120.0
		_flame.add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = Combatant.LAYER_SCENERY
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var post := CylinderShape3D.new()
	post.radius = 0.15
	post.height = HEIGHT + 2.0
	shape.shape = post
	shape.position.y = HEIGHT * 0.5 - 1.0
	body.add_child(shape)
	add_child(body)
	_flame.visible = false


func set_lit(on: bool) -> void:
	_flame.visible = on


func flame_position() -> Vector3:
	return global_position + FLAME


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1
	return mesh


func _part(mesh: Mesh, color: Color, y: float) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position.y = y
	instance.visibility_range_end = 90.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

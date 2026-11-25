@tool
class_name DoorSpot
extends Marker3D

## The way out of a dungeon: a door set against a wall, facing into the room down its local +z.
## Standing in front of it and pressing interact goes back up to where the dungeon was entered.

const MODEL := "res://art/kenney_modular-dungeon-kit_1/Models/GLB format/gate-door.glb"
const MODEL_SCALE := 0.62

var _built: Node3D


func _ready() -> void:
	if _built != null:
		return
	_built = Node3D.new()
	_built.name = "DoorModel"
	add_child(_built, false, Node.INTERNAL_MODE_FRONT)
	var packed := load(MODEL) as PackedScene
	if packed != null:
		var model := packed.instantiate() as Node3D
		model.scale = Vector3.ONE * MODEL_SCALE
		_built.add_child(model)
	var dark := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.9, 2.4, 0.1)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.02, 0.02, 0.03)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = material
	dark.mesh = box
	dark.position = Vector3(0, 1.2, -0.1)
	_built.add_child(dark)
	if Engine.is_editor_hint():
		return
	var label := Label3D.new()
	label.text = "Leave"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.outline_size = 14
	label.pixel_size = 0.01
	label.no_depth_test = true
	label.visibility_range_end = 14.0
	label.position = Vector3(0, 3.2, 0.4)
	_built.add_child(label)


## Where a player has to stand to use it.
func door_position() -> Vector3:
	return to_global(Vector3(0, 1.0, 0.8))

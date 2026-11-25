@tool
class_name ChestSpot
extends Marker3D

## Where a chest sits in a dungeon scene, facing down its local +z. Swapped for a real chest when
## the dungeon is built, named in scene order, so a saved world remembers which ones are open.

## Pays more and is drawn bigger.
@export var large: bool = false:
	set(value):
		large = value
		_refresh_preview()
## Gold inside (shared by the party).
@export var gold: int = 20
## The dungeon's big chest: it holds the dungeon's reward (Dungeon.reward_item) and is locked
## until the guardian falls. One per dungeon.
@export var big: bool = false:
	set(value):
		big = value
		_refresh_preview()

var _preview: MeshInstance3D


func _ready() -> void:
	_refresh_preview()


func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		add_child(_preview, false, Node.INTERNAL_MODE_FRONT)
	var size := 1.4 if large or big else 1.0
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.4, 1.6) * size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.85, 1.0) if big else Color(0.85, 0.65, 0.3)
	box.material = material
	_preview.mesh = box
	_preview.position.y = 0.7 * size

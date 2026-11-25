@tool
class_name MonsterSpot
extends Marker3D

## Where a monster stands in a dungeon scene. When the dungeon is built it is swapped for the real
## thing, named in scene order so it is the same monster on every machine. Move these about,
## copy them, or change what they are in the inspector.

## A MonsterDB id: skeleton_minion, skeleton_warrior, skeleton_rogue, skeleton_mage, or
## skeleton_champion for a guardian.
@export var monster_id: StringName = &"skeleton_minion":
	set(value):
		monster_id = value
		_refresh_preview()
## The dungeon's guardian. Its big chest stays locked until this one falls; one per dungeon.
@export var boss: bool = false:
	set(value):
		boss = value
		_refresh_preview()

var _preview: MeshInstance3D


func _ready() -> void:
	_refresh_preview()


## A capsule in the editor so the spot can be seen and grabbed: red for a guardian, otherwise
## bone. Never part of the saved scene, and not built in the game.
func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		add_child(_preview, false, Node.INTERNAL_MODE_FRONT)
	var size := 1.7 if boss else 1.0
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4 * size
	capsule.height = 1.7 * size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.2, 0.2) if boss else Color(0.85, 0.82, 0.7)
	capsule.material = material
	_preview.mesh = capsule
	_preview.position.y = 0.85 * size

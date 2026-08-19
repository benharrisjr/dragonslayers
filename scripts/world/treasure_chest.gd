class_name TreasureChest
extends StaticBody3D

## A chest. Walk up, press interact, get paid.
##
## Large chests are the ability-reward track rather than the gold track; for now they simply pay
## more, and `is_large` is the hook the ability drop system will read.

signal opened(chest: TreasureChest)

const MODEL_PATH := "res://art/kenney_survival-kit/Models/GLB format/chest.glb"
const MODEL_SCALE := 2.4
const INTERACT_RADIUS := 2.6

@export var is_large: bool = false

var gold_value: int = 20
var is_open: bool = false

var _lid: Node3D
var _prompt: Node3D


func setup(large: bool, value: int) -> void:
	is_large = large
	gold_value = value
	add_to_group("chests")
	_build_visual()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.7, 0.8) * (1.4 if large else 1.0)
	shape.shape = box
	shape.position.y = 0.35
	add_child(shape)


## Called by a player standing close enough and pressing interact. Host-authoritative so two
## players cannot both open the same chest on the same frame.
func try_open(player: PlayerCharacter) -> bool:
	if is_open or player == null:
		return false
	if player.global_position.distance_to(global_position) > INTERACT_RADIUS:
		return false
	if not NetworkManager.is_host():
		_request_open.rpc_id(1)
		return true
	_request_open()
	return true


@rpc("any_peer", "call_local", "reliable")
func _request_open() -> void:
	if not NetworkManager.is_host() or is_open:
		return
	if NetworkManager.is_networked():
		_net_open.rpc()
	else:
		_net_open()


@rpc("authority", "call_local", "reliable")
func _net_open() -> void:
	if is_open:
		return
	is_open = true
	if _lid != null:
		var tween := create_tween()
		tween.tween_property(_lid, "rotation_degrees:x", -100.0, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _prompt != null:
		_prompt.visible = false
	opened.emit(self)


func _build_visual() -> void:
	var packed: PackedScene = load(MODEL_PATH)
	if packed != null:
		var model := packed.instantiate() as Node3D
		model.scale = Vector3.ONE * MODEL_SCALE * (1.4 if is_large else 1.0)
		add_child(model)
		## The Kenney chest is a single mesh, so the "lid" is the whole model tipping back --
		## cheap, and at this art scale it reads exactly like a chest opening.
		_lid = model

	## A floating marker so a chest is findable across a 64 m chunk full of trees.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, 0.25, 0.25)
	var material := StandardMaterial3D.new()
	var color := Color(1.0, 0.85, 0.3) if not is_large else Color(0.6, 0.85, 1.0)
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	_prompt = MeshInstance3D.new()
	_prompt.mesh = mesh
	_prompt.position.y = 1.9
	add_child(_prompt)

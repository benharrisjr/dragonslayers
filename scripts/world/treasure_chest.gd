class_name TreasureChest
extends StaticBody3D

## A chest. Walk up, press interact, get paid.
##
## The large chest in each chunk is the gear chest: besides paying more, it holds one item
## (`item_id`), which lands in front of it when it is opened.

signal opened(chest: TreasureChest)

const MODEL_PATH := "res://art/kenney_survival-kit/Models/GLB format/chest.glb"
## Twice the kit's natural fit for this world, so a chest reads from across a chunk.
const SIZE := 2.0
const MODEL_SCALE := 2.4 * SIZE
const INTERACT_RADIUS := 3.8

@export var is_large: bool = false

var gold_value: int = 20
## The piece of gear inside, or &"" for a chest that only holds gold.
var item_id: StringName = &""
var is_open: bool = false
## A dungeon's big chest stays locked until its guardian is beaten (Dungeon). Opened chests are
## never locked.
var locked: bool = false

var _lid: Node3D
var _padlock: Node3D
var _prompt: Node3D


func setup(large: bool, value: int) -> void:
	is_large = large
	gold_value = value
	add_to_group("chests")
	_build_visual()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.7, 0.8) * SIZE * (1.4 if large else 1.0)
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	add_child(shape)


## Called by a player standing close enough and pressing interact. Host-authoritative so two
## players cannot both open the same chest on the same frame.
func try_open(player: PlayerCharacter) -> bool:
	if is_open or player == null:
		return false
	if locked:
		GameSfx.play_at(&"door", global_position)
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
	if not NetworkManager.is_host() or is_open or locked:
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
	GameSfx.play_at(&"chest", global_position)
	if _lid != null:
		var tween := create_tween()
		tween.tween_property(_lid, "rotation_degrees:x", -100.0, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _prompt != null:
		_prompt.visible = false
	opened.emit(self)


## Already opened in an earlier session of a saved world (or before someone joined): shown open,
## with nothing spilling out -- `opened` is not emitted, so no loot is spawned again.
func set_open_quietly() -> void:
	if is_open:
		return
	unlock_quietly()
	is_open = true
	if _lid != null:
		_lid.rotation_degrees.x = -100.0
	if _prompt != null:
		_prompt.visible = false


## Locks it, with a padlock on the front to show it. Every peer, at build time.
func lock() -> void:
	if locked or is_open:
		return
	locked = true
	_padlock = Node3D.new()
	_padlock.name = "Padlock"
	var body := BoxMesh.new()
	body.size = Vector3(0.5, 0.45, 0.2)
	var shackle := TorusMesh.new()
	shackle.inner_radius = 0.12
	shackle.outer_radius = 0.18
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.75, 0.25)
	gold.metallic = 0.6
	gold.roughness = 0.35
	body.material = gold
	shackle.material = gold
	var block := MeshInstance3D.new()
	block.mesh = body
	_padlock.add_child(block)
	var loop := MeshInstance3D.new()
	loop.mesh = shackle
	loop.rotation_degrees.x = 90.0
	loop.position.y = 0.28
	_padlock.add_child(loop)
	_padlock.position = Vector3(0.0, 0.55, 0.62) * SIZE * (1.4 if is_large else 1.0)
	add_child(_padlock)


## Host: takes the lock off, on every peer.
func unlock() -> void:
	if not locked or not NetworkManager.is_host():
		return
	if NetworkManager.is_networked():
		_net_unlock.rpc()
	else:
		_net_unlock()


@rpc("authority", "call_local", "reliable")
func _net_unlock() -> void:
	if not locked:
		return
	unlock_quietly()
	GameSfx.play_at(&"secret", global_position)


## Unlocked without a fanfare: a saved world loading, or someone joining.
func unlock_quietly() -> void:
	locked = false
	if _padlock != null:
		_padlock.queue_free()
		_padlock = null


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
	_prompt.position.y = 1.9 * SIZE
	add_child(_prompt)

class_name Dragon
extends Combatant

## The boss on the mountain, converted from the supplied dragon.3ds by tools/convert_dragon.py.
##
## Milestone 1 puts it on the summit as a living landmark: it breathes, shifts its wings and
## sways its tail, and it can be hit, but it does not yet fight back. The attack set -- fire
## breath, claw swipe, tail sweep, wing flap -- is authored on this same rig in Milestone 4,
## which is why the bone names are treated as an interface here rather than as incidental data.
##
## The idle is driven from code rather than baked into the .glb because the converter emits
## geometry and skeleton only: keeping animation on this side means timings can be tuned
## against real hitboxes without regenerating the model.

const MODEL_PATH := "res://art/models/dragon.glb"

## The rig the converter produces. Anything that animates the dragon goes through these names,
## so swapping in a differently-authored model means matching this list and nothing else.
const BONES := {
	"wing_l": ["wing_l_root", "wing_l_mid", "wing_l_tip"],
	"wing_r": ["wing_r_root", "wing_r_mid", "wing_r_tip"],
	"tail": ["tail_1", "tail_2", "tail_3", "tail_4"],
	"neck": ["neck", "head"],
	"body": ["root", "hips", "spine", "chest"],
}

var skeleton: Skeleton3D

var _time: float = 0.0
var _bone_ids: Dictionary = {}


func configure() -> void:
	faction = Faction.MONSTER
	max_health = 240
	health = max_health
	## Immovable: a boss that can be shield-bashed off its own mountain is not a boss.
	knockback_resistance = 0.0
	name = "Dragon"

	var packed: PackedScene = load(MODEL_PATH)
	if packed == null:
		push_error("Dragon: %s missing -- run tools/convert_dragon.py" % MODEL_PATH)
		return
	var model := packed.instantiate() as Node3D
	add_child(model)
	skeleton = _find_skeleton(model)
	if skeleton == null:
		push_error("Dragon: converted model has no Skeleton3D")
		return
	for group: String in BONES:
		for bone_name: String in BONES[group]:
			_bone_ids[bone_name] = skeleton.find_bone(bone_name)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 2.0
	capsule.height = 5.0
	shape.shape = capsule
	shape.position.y = 2.5
	add_child(shape)
	add_to_group("dragon")


func _physics_process(delta: float) -> void:
	_tick_knockback(delta)
	if not is_on_floor():
		velocity.y -= gravity() * delta
		move_and_slide()
	_idle_pose(delta)


## A slow breathing sway. Small amplitudes on purpose: at 5.6 m tall, a few degrees of wing
## movement is already metres of travel at the tip.
func _idle_pose(delta: float) -> void:
	if skeleton == null:
		return
	_time += delta
	var breath := sin(_time * 0.9)
	var sway := sin(_time * 0.55)

	_pose("wing_l_root", Vector3(0, 0, -1), 0.10 + breath * 0.06)
	_pose("wing_r_root", Vector3(0, 0, 1), 0.10 + breath * 0.06)
	_pose("wing_l_mid", Vector3(0, 0, -1), breath * 0.05)
	_pose("wing_r_mid", Vector3(0, 0, 1), breath * 0.05)
	_pose("tail_1", Vector3(0, 1, 0), sway * 0.10)
	_pose("tail_2", Vector3(0, 1, 0), sway * 0.13)
	_pose("tail_3", Vector3(0, 1, 0), sway * 0.16)
	_pose("tail_4", Vector3(0, 1, 0), sway * 0.18)
	_pose("neck", Vector3(1, 0, 0), breath * 0.05)
	_pose("chest", Vector3(1, 0, 0), breath * 0.02)


func _pose(bone_name: String, axis: Vector3, angle: float) -> void:
	var id: int = _bone_ids.get(bone_name, -1)
	if id < 0:
		return
	skeleton.set_bone_pose_rotation(id, Quaternion(axis.normalized(), angle))


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

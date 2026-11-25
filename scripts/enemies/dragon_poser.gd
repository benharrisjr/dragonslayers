class_name DragonPoser
extends SkeletonModifier3D

## Lays the dragon's attack poses over whatever its own animation is doing.
##
## The model comes with its own loops -- idle, walk, run, flying -- played by its AnimationPlayer.
## The attacks (claw, wing beat, tail sweep, fire breath, roar) are not in it, so they are added
## here, after the animation has posed the skeleton each frame: SkeletonModifier3D runs at exactly
## that point. That way the dragon keeps breathing and shifting under an attack rather than
## freezing into it.
##
## `offsets` maps a bone name to a rotation in the skeleton's own space (head towards +Z, up +Y,
## the left wing along +X) -- see DragonAnimator. Each is applied about the bone's own joint, on
## top of its parent's, so rotating every bone of the neck a little bends the whole neck.

var offsets: Dictionary = {}

var _ids: Dictionary = {}


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or offsets.is_empty():
		return
	## Parents before children, so each bone turns on top of the turn its parent just took.
	var order: Array[int] = []
	for bone: String in offsets:
		var id := _id(skeleton, bone)
		if id >= 0:
			order.append(id)
	order.sort()
	for id in order:
		var rotation: Quaternion = offsets[skeleton.get_bone_name(id)]
		var parent := skeleton.get_bone_parent(id)
		var parent_turn := Quaternion.IDENTITY
		if parent >= 0:
			parent_turn = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
		## The turn is wanted in skeleton space; a bone's pose is in its parent's space.
		var local := parent_turn.inverse() * rotation * parent_turn
		skeleton.set_bone_pose_rotation(id, local * skeleton.get_bone_pose_rotation(id))


func _id(skeleton: Skeleton3D, bone: String) -> int:
	if not _ids.has(bone):
		_ids[bone] = skeleton.find_bone(bone)
	return _ids[bone]

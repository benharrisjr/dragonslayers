class_name CharacterVisual
extends Node3D

## Builds a KayKit character at runtime: mesh, animation player, weapons in hand.
##
## Built in code rather than as four authored .tscn files because the four adventurers and
## every skeleton enemy differ only in which .glb to load and which weapons to hang off the
## rig -- four near-identical scene files would be four places to forget the same fix. The
## animation clips are not in the character files at all; they come from RigAnimations.
##
## The AnimationPlayer is parented to the model's own root because the imported clips address
## bones as "Rig_Medium/Skeleton3D:hips", a path that only resolves from there.

## KayKit adventurers are 2.2-2.6 units tall as authored, which would make them the size of a
## Kenney town tree. 0.75 puts them at roughly 1.8 m in a world where one unit is one metre.
const MODEL_SCALE := 0.75

## How long a clip cross-fades into the next. Long enough to hide the pop between run and idle,
## short enough that an attack still lands on the frame the timing table says it does.
const BLEND_TIME := 0.12

signal action_finished

var animation_player: AnimationPlayer
var skeleton: Skeleton3D

var _model_root: Node3D
var _action_clip: String = ""
var _loop_clip: String = ""
var _loop_speed: float = 1.0
var _attachments: Dictionary = {}


## `model_path` is a character .glb; `weapon_paths` maps a bone name (handslot.l / handslot.r)
## to a weapon .gltf.
func build(model_path: String, weapon_paths: Dictionary = {}, extra_scale: float = 1.0) -> bool:
	var packed: PackedScene = load(model_path)
	if packed == null:
		push_error("CharacterVisual: no model at %s" % model_path)
		return false

	_model_root = packed.instantiate() as Node3D
	add_child(_model_root)
	_model_root.scale = Vector3.ONE * (MODEL_SCALE * extra_scale)

	skeleton = _find_skeleton(_model_root)
	if skeleton == null:
		push_error("CharacterVisual: %s has no Skeleton3D" % model_path)
		return false

	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	## Default root_node is "..", i.e. the model root -- exactly what the clip track paths
	## expect, so no explicit root_node assignment is needed or wanted here.
	_model_root.add_child(animation_player)
	RigAnimations.attach(animation_player)
	animation_player.animation_finished.connect(_on_animation_finished)

	for bone: String in weapon_paths:
		_attach_to_bone(bone, weapon_paths[bone])
	return true


## Looping locomotion clip. Ignored while an action (an attack, a hit reaction) is playing, so
## walking does not cancel a swing.
func set_loop(clip: String, speed: float = 1.0) -> void:
	if _loop_clip == clip:
		return
	_loop_clip = clip
	_loop_speed = speed
	if _action_clip.is_empty():
		_play(clip, speed, true)


## One-shot clip that owns the body until it finishes -- attacks, hit reactions, death.
func play_action(clip: String, speed: float = 1.0) -> void:
	if animation_player == null or not RigAnimations.has_clip(clip):
		return
	_action_clip = clip
	_play(clip, speed, false)


func stop_action() -> void:
	_action_clip = ""
	if not _loop_clip.is_empty():
		_play(_loop_clip, _loop_speed, true)


func is_acting() -> bool:
	return not _action_clip.is_empty()


## Death poses freeze rather than looping back to idle, so a corpse stays a corpse.
func play_death(clip: String) -> void:
	if animation_player == null or not RigAnimations.has_clip(clip):
		return
	_action_clip = "death"
	animation_player.play(clip, BLEND_TIME)


func tint(color: Color) -> void:
	## A flat additive tint on every surface, used to mark whose player is whose in a
	## split-screen scrum where four identically-coloured knights would be unreadable.
	for mesh in _find_meshes(_model_root):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color * 0.25
		mesh.material_overlay = null
		mesh.set_instance_shader_parameter("tint", color)


## Dyes the character's clothes for an armour level: 0 is their own colours, 1 blue, 2 red
## (cloth_tint.gdshader). Only the body is dyed, not what is held in its hands.
func set_armor_tint(level: int) -> void:
	for mesh in _body_meshes(_model_root):
		for surface in mesh.get_surface_override_material_count():
			if level <= 0:
				mesh.set_surface_override_material(surface, null)
				continue
			var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null:
				continue
			mesh.set_surface_override_material(surface, CharacterVisual.dyed(original, level))
		if level <= 0:
			ComicLook.apply(mesh)


## Armour colours by level, as hues.
const ARMOR_HUES: Array[float] = [0.0, 0.6, 0.0]

## One dyed material per original material and level, shared by everyone wearing it.
static var _dyed: Dictionary = {}


static func dyed(original: StandardMaterial3D, level: int) -> ShaderMaterial:
	var key := "%d:%d" % [original.get_instance_id(), level]
	if _dyed.has(key):
		return _dyed[key]
	var material := ShaderMaterial.new()
	material.shader = ComicLook.shader_for(preload("res://scripts/characters/cloth_tint.gdshader"))
	material.set_shader_parameter("albedo_texture", original.albedo_texture)
	material.set_shader_parameter("albedo_color", original.albedo_color)
	material.set_shader_parameter("roughness", original.roughness)
	material.set_shader_parameter("metallic", original.metallic)
	material.set_shader_parameter("dye_hue", ARMOR_HUES[clampi(level, 0, ARMOR_HUES.size() - 1)])
	_dyed[key] = material
	return material


func _body_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node == null or node is BoneAttachment3D:
		return out
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_body_meshes(child))
	return out


func attachment(bone: String) -> Node3D:
	return _attachments.get(bone)


func _play(clip: String, speed: float, looping: bool) -> void:
	if animation_player == null or not RigAnimations.has_clip(clip):
		return
	animation_player.play(clip, BLEND_TIME, speed)
	var anim := animation_player.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE


func _on_animation_finished(_clip: StringName) -> void:
	if _action_clip.is_empty() or _action_clip == "death":
		return
	_action_clip = ""
	action_finished.emit()
	if not _loop_clip.is_empty():
		_play(_loop_clip, _loop_speed, true)


func _attach_to_bone(bone_name: String, model_path: String) -> void:
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		push_warning("CharacterVisual: rig has no bone '%s'" % bone_name)
		return
	var packed: PackedScene = load(model_path)
	if packed == null:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "Attach_" + bone_name
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	var weapon := packed.instantiate() as Node3D
	## The kit's bow is modelled with its string on the side the hand slot treats as the front,
	## so held as it comes it points back at the archer. Half a turn about its grip fixes it.
	if model_path.get_file().begins_with("bow"):
		weapon.rotate_y(PI)
	attachment.add_child(weapon)
	_attachments[bone_name] = weapon


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_meshes(child))
	return out

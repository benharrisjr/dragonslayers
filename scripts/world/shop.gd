class_name Shop
extends StaticBody3D

## The stall in town. Walk up, press interact, and trade bugs for gear.
##
## It is only a place: what it sells and what that costs is in ItemDB, the buying is done by the
## player (PlayerCharacter.buy), and the list is drawn by that player's own ShopPanel.

const MODEL_PATH := "res://art/kenney_fantasy-town-kit_2/Models/GLB format/stall-green.glb"
const MODEL_SCALE := 4.2
const INTERACT_RADIUS := 5.5
const SIGN_COLOR := Color(0.55, 0.95, 0.5)


func setup() -> void:
	add_to_group("shops")
	var packed := load(MODEL_PATH) as PackedScene
	if packed != null:
		var model := packed.instantiate() as Node3D
		model.scale = Vector3.ONE * MODEL_SCALE
		add_child(model)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 3.0, 2.6)
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	add_child(shape)

	var sign := Label3D.new()
	sign.text = "Bug Shop"
	sign.font_size = 96
	sign.pixel_size = 0.012
	sign.outline_size = 24
	sign.modulate = SIGN_COLOR
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position.y = 6.2
	add_child(sign)

	## The same floating marker the chests have, in the shop's own colour.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.35, 0.35)
	var material := StandardMaterial3D.new()
	material.albedo_color = SIGN_COLOR
	material.emission_enabled = true
	material.emission = SIGN_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.position.y = 5.2
	add_child(marker)


## The shop a player standing at `at` could use, or null.
static func in_reach(tree: SceneTree, at: Vector3) -> Shop:
	for node in tree.get_nodes_in_group("shops"):
		var shop := node as Shop
		if shop != null and shop.global_position.distance_to(at) <= INTERACT_RADIUS:
			return shop
	return null

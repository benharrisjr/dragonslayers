class_name ItemDB
extends RefCounted

## The gear a player can hold.
##
## There are no classes: what a player can do is what they are carrying. Everyone starts with a
## sword and a shield and keeps them for good; the rest is found in the large chests, and is
## dropped on death for whoever gets to it first.
##
## Three kinds. The sword and the shield are always on their own buttons. Usable equipment --
## hookshot, lantern, power glove, bug net, fan -- shares the third button, so which one is equipped is a choice made in
## the gear panel. Static equipment -- feather, boots -- simply works while you hold it: no
## feather, no jump; no boots, no dash.

const SWORD := &"sword"
const SHIELD := &"shield"
const HOOKSHOT := &"hookshot"
const FEATHER := &"feather"
const BOOTS := &"boots"
const LANTERN := &"lantern"
const GLOVE := &"glove"
const NET := &"net"
const FAN := &"fan"
## Not gear: a heart container is used up the moment it is taken, and makes the health bar one
## heart longer for good.
const HEART := &"heart"
const MIRROR := &"mirror"

## Display order in the gear panel, and the numbering used when an item id crosses the wire.
## New items go on the end: the numbering is what item pickups send between machines.
const ORDER: Array[StringName] = [SWORD, SHIELD, HOOKSHOT, FEATHER, BOOTS, LANTERN, GLOVE, NET, FAN,
		HEART, MIRROR]
const STARTING: Array[StringName] = [SWORD, SHIELD]
## What the large chests hold, handed out in turn so a map has a few of each.
const CHEST_CYCLE: Array[StringName] = [FEATHER, BOOTS, HOOKSHOT, LANTERN, GLOVE, FAN, HEART, NET]

## Shown in the gear panel, in this order: the things to equip, then the things that just work.
const USABLE: Array[StringName] = [HOOKSHOT, LANTERN, GLOVE, NET, FAN]
const STATIC: Array[StringName] = [BOOTS, FEATHER, MIRROR]

## What the town's shop sells, and what each costs in bugs. The net is free -- it is what the
## bugs are caught with, so charging bugs for it would leave nobody able to shop at all.
const SHOP_STOCK: Array[StringName] = [NET, HEART, MIRROR, GLOVE, FAN, BOOTS, LANTERN, HOOKSHOT]
const _PRICES: Dictionary = {NET: 0, HEART: 3, MIRROR: 3, GLOVE: 4, FAN: 4, BOOTS: 5, LANTERN: 5,
	HOOKSHOT: 6}
## A heart container adds one heart, up to this many.
const MAX_HEARTS := 8

const HOTKEY_COUNT := 3
## What each button is for. The first two never change; the third holds the equipped usable.
const SLOT_SWORD := 0
const SLOT_SHIELD := 1
const SLOT_USABLE := 2

const ASSET_ROOT := "res://art/KayKit_Adventurers_2.0_FREE/Assets/gltf/"

const _INFO: Dictionary = {
	SWORD: {"name": "Sword", "color": Color(0.8, 0.85, 0.95), "passive": false, "keep": true,
		"text": "Swing at whatever is in front of you."},
	SHIELD: {"name": "Shield", "color": Color(0.45, 0.6, 0.95), "passive": false, "keep": true,
		"text": "Hold to block hits from the front."},
	HOOKSHOT: {"name": "Hookshot", "color": Color(0.95, 0.6, 0.25), "passive": false, "keep": false,
		"text": "Pulls you to walls, trees and chests. Pulls enemies to you."},
	FEATHER: {"name": "Feather", "color": Color(0.95, 0.95, 0.85), "passive": true, "keep": false,
		"text": "Lets you jump."},
	BOOTS: {"name": "Boots", "color": Color(0.75, 0.5, 0.3), "passive": true, "keep": false,
		"text": "Lets you dash."},
	LANTERN: {"name": "Lantern", "color": Color(1.0, 0.75, 0.25), "passive": false, "keep": false,
		"text": "Drops fire. Burns enemies, trees, grass and anything wooden."},
	GLOVE: {"name": "Power Glove", "color": Color(0.85, 0.3, 0.25), "passive": false, "keep": false,
		"text": "Lifts a rock in front of you. Press again to throw it."},
	NET: {"name": "Bug Net", "color": Color(0.55, 0.85, 0.5), "passive": false, "keep": false,
		"text": "Swing at bugs to catch them. The shop in town trades for bugs."},
	FAN: {"name": "Fan", "color": Color(0.6, 0.9, 0.95), "passive": false, "keep": false,
		"text": "A gust of wind that shoves back everything in front of you."},
	HEART: {"name": "Heart Container", "color": Color(0.95, 0.25, 0.35), "passive": false,
		"keep": true, "consumable": true,
		"text": "One more heart, for good."},
	MIRROR: {"name": "Mirror", "color": Color(0.7, 0.85, 1.0), "passive": true, "keep": false,
		"text": "Online, anyone else holding a mirror hears your voice however far away."},
}


static func exists(id: StringName) -> bool:
	return _INFO.has(id)


static func display_name(id: StringName) -> String:
	return _INFO[id]["name"] if _INFO.has(id) else ""


static func description(id: StringName) -> String:
	return _INFO[id]["text"] if _INFO.has(id) else ""


static func color(id: StringName) -> Color:
	return _INFO[id]["color"] if _INFO.has(id) else Color.WHITE


## Used up on being taken rather than held: the heart container.
static func is_consumable(id: StringName) -> bool:
	return _INFO.has(id) and _INFO[id].get("consumable", false)


## What the shop asks for an item, in bugs; -1 for something it does not sell.
static func price(id: StringName) -> int:
	return _PRICES.get(id, -1)


## Passive items work just by being held and are never put on a hotkey.
static func is_passive(id: StringName) -> bool:
	return _INFO.has(id) and _INFO[id]["passive"]


## Usable equipment is what the third button fires; one piece is equipped at a time.
static func is_usable(id: StringName) -> bool:
	return USABLE.has(id)


## Sword and shield stay with a player through death; everything else is dropped.
static func is_droppable(id: StringName) -> bool:
	return _INFO.has(id) and not _INFO[id]["keep"]


## The item in a chunk's large chest. The town always has a feather, so the first jump is a
## short walk from where the party starts; elsewhere the three finds simply take turns.
static func chest_item(chunk_index: int, biome_id: StringName) -> StringName:
	if biome_id == &"town":
		return FEATHER
	return CHEST_CYCLE[chunk_index % CHEST_CYCLE.size()]


## A small model of the item, for pickups lying in the world. Sword and shield reuse the models
## the hero carries; the rest are simple shapes, since the kits have no feather, boot or hook.
static func build_model(id: StringName) -> Node3D:
	var root := Node3D.new()
	match id:
		SWORD, SHIELD:
			var path := ASSET_ROOT + ("sword_1handed.gltf" if id == SWORD else "shield_round.gltf")
			var packed := load(path) as PackedScene
			if packed != null:
				root.add_child(packed.instantiate())
		HOOKSHOT:
			var head := CylinderMesh.new()
			head.top_radius = 0.0
			head.bottom_radius = 0.2
			head.height = 0.5
			head.radial_segments = 8
			_add_part(root, head, color(id), Vector3(0, 0.25, 0))
			var grip := CylinderMesh.new()
			grip.top_radius = 0.07
			grip.bottom_radius = 0.07
			grip.height = 0.4
			grip.radial_segments = 6
			_add_part(root, grip, Color(0.35, 0.3, 0.28), Vector3(0, -0.2, 0))
		FEATHER:
			var vane := SphereMesh.new()
			vane.radius = 0.16
			vane.height = 0.75
			vane.radial_segments = 8
			vane.rings = 4
			var part := _add_part(root, vane, color(id), Vector3.ZERO)
			part.scale = Vector3(1.0, 1.0, 0.25)
			part.rotation_degrees.z = 25.0
		BOOTS:
			for side in [-1.0, 1.0]:
				var leg := BoxMesh.new()
				leg.size = Vector3(0.2, 0.34, 0.22)
				_add_part(root, leg, color(id), Vector3(side * 0.16, 0.1, 0))
				var toe := BoxMesh.new()
				toe.size = Vector3(0.2, 0.14, 0.2)
				_add_part(root, toe, color(id).darkened(0.2), Vector3(side * 0.16, 0.0, 0.2))
		LANTERN:
			var frame := BoxMesh.new()
			frame.size = Vector3(0.26, 0.36, 0.26)
			_add_part(root, frame, Color(0.3, 0.27, 0.25), Vector3.ZERO)
			var flame := SphereMesh.new()
			flame.radius = 0.16
			flame.height = 0.32
			flame.radial_segments = 8
			flame.rings = 4
			_add_part(root, flame, color(id), Vector3(0, 0.02, 0)).scale = Vector3.ONE * 1.25
			var handle := TorusMesh.new()
			handle.inner_radius = 0.09
			handle.outer_radius = 0.12
			var loop := _add_part(root, handle, Color(0.3, 0.27, 0.25), Vector3(0, 0.26, 0))
			loop.rotation_degrees.x = 90.0
		GLOVE:
			var palm := BoxMesh.new()
			palm.size = Vector3(0.34, 0.36, 0.2)
			_add_part(root, palm, color(id), Vector3(0, 0.05, 0))
			var cuff := BoxMesh.new()
			cuff.size = Vector3(0.3, 0.16, 0.22)
			_add_part(root, cuff, Color(0.95, 0.85, 0.4), Vector3(0, -0.2, 0))
			var thumb := BoxMesh.new()
			thumb.size = Vector3(0.1, 0.2, 0.14)
			_add_part(root, thumb, color(id), Vector3(0.22, 0.02, 0))
		NET:
			var pole := CylinderMesh.new()
			pole.top_radius = 0.035
			pole.bottom_radius = 0.035
			pole.height = 0.7
			pole.radial_segments = 6
			_add_part(root, pole, Color(0.5, 0.36, 0.22), Vector3(0, -0.15, 0))
			var hoop := TorusMesh.new()
			hoop.inner_radius = 0.17
			hoop.outer_radius = 0.22
			_add_part(root, hoop, color(id), Vector3(0, 0.4, 0)).rotation_degrees.x = 90.0
		FAN:
			for blade in 5:
				var leaf := BoxMesh.new()
				leaf.size = Vector3(0.1, 0.5, 0.03)
				var part := _add_part(root, leaf, color(id), Vector3.ZERO)
				part.rotation_degrees.z = -50.0 + blade * 25.0
				part.position = Vector3(-sin(part.rotation.z), cos(part.rotation.z), 0.0) * 0.22 \
						+ Vector3(0, -0.2, 0)
			var pin := SphereMesh.new()
			pin.radius = 0.07
			pin.height = 0.14
			_add_part(root, pin, Color(0.4, 0.3, 0.25), Vector3(0, -0.2, 0))
		HEART:
			for side in [-1.0, 1.0]:
				var lobe := SphereMesh.new()
				lobe.radius = 0.2
				lobe.height = 0.4
				lobe.radial_segments = 8
				lobe.rings = 4
				_add_part(root, lobe, color(id), Vector3(side * 0.14, 0.12, 0))
			var point := CylinderMesh.new()
			point.top_radius = 0.3
			point.bottom_radius = 0.0
			point.height = 0.36
			point.radial_segments = 4
			_add_part(root, point, color(id), Vector3(0, -0.12, 0)).scale = Vector3(1.0, 1.0, 0.6)
		MIRROR:
			var rim := CylinderMesh.new()
			rim.top_radius = 0.26
			rim.bottom_radius = 0.26
			rim.height = 0.05
			rim.radial_segments = 12
			_add_part(root, rim, Color(0.85, 0.7, 0.3), Vector3(0, 0.15, 0)).rotation_degrees.x = 90.0
			var glass := CylinderMesh.new()
			glass.top_radius = 0.2
			glass.bottom_radius = 0.2
			glass.height = 0.07
			glass.radial_segments = 12
			_add_part(root, glass, color(id), Vector3(0, 0.15, 0)).rotation_degrees.x = 90.0
			var stem := CylinderMesh.new()
			stem.top_radius = 0.04
			stem.bottom_radius = 0.04
			stem.height = 0.3
			stem.radial_segments = 6
			_add_part(root, stem, Color(0.85, 0.7, 0.3), Vector3(0, -0.25, 0))
	return root


static func _add_part(root: Node3D, mesh: Mesh, tint: Color, at: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.5
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	root.add_child(instance)
	return instance

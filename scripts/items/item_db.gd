class_name ItemDB
extends RefCounted

## The gear a player can hold.
##
## Each hero starts with their own weapon -- the Knight with a sword and a shield -- and keeps it
## for good (ArchetypeDB). The rest is found in the large chests, and is dropped on death for
## whoever gets to it first.
##
## Three kinds. The weapon and the shield are always on their own buttons. Usable equipment --
## hookshot, lantern, power glove, bug net, fan -- shares the third button, so which one is equipped is a choice made in
## the gear panel. Static equipment -- feather, boots -- simply works while you hold it: no
## feather, no jump; no boots, no dash.

const SWORD := &"sword"
const SHIELD := &"shield"
## The other heroes' weapons. Each hero starts with their own (ArchetypeDB) and it goes on the
## first button, where the Knight's sword is.
const AXE := &"axe"
const DAGGER := &"dagger"
const STAFF := &"staff"
const BOW := &"bow"
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
const BOOMERANG := &"boomerang"
## Not gear either: each one taken raises the wearer's armour a level, for good (see MAX_ARMOR).
const ARMOR := &"armor"
const RAFT := &"raft"
## Found in the dungeons: bombs (also sold in town) open the cracked wall in the plains, and the
## flippers let you swim the lake and the sea and dive to the lake's bed.
const BOMB := &"bomb"
const FLIPPERS := &"flippers"

## Display order in the gear panel, and the numbering used when an item id crosses the wire.
## New items go on the end: the numbering is what item pickups send between machines.
const ORDER: Array[StringName] = [SWORD, SHIELD, HOOKSHOT, FEATHER, BOOTS, LANTERN, GLOVE, NET, FAN,
		HEART, MIRROR, AXE, DAGGER, STAFF, BOW, BOOMERANG, ARMOR, RAFT, BOMB, FLIPPERS]
## A weapon goes on the first button and fires its hero's attack.
const WEAPONS: Array[StringName] = [SWORD, AXE, DAGGER, STAFF, BOW]
## What the large chests hold, handed out in turn so a map has a few of each.
const CHEST_CYCLE: Array[StringName] = [FEATHER, BOOTS, HOOKSHOT, RAFT, BOOMERANG, ARMOR, LANTERN,
		GLOVE, FAN, HEART, NET]

## Shown in the gear panel, in this order: the things to equip, then the things that just work.
const USABLE: Array[StringName] = [HOOKSHOT, BOOMERANG, LANTERN, GLOVE, NET, FAN, BOMB]
const STATIC: Array[StringName] = [BOOTS, FEATHER, MIRROR, RAFT, FLIPPERS]

## What the town's shop sells, and what each costs in bugs. The net is free -- it is what the
## bugs are caught with, so charging bugs for it would leave nobody able to shop at all.
const SHOP_STOCK: Array[StringName] = [NET, HEART, MIRROR, BOOMERANG, GLOVE, FAN, BOOTS, LANTERN,
		HOOKSHOT, ARMOR, RAFT, BOMB]
const _PRICES: Dictionary = {NET: 0, HEART: 3, MIRROR: 3, BOOMERANG: 4, GLOVE: 4, FAN: 4, BOOTS: 5,
	LANTERN: 5, HOOKSHOT: 6, ARMOR: 8, RAFT: 5, BOMB: 6}
## A heart container adds one heart, up to this many.
const MAX_HEARTS := 8
## Armour levels: 0 takes full damage, 1 half, 2 a quarter. Out of four quarters of a point.
const MAX_ARMOR := 2
const ARMOR_QUARTERS: Array[int] = [4, 2, 1]

const HOTKEY_COUNT := 3
## What each button is for. The first two never change; the third holds the equipped usable.
## The first is the hero's weapon (the sword, for the Knight); the second is the shield, which
## only the Knight has.
const SLOT_SWORD := 0
const SLOT_SHIELD := 1
const SLOT_USABLE := 2

const ASSET_ROOT := "res://art/KayKit_Adventurers_2.0_FREE/Assets/gltf/"

const _INFO: Dictionary = {
	SWORD: {"name": "Sword", "color": Color(0.8, 0.85, 0.95), "passive": false, "keep": true,
		"text": "Swing at whatever is in front of you."},
	SHIELD: {"name": "Shield", "color": Color(0.45, 0.6, 0.95), "passive": false, "keep": true,
		"text": "Hold to block hits from the front."},
	AXE: {"name": "Axe", "color": Color(0.75, 0.75, 0.8), "passive": false, "keep": true,
		"text": "A heavy two-handed chop."},
	DAGGER: {"name": "Dagger", "color": Color(0.85, 0.88, 0.95), "passive": false, "keep": true,
		"text": "A quick stab."},
	STAFF: {"name": "Staff", "color": Color(0.6, 0.55, 1.0), "passive": false, "keep": true,
		"text": "Casts a bolt of magic."},
	BOW: {"name": "Bow", "color": Color(0.75, 0.55, 0.3), "passive": false, "keep": true,
		"text": "Shoots an arrow."},
	HOOKSHOT: {"name": "Hookshot", "color": Color(0.95, 0.6, 0.25), "passive": false, "keep": false,
		"text": "Pulls you to walls, trees and chests. Pulls enemies to you."},
	FEATHER: {"name": "Feather", "color": Color(0.95, 0.95, 0.85), "passive": true, "keep": false,
		"text": "Lets you jump."},
	BOOTS: {"name": "Boots", "color": Color(0.75, 0.5, 0.3), "passive": true, "keep": false,
		"text": "Hold dash to sprint. Steer as you run."},
	BOOMERANG: {"name": "Boomerang", "color": Color(0.82, 0.55, 0.3), "passive": false,
		"keep": false, "text": "Flies out and comes back. Stuns whatever it hits, for one point."},
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
	ARMOR: {"name": "Armor", "color": Color(0.35, 0.5, 0.95), "passive": false, "keep": true,
		"consumable": true,
		"text": "Raises your armour a level, for good: half damage, then a quarter."},
	RAFT: {"name": "Raft", "color": Color(0.62, 0.42, 0.22), "passive": true, "keep": false,
		"text": "Step onto the river and ride it. The current carries you downstream."},
	BOMB: {"name": "Bombs", "color": Color(0.95, 0.5, 0.15), "passive": false, "keep": false,
		"text": "Stand still to set one down; on the move, throw it. It blows up after a moment -- mind your feet."},
	FLIPPERS: {"name": "Flippers", "color": Color(0.25, 0.75, 0.6), "passive": true, "keep": false,
		"text": "Swim in deep still water instead of sinking. Jump to dive."},
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


## A hero's weapon: what the first button attacks with.
static func is_weapon(id: StringName) -> bool:
	return WEAPONS.has(id)


## Usable equipment is what the third button fires; one piece is equipped at a time.
static func is_usable(id: StringName) -> bool:
	return USABLE.has(id)


## Weapons and the shield stay with a player through death; everything else is dropped.
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
		SWORD, SHIELD, AXE, DAGGER, STAFF, BOW:
			var files := {SWORD: "sword_1handed.gltf", SHIELD: "shield_round.gltf",
					AXE: "axe_2handed.gltf", DAGGER: "dagger.gltf", STAFF: "staff.gltf",
					BOW: "bow_withString.gltf"}
			var path: String = ASSET_ROOT + String(files[id])
			var packed := load(path) as PackedScene
			if packed != null:
				root.add_child(packed.instantiate())
		RAFT:
			root.add_child(RiverBuilder.raft_model(0.4))
		ARMOR:
			## A breastplate: a broad plate, narrower at the waist, with shoulder guards.
			var plate := BoxMesh.new()
			plate.size = Vector3(0.5, 0.5, 0.16)
			_add_part(root, plate, color(id), Vector3.ZERO)
			for side in [-1.0, 1.0]:
				var guard := BoxMesh.new()
				guard.size = Vector3(0.2, 0.12, 0.24)
				_add_part(root, guard, Color(0.75, 0.78, 0.85), Vector3(side * 0.3, 0.24, 0.0))
		BOOMERANG:
			## Two flat arms meeting at an angle, the classic bent stick.
			for side in [-1.0, 1.0]:
				var arm := BoxMesh.new()
				arm.size = Vector3(0.11, 0.04, 0.42)
				var part := _add_part(root, arm, color(id), Vector3.ZERO)
				part.rotation.y = side * 0.75
				part.position = Vector3(side * 0.13, 0.0, -0.1)
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
		BOMB:
			root.add_child(bomb_model())
		FLIPPERS:
			## A pair of flippers: a strap at the heel and a wide paddle in front.
			for side in [-1.0, 1.0]:
				var paddle := BoxMesh.new()
				paddle.size = Vector3(0.2, 0.04, 0.46)
				_add_part(root, paddle, color(id), Vector3(side * 0.15, 0.0, 0.1))
				var strap := BoxMesh.new()
				strap.size = Vector3(0.18, 0.1, 0.14)
				_add_part(root, strap, color(id).darkened(0.35), Vector3(side * 0.15, 0.05, -0.12))
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


## A bomb: a round black body, a little cap and a fuse. Used for the pickup and the bomb itself.
static func bomb_model(radius: float = 0.24) -> Node3D:
	var root := Node3D.new()
	var body := SphereMesh.new()
	body.radius = radius
	body.height = radius * 2.0
	body.radial_segments = 12
	body.rings = 6
	var shell := _add_part(root, body, Color(0.12, 0.12, 0.16), Vector3.ZERO)
	shell.name = "Shell"
	(shell.material_override as StandardMaterial3D).emission_energy_multiplier = 0.1
	var cap := CylinderMesh.new()
	cap.top_radius = radius * 0.32
	cap.bottom_radius = radius * 0.38
	cap.height = radius * 0.3
	cap.radial_segments = 8
	_add_part(root, cap, Color(0.55, 0.5, 0.45), Vector3(0, radius * 0.98, 0))
	var fuse := CylinderMesh.new()
	fuse.top_radius = radius * 0.06
	fuse.bottom_radius = radius * 0.06
	fuse.height = radius * 0.5
	fuse.radial_segments = 4
	var wick := _add_part(root, fuse, Color(0.85, 0.75, 0.55), Vector3(radius * 0.1, radius * 1.3, 0))
	wick.rotation_degrees.z = -20.0
	var spark := SphereMesh.new()
	spark.radius = radius * 0.14
	spark.height = radius * 0.28
	var glow := _add_part(root, spark, Color(1.0, 0.6, 0.15), Vector3(radius * 0.2, radius * 1.55, 0))
	glow.name = "Spark"
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

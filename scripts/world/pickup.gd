class_name Pickup
extends Node3D

## A coin, a heart or a piece of gear lying on the ground waiting to be walked into.
##
## Only the host decides a pickup was collected, then tells everyone to remove it. Letting each
## client claim locally would pay a four-player party four times for one coin.

enum Kind { GOLD, HEART, ITEM }

const COLLECT_RADIUS := 1.6
const BOB_HEIGHT := 0.18
const LIFETIME := 90.0

var kind: Kind = Kind.GOLD
## For gold and hearts, how much. For gear, which item: its position in ItemDB.ORDER.
var amount: int = 1
## The player who dropped this by dying, if anyone. They are kept from scooping it straight
## back up when they respawn beside it, so the rest of the party has a real chance at it.
var dropped_by: int = 0
## Seconds a dropped item ignores the player who dropped it: the four they spend dead, and four
## more after they are back on their feet.
const DROPPER_GRACE := 8.0

## Long enough to save the work, short enough that a coin never feels sticky to pick up.
const COLLECT_INTERVAL := 0.1

var _check_timer: float = 0.0
var _base_height: float = 0.0
var _time: float = 0.0
var _collected: bool = false


func setup(pickup_kind: Kind, value: int, position: Vector3) -> void:
	## Grouped so anything that needs to find loose loot -- the playtest, and later a magnet
	## upgrade or an end-of-round sweep -- can do so without walking the scene tree.
	add_to_group("pickups")
	kind = pickup_kind
	amount = value
	## Bobs and spins every drawn frame in _process, so it opts out of physics interpolation.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_position = position
	_base_height = position.y
	_build_visual()


func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	position.y = _base_height + sin(_time * 3.0) * BOB_HEIGHT + BOB_HEIGHT
	rotation.y += delta * 1.8

	## Gear never expires: a feather that vanished after ninety seconds would strand the party.
	if _time > LIFETIME and kind != Kind.ITEM:
		queue_free()
		return
	if not NetworkManager.is_host():
		return
	## Throttled rather than checked every frame. A coin is not going anywhere and neither is a
	## player moving 7 m/s, but a screen full of loot each walking the player list every frame is
	## a cost that shows up as a hitch after a big fight.
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = COLLECT_INTERVAL
	for body in PlayerRegistry.living_bodies():
		if body.global_position.distance_to(global_position) > COLLECT_RADIUS:
			continue
		if kind == Kind.ITEM and not _may_take(body as PlayerCharacter):
			continue
		_collect(body)
		return


func _collect(player: Node) -> void:
	_collected = true
	if NetworkManager.is_networked():
		_net_collected.rpc(player.get_path())
	else:
		_net_collected(player.get_path())


@rpc("authority", "call_local", "reliable")
func _net_collected(player_path: NodePath) -> void:
	var player := get_node_or_null(player_path) as PlayerCharacter
	if player != null:
		match kind:
			Kind.GOLD:
				## Gold is a party pool, so it does not matter who physically ran over the coin.
				player.add_gold(amount)
			Kind.HEART:
				player.heal(amount)
			Kind.ITEM:
				player.add_item(item_id())
	queue_free()


func item_id() -> StringName:
	return ItemDB.ORDER[amount] if kind == Kind.ITEM and amount >= 0 \
			and amount < ItemDB.ORDER.size() else &""


## Gear is one each: a player who already holds this item walks past it and leaves it for
## someone who does not.
func _may_take(player: PlayerCharacter) -> bool:
	if player == null or player.has_item(item_id()):
		return false
	return not (dropped_by != 0 and player.pid == dropped_by and _time < DROPPER_GRACE)


func _build_visual() -> void:
	if kind == Kind.ITEM:
		var model := ItemDB.build_model(item_id())
		model.scale = Vector3.ONE * 1.5
		add_child(model)
		## A ring on the ground under it, so gear reads as gear from across a chunk and is not
		## mistaken for a coin.
		var ring := TorusMesh.new()
		ring.inner_radius = 0.55
		ring.outer_radius = 0.68
		var glow := StandardMaterial3D.new()
		glow.albedo_color = ItemDB.color(item_id())
		glow.emission_enabled = true
		glow.emission = ItemDB.color(item_id())
		glow.emission_energy_multiplier = 1.2
		var halo := MeshInstance3D.new()
		halo.mesh = ring
		halo.material_override = glow
		halo.position.y = -0.35
		add_child(halo)
		return
	var mesh: Mesh
	var color: Color
	if kind == Kind.GOLD:
		var coin := CylinderMesh.new()
		coin.top_radius = 0.3
		coin.bottom_radius = 0.3
		coin.height = 0.08
		coin.radial_segments = 8  ## Faceted on purpose, to sit alongside the low-poly kits.
		mesh = coin
		color = Color(1.0, 0.82, 0.25)
	else:
		var heart := SphereMesh.new()
		heart.radius = 0.28
		heart.height = 0.56
		heart.radial_segments = 8
		heart.rings = 4
		mesh = heart
		color = Color(0.95, 0.25, 0.35)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.9
	mesh.material = material

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.rotation_degrees.x = 90.0 if kind == Kind.GOLD else 0.0
	add_child(instance)

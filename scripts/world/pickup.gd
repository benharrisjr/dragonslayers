class_name Pickup
extends Node3D

## A gem, a heart or a piece of gear lying on the ground waiting to be walked into. Money is gems
## (Gem): a green one is worth 1, red 2, blue 5, purple 10 and a diamond 25.
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
## While a boomerang or hookshot is bringing this back: whose it is, and which of the two
## (&"boomerang" or &"hook"). It rides along on that player's copy of the tool on every peer,
## and is collected the usual way -- the host seeing it come within reach of someone.
var _carrier: PlayerCharacter
var _carrier_tool: StringName = &""
## How close a passing boomerang or hook has to come to snatch it.
const SNATCH_RADIUS := 1.0


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
	if _carrier_tool != &"":
		_follow_carrier()
	else:
		position.y = _base_height + sin(_time * 3.0) * BOB_HEIGHT + BOB_HEIGHT
	rotation.y += delta * (2.6 if kind == Kind.GOLD and amount >= Gem.VALUES[0] else 1.8)

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
				GameSfx.play_at(&"coin", global_position)
			Kind.HEART:
				player.heal(amount)
				GameSfx.play_at(&"heart", global_position)
			Kind.ITEM:
				player.add_item(item_id())
				GameSfx.play_at(&"item", global_position)
	queue_free()


func is_carried() -> bool:
	return _carrier_tool != &""


## Host: a boomerang or hookshot of `player`'s has caught this and is bringing it back.
func start_carry(player: PlayerCharacter, tool: StringName) -> void:
	if not NetworkManager.is_host() or _collected or is_carried() or player == null:
		return
	if NetworkManager.is_networked():
		_net_carry.rpc(player.get_path(), tool)
	else:
		_net_carry(player.get_path(), tool)


@rpc("authority", "call_local", "reliable")
func _net_carry(player_path: NodePath, tool: StringName) -> void:
	var player := get_node_or_null(player_path) as PlayerCharacter
	if player == null:
		return
	_carrier = player
	_carrier_tool = tool
	_follow_carrier()


## Rides on the tool while it is out; once it is back in hand (or gone) the pickup is set down
## just in front of its owner -- where, if they can take it, the host's next check has them
## collect it, and if they cannot (a second feather) it waits there for a friend.
func _follow_carrier() -> void:
	var player := _carrier if is_instance_valid(_carrier) else null
	var at := Vector3.INF
	if player != null:
		match _carrier_tool:
			&"boomerang":
				if player.boomerang != null and is_instance_valid(player.boomerang):
					at = player.boomerang.global_position - Vector3.UP * 0.4
			&"hook":
				if player.hook != null and is_instance_valid(player.hook) \
						and player.hook.state == Hookshot.State.RETURNING:
					at = player.hook.head - Vector3.UP * 0.2
	if at != Vector3.INF:
		global_position = at
		return
	_carrier_tool = &""
	_carrier = null
	if player != null and not player.is_dead:
		var ahead := player.facing() * 0.9
		global_position = Vector3(player.global_position.x + ahead.x, player.global_position.y,
				player.global_position.z + ahead.z)
	_base_height = global_position.y
	## A pickup with somewhere to go should not time out on the way: it gets a fresh lifetime.
	_time = 0.0


## Every loose pickup within SNATCH_RADIUS of `point` not already on its way somewhere.
static func near(tree: SceneTree, point: Vector3, radius: float = SNATCH_RADIUS) -> Array[Pickup]:
	var out: Array[Pickup] = []
	for node in tree.get_nodes_in_group("pickups"):
		var pickup := node as Pickup
		if pickup == null or pickup._collected or pickup.is_carried():
			continue
		if pickup.global_position.distance_to(point) <= radius:
			out.append(pickup)
	return out


func item_id() -> StringName:
	return ItemDB.ORDER[amount] if kind == Kind.ITEM and amount >= 0 \
			and amount < ItemDB.ORDER.size() else &""


## Gear is one each: a player who already holds this item walks past it and leaves it for
## someone who does not.
func _may_take(player: PlayerCharacter) -> bool:
	if player == null or not player.can_take(item_id()):
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
	if kind == Kind.GOLD:
		var gem := Gem.build(amount)
		add_child(gem)
		return
	var heart := SphereMesh.new()
	heart.radius = 0.28
	heart.height = 0.56
	heart.radial_segments = 8
	heart.rings = 4
	var color := Color(0.95, 0.25, 0.35)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.9
	heart.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = heart
	add_child(instance)

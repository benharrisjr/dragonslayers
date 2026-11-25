class_name LootArea
extends Node3D

## A stretch of the world that hands out loot: a chunk of the map, or a dungeon. Gems, hearts and
## gear are spawned here by the host and replicated, unlike the rest of the area: where a coin
## lands depends on when something died, which is not derivable from the seed. Pickups are this
## node's children, named by a running serial so the host can address them on every machine.

var _pickup_serial: int = 0
## Scatters coins round where they drop. Host only, and only for where the coins land, which is
## replicated -- so it needs no seed.
var _loot_rng := RandomNumberGenerator.new()


## The dungeon or the chunk of the map that `at` is in, or null nowhere at all.
static func at_point(tree: SceneTree, at: Vector3) -> LootArea:
	var dungeon := Dungeon.containing(tree, at)
	if dungeon != null:
		return dungeon
	return Chunk.containing(tree, at)


func _on_monster_died(monster: Monster) -> void:
	if not NetworkManager.is_host():
		return
	## Its last footing, not its final resting place: a skeleton shoved off a cliff still owes
	## the party its gold, and coins spawned in mid-air over a pit are coins nobody can collect.
	_spawn_loot(monster.last_grounded_position, monster.data.gold, monster.data.is_rare)


func _on_chest_opened(chest: TreasureChest) -> void:
	if not NetworkManager.is_host():
		return
	_spawn_loot(chest.global_position + Vector3.UP, chest.gold_value, chest.is_large)
	if chest.item_id != &"":
		## Set down in front of the chest rather than on it, clear of the coins.
		drop_item(chest.item_id, chest.global_position + chest.global_basis.z * 2.8 + Vector3.UP * 0.8)
	## A saved world writes the open chest down straight away (after the loot is out, so the
	## gear lying in front of it is saved too).
	var world := GameWorld.of(self)
	if world != null:
		world.save_progress.call_deferred()


func _spawn_loot(at: Vector3, gold: int, generous: bool) -> void:
	for value in Gem.split(gold):
		var offset := Vector3(_loot_rng.randf_range(-1.0, 1.0), 0.0, _loot_rng.randf_range(-1.0, 1.0))
		_net_spawn_pickup(Pickup.Kind.GOLD, value, at + offset)
	if generous:
		_net_spawn_pickup(Pickup.Kind.HEART, Combatant.POINTS_PER_HEART, at + Vector3.RIGHT)


func _net_spawn_pickup(kind: Pickup.Kind, value: int, at: Vector3, from_pid: int = 0) -> void:
	_pickup_serial += 1
	if NetworkManager.is_networked():
		_spawn_pickup.rpc(int(kind), value, at, from_pid, _pickup_serial)
	else:
		_spawn_pickup(int(kind), value, at, from_pid, _pickup_serial)


## `serial` is the host's running count for this area and becomes the pickup's name. The host
## later tells everyone a pickup was collected by addressing that node, so its name has to be
## the same on every machine -- which an automatically generated one is not.
@rpc("authority", "call_local", "reliable")
func _spawn_pickup(kind: int, value: int, at: Vector3, from_pid: int = 0, serial: int = 0) -> void:
	var pickup := Pickup.new()
	if serial > 0:
		pickup.name = "Pickup_%d" % serial
	add_child(pickup)
	pickup.setup(kind as Pickup.Kind, value, at)
	pickup.dropped_by = from_pid


## Host only: puts a piece of gear on the ground here. `from_pid` is the player who dropped it,
## if it was dropped rather than found -- they have to wait a moment before taking it back.
func drop_item(id: StringName, at: Vector3, from_pid: int = 0) -> void:
	var number := ItemDB.ORDER.find(id)
	if number >= 0:
		_net_spawn_pickup(Pickup.Kind.ITEM, number, at, from_pid)


## Host only: what a broken crate held -- now and then a heart, often a gem or a few, sometimes
## nothing at all. Rolled here and sent to everyone as pickups, like a monster's loot.
func spawn_crate_loot(at: Vector3) -> void:
	var roll := _loot_rng.randf()
	if roll < 0.25:
		return
	if roll < 0.45:
		_net_spawn_pickup(Pickup.Kind.HEART, Combatant.POINTS_PER_HEART, at)
		return
	for i in _loot_rng.randi_range(1, 3):
		var pick := _loot_rng.randf()
		var value := 1
		if pick > 0.98:
			value = 25
		elif pick > 0.9:
			value = 10
		elif pick > 0.75:
			value = 5
		elif pick > 0.45:
			value = 2
		var offset := Vector3(_loot_rng.randf_range(-0.8, 0.8), 0.0, _loot_rng.randf_range(-0.8, 0.8))
		_net_spawn_pickup(Pickup.Kind.GOLD, value, at + offset)

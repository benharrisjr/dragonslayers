class_name Playtest
extends Node

## Drives a real match and reports what happened, so the loop can be checked without a human
## on the controls.
##
##   Godot --path . -- --playtest --slots=2 --seed=4242
##
## Unlike scripts/tests.gd, nothing here is mocked: it is the real generated world, the real
## physics, the real monsters and the real damage path. It exists because the things most
## likely to break -- a player falling through terrain, a monster never reaching anybody, gold
## never arriving -- are exactly the things a unit test cannot see.

const SETTLE_TIME := 2.5
const STEP_TIMEOUT := 12.0

var main: Node

var _passed := 0
var _failed := 0
var _elapsed := 0.0
var _started := false


func _process(delta: float) -> void:
	if _started:
		return
	_elapsed += delta
	## Wait for the world to exist and for the party to have fallen onto solid ground.
	if _elapsed < SETTLE_TIME or main.world == null:
		return
	_started = true
	_run()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s%s" % [label, (" -- " + detail) if detail else ""])


func _run() -> void:
	print("\n=== playtest, seed %d ===" % GameState.world_seed)
	var world: GameWorld = main.world

	_check("all 16 chunks built", world.chunks.size() == 16)
	_check("split screen has a pane per local player",
			main.split_screen.panes.size() == PlayerRegistry.local_pids().size(),
			"%d panes, %d locals" % [main.split_screen.panes.size(),
					PlayerRegistry.local_pids().size()])
	_check("the dragon is on the mountain", world.dragon != null)

	var players := PlayerRegistry.living_bodies()
	_check("players spawned", players.size() > 0)
	if players.is_empty():
		_finish()
		return
	var player: PlayerCharacter = players[0]

	await _settle(1.0)
	_check("player landed on ground rather than falling through",
			player.global_position.y > ChunkMesher.height_to_world(0) - 2.0,
			"y = %.2f" % player.global_position.y)
	_check("player is standing on something", player.is_on_floor())

	# --- movement and jumping ---
	## Press the real actions rather than writing velocity directly: the controller rewrites
	## velocity from input every physics frame, so a poked velocity proves nothing about whether
	## the movement code actually works.
	var start := player.global_position
	Input.action_press("p0_right")
	await _settle(0.8)
	Input.action_release("p0_right")
	_check("player moves when the move action is held",
			player.global_position.distance_to(start) > 1.0,
			"moved %.2f m" % player.global_position.distance_to(start))

	await _settle(0.4)
	var ground_y := player.global_position.y
	Input.action_press("p0_jump")
	await _settle(0.1)
	Input.action_release("p0_jump")
	await _settle(0.3)
	_check("player leaves the ground when jumping", player.global_position.y > ground_y + 0.5,
			"%.2f -> %.2f" % [ground_y, player.global_position.y])
	await _settle(1.5)
	_check("player comes back down", player.is_on_floor())

	# --- targeting and combat ---
	var monster := _nearest_monster(player)
	_check("the world contains monsters", monster != null)
	if monster != null:
		## Teleport the pair together rather than waiting for the AI to walk across a chunk: the
		## point of this step is the damage and knockback path, not pathfinding.
		player.global_position = monster.global_position + Vector3(2.0, 0.5, 0.0)
		await _settle(0.4)

		player.targeting.cycle(1)
		_check("target cycling selects a monster", player.targeting.target() != null)

		var monster_start := monster.global_position
		var health_before := monster.health
		player.use_ability(-1)
		await _settle(1.2)
		_check("a basic attack damages the target", monster.health < health_before,
				"%d -> %d" % [health_before, monster.health])
		_check("the hit knocks the monster back",
				monster.global_position.distance_to(monster_start) > 0.3,
				"moved %.2f m" % monster.global_position.distance_to(monster_start))

		## Read the purse before the killing blow: the player is standing well inside pickup
		## range, so the coins are collected during the fight rather than after it.
		var gold_before := GameState.gold
		var swings := 0
		while not monster.is_dead and swings < 30:
			player.use_ability(-1)
			await _settle(0.7)
			swings += 1
		_check("a monster can be killed", monster.is_dead)

		## Stand over where it fell, in case any coin landed outside the fighting radius.
		player.global_position = monster_start + Vector3.UP
		await _settle(1.5)
		_check("killing a monster pays gold", GameState.gold > gold_before,
				"%d -> %d" % [gold_before, GameState.gold])

	# --- magic ---
	var magic_before := player.magic
	player.use_ability(0)
	await _settle(0.3)
	_check("using an ability drains magic", player.magic < magic_before,
			"%.0f -> %.0f" % [magic_before, player.magic])
	await _settle(PlayerCharacter.MAGIC_REGEN_DELAY + 1.5)
	_check("magic refills after a pause", player.magic > 0.0)

	# --- chests ---
	var chest := _nearest_chest(player)
	_check("the world contains chests", chest != null)
	if chest != null:
		player.global_position = chest.global_position + Vector3(1.0, 0.5, 0.0)
		await _settle(0.4)
		chest.try_open(player)
		await _settle(0.6)
		_check("a chest opens", chest.is_open)

	# --- falling off the world ---
	var health_before_fall := player.health
	player.global_position = Vector3(player.global_position.x,
			PlayerCharacter.KILL_HEIGHT - 2.0, player.global_position.z)
	await _settle(0.5)
	_check("falling off the world respawns the player",
			player.global_position.y > PlayerCharacter.KILL_HEIGHT,
			"y = %.2f" % player.global_position.y)
	_check("falling costs health", player.health < health_before_fall,
			"%d -> %d" % [health_before_fall, player.health])

	_finish()


func _finish() -> void:
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _nearest_monster(player: PlayerCharacter) -> Monster:
	var best: Monster = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("monsters"):
		var monster := node as Monster
		if monster == null or monster.is_dead:
			continue
		var distance := monster.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = monster
	return best


func _nearest_chest(player: PlayerCharacter) -> TreasureChest:
	var best: TreasureChest = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("chests"):
		var chest := node as TreasureChest
		if chest == null or chest.is_open:
			continue
		var distance := chest.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = chest
	return best

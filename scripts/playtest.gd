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
	## No feather, no jump: the button is pressed and nothing happens.
	var ground_y := player.global_position.y
	Input.action_press("p0_jump")
	await _settle(0.1)
	Input.action_release("p0_jump")
	await _settle(0.3)
	_check("without the feather the jump button does nothing",
			player.global_position.y < ground_y + 0.2,
			"%.2f -> %.2f" % [ground_y, player.global_position.y])

	## The town's large chest holds a feather, a short walk from the spawn.
	var town_chunk := world.chunk_of_biome(&"town")
	var feather_chest: TreasureChest = town_chunk.chests[0] if town_chunk != null \
			and not town_chunk.chests.is_empty() else null
	_check("the town has a gear chest holding a feather",
			feather_chest != null and feather_chest.item_id == ItemDB.FEATHER)
	if feather_chest != null:
		player.global_position = feather_chest.global_position + Vector3(1.2, 0.5, 0.0)
		player.reset_physics_interpolation()
		await _settle(0.4)
		feather_chest.try_open(player)
		await _settle(0.6)
		_check("the gear chest opens", feather_chest.is_open)
		## Walk onto what it dropped.
		player.global_position = feather_chest.global_position + Vector3(0.0, 0.5, 2.4)
		await _settle(0.6)
		_check("walking over the feather picks it up", player.has_item(ItemDB.FEATHER))
	if not player.has_item(ItemDB.FEATHER):
		player.add_item(ItemDB.FEATHER)

	await _settle(0.6)
	ground_y = player.global_position.y
	Input.action_press("p0_jump")
	await _settle(0.1)
	Input.action_release("p0_jump")
	await _settle(0.3)
	_check("with the feather the player jumps", player.global_position.y > ground_y + 0.5,
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
		## Polled rather than slept on. A shove plays out over a fixed number of physics steps
		## but the check runs on wall-clock time, and a fixed wait that is comfortable at an
		## uncapped headless frame rate is marginal at a vsynced 60.
		var shoved := 0.0
		var travelled := 0.0
		while shoved < 3.0:
			await _settle(0.15)
			shoved += 0.15
			travelled = maxf(travelled, monster.global_position.distance_to(monster_start))
			if monster.health < health_before and travelled > 0.3:
				break
		_check("a basic attack damages the target", monster.health < health_before,
				"%d -> %d" % [health_before, monster.health])
		_check("the hit knocks the monster back", travelled > 0.3,
				"moved %.2f m" % travelled)

		## Read the purse before the killing blow: the player is standing well inside pickup
		## range, so the coins are collected during the fight rather than after it.
		var gold_before := GameState.gold
		var swings := 0
		while not monster.is_dead and swings < 30:
			## Step back into range before each swing. Every hit knocks the target away, so a
			## stationary attacker connects once and then flails at empty air -- which looked
			## like "a monster cannot be killed" on any seed where the first shove went far.
			## Health is topped up for the same reason: this checks that a monster can be killed,
			## and a tester that dies mid-loop stops swinging for reasons of its own.
			player.is_dead = false
			player.health = player.max_health
			player.global_position = monster.global_position + Vector3(2.0, 0.5, 0.0)
			## Targeted explicitly. With nothing selected the swing aims at whatever is roughly
			## in front, and a teleported player keeps whichever way it was already facing -- so
			## on some seeds every one of thirty swings went off into empty air.
			player.targeting.set_target(monster)
			await get_tree().physics_frame
			player.use_ability(-1)
			await _settle(0.7)
			swings += 1
		_check("a monster can be killed", monster.is_dead)

		## Coins drop where the monster died, which after a dozen knockbacks is nowhere near
		## where the fight started. The kill loop also parks the player inside a monster pack
		## for a dozen swings, so top it up first -- a corpse collects nothing, and that would
		## fail the loot check for a reason that has nothing to do with loot.
		player.is_dead = false
		player.health = player.max_health
		var death_spot := monster.last_grounded_position
		var gold_wait := 0.0
		while GameState.gold <= gold_before and gold_wait < 4.0:
			## Home in on the coins themselves rather than the spot the monster fell on.
			## Teleporting onto the corpse drops the player inside whatever scenery it died
			## against, and physics then shoves it clear -- far enough to leave the loot just
			## outside pickup range, which read as "killing a monster pays no gold".
			var coins := get_tree().get_nodes_in_group("pickups")
			if coins.is_empty():
				player.global_position = death_spot + Vector3.UP
			else:
				player.global_position = (coins[0] as Node3D).global_position
			await _settle(0.3)
			gold_wait += 0.3
		_check("killing a monster pays gold", GameState.gold > gold_before,
				"%d -> %d after %.1fs" % [gold_before, GameState.gold, gold_wait])
	# --- every archetype can actually land its basic attack ---
	## Unit tests cover the reach geometry, but only a real shot in a real world proves a
	## projectile survives the flight: arrows and bolts were once destroyed by their own
	## target's collision capsule a frame before the damage test ran, so the Archer and Wizard
	## could not damage anything at all while every unit test stayed green.
	## One victim for all four, healed between attempts. Picking a fresh monster per class made
	## each of them fight different terrain, so a shot blocked by a cliff was indistinguishable
	## from a shot that could not hit at all.
	var dummy := _fresh_monster()
	_check("a monster is available to test every archetype against", dummy != null)
	## Town is the flattest biome and the only one with no monsters of its own, so moving the
	## pair there removes the terrain from the equation entirely rather than hoping the search
	## below finds a gap in a forest.
	var town := (main.world as GameWorld).chunk_of_biome(&"town")
	if town != null and dummy != null:
		player.global_position = town.ground_spawn(GameState.chunk_rng(4)) + Vector3.UP * 0.5
		await _settle(0.8)
	## Every hero fights differently -- sword, axe, dagger, magic bolt, arrow -- so every one is
	## tried. The player is set back to the knight afterwards, which the rest of the run expects.
	for archetype_id in ArchetypeDB.ORDER:
		var victim := dummy
		if victim == null:
			continue
		victim.health = victim.max_health
		victim.is_dead = false
		player.archetype = ArchetypeDB.get_archetype(archetype_id)
		player.magic = player.max_magic
		## Stand where that class is meant to fight from: just inside a melee swing, or well
		## back for a projectile. A fixed distance would only ever test one of the two.
		var attack := player.archetype.basic_attack
		var distance := 8.0 if attack.shape == AbilityData.Shape.PROJECTILE \
				else attack.range * 0.6
		## Put the pair on a line with nothing between them. Terrain blocking a shot is correct
		## behaviour, but it is not what this check is about, and on generated ground a fixed
		## offset lands behind a cliff often enough to make the result meaningless.
		var spot := _clear_line_position(player, distance)
		if spot == Vector3.INF:
			_check("%s has a clear line to test from" % archetype_id, false,
					"no unobstructed ground within %.0f m" % distance)
			continue
		victim.global_position = spot
		victim.velocity = Vector3.ZERO
		## Frozen outright for the duration. Setting it idle is not enough -- its own AI resumes
		## within a fraction of a second, and a dummy that closes in and shoves the tester out of
		## range mid-wind-up makes "can this class land a hit" depend on who swung first.
		victim.set_physics_process(false)
		player.is_dead = false
		player.health = player.max_health
		player.targeting.set_target(victim)
		## Wait out any swing still in progress from the previous case, so a blocked cast is
		## never mistaken for a missed one. stop_action alone is not enough: the animation it
		## returns to still has to be given a moment, and how long that takes depends on the
		## frame rate.
		player.visual.stop_action()
		var settled := 0.0
		while player.visual.is_acting() and settled < 2.0:
			await _settle(0.1)
			settled += 0.1
		await _settle(0.4)
		var before := victim.health
		var cast := player.use_ability(-1)
		_check("%s can start its basic attack" % archetype_id, cast)
		## Poll rather than sleeping a fixed time: an arrow crossing 5 m takes a fraction of the
		## time a two-handed wind-up does.
		var waited := 0.0
		while victim.health >= before and waited < 3.0:
			await _settle(0.2)
			waited += 0.2
		_check("%s lands its basic attack from %.1f m" % [archetype_id, distance],
				victim.health < before, "hp %d after %.1fs" % [victim.health, waited])
		## And the charged attack, at a victim *behind* them: a spin, a flurry and a ring all
		## reach all the way round, so a dummy at their back is the one that proves it.
		var charged := player.archetype.charged_attack
		var behind_distance := 4.0 if charged.shape != AbilityData.Shape.PROJECTILE else 6.0
		victim.health = victim.max_health
		victim.is_dead = false
		victim.global_position = player.global_position - player.facing() * behind_distance
		victim.velocity = Vector3.ZERO
		player.targeting.set_target(null)
		await _settle(0.6)
		var charged_before := victim.health
		_check("%s can let loose its charged attack" % archetype_id, player.use_charged_attack())
		var charge_wait := 0.0
		while victim.health >= charged_before and charge_wait < 3.0:
			await _settle(0.2)
			charge_wait += 0.2
		_check("%s's %s lands behind it" % [archetype_id, charged.display_name],
				victim.health < charged_before,
				"hp %d after %.1fs, %.2f m away" % [victim.health, charge_wait,
				_flat_distance(victim.global_position, player.global_position)])
		victim.set_physics_process(true)
		player.visual.stop_action()
	player.archetype = ArchetypeDB.get_archetype(&"knight")

	await _check_gear(player, dummy)
	await _check_river(player)
	await _check_deep_water(player)
	await _check_dungeons(player)
	await _check_drop_in(player)

	# --- chests ---
	var chest := _nearest_chest(player)
	_check("the world contains chests", chest != null)
	if chest != null:
		player.global_position = chest.global_position + Vector3(1.0, 0.5, 0.0)
		await _settle(0.4)
		chest.try_open(player)
		await _settle(0.6)
		_check("a chest opens", chest.is_open)

	# --- right-button free look ---
	await _check_mouse_look(player)

	# --- only the chunks near the players are drawn ---
	await _settle(0.2)
	var drawn := world.drawn_chunk_count()
	var mountain_chunk := world.chunk_of_biome(&"mountain")
	_check("only the chunks round the players are drawn", drawn < world.chunks.size(),
			"%d of %d" % [drawn, world.chunks.size()])
	_check("the mountain is always drawn", mountain_chunk != null
			and mountain_chunk.get_node("Terrain").visible)

	# --- the dragon fight ---
	await _walk_the_ascent(world, player)
	await _fight_dragon(world, player)

	# --- falling off the world ---
	## Back on its feet first: the dragon fight leaves the tester in whatever state the boss put
	## it in, and a dead player neither falls nor takes fall damage.
	player.is_dead = false
	player.health = player.max_health
	await _settle(0.3)
	## Watch for the damage event rather than comparing health before and after. A respawn can
	## land the player somewhere they immediately fall again, and a second hit plus the revive
	## that may follow makes the final number say nothing about whether the first fall was paid
	## for. Array-wrapped because GDScript lambdas capture locals by value.
	var fall_damage: Array[int] = [0]
	var probe := func(amount: int, _from: Vector3) -> void: fall_damage[0] += amount
	player.damaged.connect(probe)
	## Dropped repeatedly until the fall is registered. One teleport can be undone within the
	## same physics tick by a respawn that has not yet run its damage path, and polling is the
	## honest way to ask "does falling cost health" rather than "did this one frame line up".
	var dropped := 0.0
	while fall_damage[0] < PlayerCharacter.FALL_DAMAGE and dropped < 3.0:
		player.is_dead = false
		player.global_position = Vector3(player.global_position.x,
				PlayerCharacter.KILL_HEIGHT - 2.0, player.global_position.z)
		await _settle(0.3)
		dropped += 0.3
	await _settle(0.4)
	player.damaged.disconnect(probe)
	_check("falling off the world respawns the player",
			player.global_position.y > PlayerCharacter.KILL_HEIGHT,
			"y = %.2f" % player.global_position.y)
	_check("falling costs health", fall_damage[0] >= PlayerCharacter.FALL_DAMAGE,
			"took %d points" % fall_damage[0])

	await _check_saved_world()
	_finish()


## Saving a world and coming back to it: the match is written to a world file, torn down, and
## built again from that file, the way loading it from the lobby does.
func _check_saved_world() -> void:
	var world := main.world as GameWorld
	var save := SaveManager.new_world(GameState.world_seed)
	GameState.world = save
	var pid: int = PlayerRegistry.local_pids()[0]
	var player := PlayerRegistry.body_of(pid) as PlayerCharacter
	player.is_dead = false
	player.add_item(ItemDB.BOOTS)
	player.add_item(ItemDB.HEART)
	var gear_before := player.gear.duplicate()
	var hearts := player.max_health
	var opened := PackedStringArray()
	for node in get_tree().get_nodes_in_group("chests"):
		if (node as TreasureChest).is_open:
			opened.append(String(node.name))
	_check("there is an opened chest to remember", not opened.is_empty())
	GameState.gold = 77
	var revealed := DungeonEntrance.revealed_names(get_tree())
	_check("there are dungeon entrances found to remember", revealed.size() >= 3, str(revealed))
	world.save_progress()
	var on_disk := SaveManager.load_world(save.id)
	_check("the world is written to disk", on_disk != null and on_disk.opened_chests == opened
			and on_disk.gold == 77 and on_disk.characters.has(String(player.archetype.id))
			and on_disk.revealed_entrances == revealed)

	## Load it: a fresh build from the seed, with the save laid over it.
	GameState.gold = 0
	GameState.phase = GameState.Phase.PLAYING
	main._on_match_started(save.world_seed)
	await _settle(1.0)
	var rebuilt := main.world as GameWorld
	var found_open := 0
	for node in get_tree().get_nodes_in_group("chests"):
		if rebuilt.is_ancestor_of(node) and opened.has(String(node.name)) \
				and (node as TreasureChest).is_open:
			found_open += 1
	_check("opened chests are still open after loading", found_open == opened.size(),
			"%d of %d" % [found_open, opened.size()])
	var coins := 0
	for node in get_tree().get_nodes_in_group("pickups"):
		if (node as Pickup).kind == Pickup.Kind.GOLD and not node.is_queued_for_deletion():
			coins += 1
	_check("and nothing spills out of them again", coins == 0, "%d coins lying about" % coins)
	_check("the party's gold comes back", GameState.gold == 77, str(GameState.gold))
	var hero := PlayerRegistry.body_of(pid) as PlayerCharacter
	var same := hero != null and hero.gear.size() == gear_before.size()
	if same:
		for id in gear_before:
			same = same and hero.has_item(id)
	_check("the hero comes back with their gear", same,
			"%s vs %s" % [str(hero.gear) if hero != null else "no hero", str(gear_before)])
	_check("and their heart containers", hero != null and hero.max_health == hearts)
	_check("starting in town", hero != null
			and rebuilt.chunk_containing(hero.global_position) == rebuilt.chunk_of_biome(&"town"))
	_check("and the dragon is back", rebuilt.dragon != null and not rebuilt.dragon.is_dead)
	_check("the dungeon entrances found stay found", DungeonEntrance.revealed_names(get_tree()) == revealed,
			"%s vs %s" % [DungeonEntrance.revealed_names(get_tree()), revealed])
	var desert := DungeonEntrance.for_dungeon(get_tree(), &"desert")
	_check("and the desert's marked rock stays lifted", desert != null and desert.revealed
			and not desert._chunk.can_lift(desert._rock_index))
	SaveManager.delete_world(save.id)
	GameState.world = null


## The boss fight end to end: waking it, being hit by it, hitting it back, the reset when the
## party is wiped off the platform, and the win. Everything here is timing the unit tests cannot
## see -- whether an attack's damage frame actually fires, whether the reset notices an empty
## arena, whether killing it ends the run.
## Boots, hookshot and what death does to gear, in a real world with real physics.
func _check_gear(player: PlayerCharacter, dummy: Monster) -> void:
	player.is_dead = false
	player.health = player.max_health
	player.visual.stop_action()
	player.targeting.set_target(null)
	await _settle(0.8)

	# --- boots ---
	Input.action_press("p0_dash")
	await _settle(0.1)
	Input.action_release("p0_dash")
	_check("without the boots the dash button does nothing",
			Vector2(player.velocity.x, player.velocity.z).length() < 2.0)
	player.add_item(ItemDB.BOOTS)
	await _settle(0.3)
	var dash_from := player.global_position
	Input.action_press("p0_dash")
	await _settle(0.05)
	var early := Vector2(player.velocity.x, player.velocity.z).length()
	await _settle(0.5)
	var held := Vector2(player.velocity.x, player.velocity.z).length()
	_check("with the boots, holding dash winds up to a sprint", player.is_dashing()
			and held > early + 2.0 and held > PlayerCharacter.DASH_SPEED * 0.9,
			"%.1f -> %.1f m/s" % [early, held])
	## Steering: the stick turns it, but not on the spot.
	var heading := Vector2(player.velocity.x, player.velocity.z).normalized()
	## Whichever of stick right and stick up points most across the way it is going (the stick
	## is camera-relative), so the turn asked for is a real one.
	var screen_right := Basis(Vector3.UP, player.camera_yaw) * Vector3.RIGHT
	var across := "p0_right" if absf(Vector2(screen_right.x, screen_right.z).dot(heading)) < 0.7 \
			else "p0_up"
	Input.action_press(across)
	await _settle(0.15)
	var turned := Vector2(player.velocity.x, player.velocity.z).normalized()
	var angle := absf(heading.angle_to(turned))
	_check("a dash steers with the stick, turning wide", angle > 0.15 and angle < 1.2,
			"%.2f rad" % angle)
	Input.action_release(across)
	Input.action_release("p0_dash")
	await _settle(0.1)
	_check("letting go of dash ends it", not player.is_dashing())
	await _settle(0.5)
	var dashed := player.global_position - dash_from
	dashed.y = 0.0
	_check("with the boots the player dashes", dashed.length() > 4.0, "%.1f m" % dashed.length())

	# --- hookshot against something that does not move ---
	player.add_item(ItemDB.HOOKSHOT)
	_check("the hookshot goes on a hotkey when found", player.hotkey_of(ItemDB.HOOKSHOT) >= 0)
	var anchor := _nearest_chest(player)
	if anchor != null:
		var stand := _stand_off(player, anchor.global_position, 8.0)
		_check("there is somewhere to fire the hookshot from", stand != Vector3.INF)
		if stand != Vector3.INF:
			## Skeletons nearby are parked out of the way: the aim would lock on to one, and
			## this is the hook against something that does not move.
			var parked := _park_monsters_near(stand, 16.0)
			player.global_position = stand + Vector3.UP * 0.2
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
			var toward := anchor.global_position - player.global_position
			player.rotation.y = atan2(toward.x, toward.z)
			await _settle(0.8)
			var gap_before := _flat_distance(player.global_position, anchor.global_position)
			_check("the hookshot fires", player.fire_hookshot())
			await _settle(0.15)
			_check("a hook is in flight with a line to the player", player.hook != null)
			await _settle(1.4)
			var gap_after := _flat_distance(player.global_position, anchor.global_position)
			_check("hitting something static pulls the player to it", gap_after < 3.0,
					"%.1f m -> %.1f m" % [gap_before, gap_after])
			_check("the hook comes back in afterwards", player.hook == null)
			_unpark_monsters(parked)

	# --- hookshot against something that does ---
	if dummy != null and not dummy.is_dead:
		await _settle(1.0)
		## On the same level as the player: a monster up on a mesa is behind a cliff face as far
		## as a hook fired from knee height is concerned, and the hook rightly bites the cliff.
		var spot := _clear_line_position(player, 9.0, true)
		if spot != Vector3.INF:
			dummy.global_position = spot
			dummy.velocity = Vector3.ZERO
			dummy.reset_physics_interpolation()
			player.targeting.set_target(dummy)
			await _settle(0.3)
			var player_before := player.global_position
			var monster_gap := _flat_distance(player.global_position, dummy.global_position)
			player.fire_hookshot()
			## Polled: the AI resumes as soon as the pull lets go, and it may walk off again.
			var closest := monster_gap
			var waited := 0.0
			## How far the player moved while the pull was happening. Measured only until the
			## monster arrives: once it is in reach it swings, and being shoved by that swing
			## says nothing about which end of the line did the travelling.
			var drifted := 0.0
			var arrived := false
			while waited < 1.6:
				await _settle(0.1)
				waited += 0.1
				var gap := _flat_distance(player.global_position, dummy.global_position)
				arrived = arrived or gap <= 4.0
				if not arrived:
					drifted = maxf(drifted, _flat_distance(player.global_position, player_before))
				closest = minf(closest, gap)
			_check("hitting a monster pulls it to the player", closest < 4.0,
					"%.1f m -> %.1f m" % [monster_gap, closest])
			## Not "did not move at all": other skeletons live here and one may bump the tester.
			## The point is which end of the line travelled, and the monster covered five metres.
			_check("and the player stays put", drifted < 2.0, "moved %.1f m" % drifted)
		player.targeting.set_target(null)

	# --- lantern ---
	await _settle(0.8)
	player.add_item(ItemDB.LANTERN)
	var tinder := Vector3.INF
	var tinder_chunk: Chunk = null
	## In town, where nothing is trying to kill the tester: a skeleton's swing mid-check would
	## both interrupt the lantern and cost health for reasons that have nothing to do with fire.
	var town_for_fire := (main.world as GameWorld).chunk_of_biome(&"town")
	if town_for_fire != null and not town_for_fire.flammable_props().is_empty():
		tinder = town_for_fire.flammable_props()[0]
		tinder_chunk = town_for_fire
	_check("the world has something flammable in it", tinder_chunk != null)
	if tinder_chunk != null:
		var standing_before := tinder_chunk.flammable_props().size()
		player.global_position = tinder + Vector3(0.0, 0.4, -1.8)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		player.rotation.y = 0.0  ## Facing +Z, towards the prop.
		await _settle(0.6)
		var health_before := player.health
		_check("the lantern drops fire", player.use_lantern())
		await _settle(0.2)
		_check("there is fire on the ground", _fire_patches() > 0)
		await _settle(1.4)
		_check("the fire burns away the scenery standing in it",
				tinder_chunk.flammable_props().size() < standing_before,
				"%d -> %d flammable props" % [standing_before, tinder_chunk.flammable_props().size()])
		_check("and does not burn whoever dropped it", player.health == health_before)

	# --- set alight by a friend's lantern ---
	await _settle(2.6)
	player.visual.stop_action()
	var calm_at := player.global_position
	await _settle(0.5)
	_check("a player left alone stands still",
			_flat_distance(player.global_position, calm_at) < 0.3)
	var alight_health := player.health
	player.set_alight(1.5)
	await _settle(0.1)
	_check("a player can be set alight", player.is_alight())
	var panic_from := player.global_position
	var furthest := 0.0
	var burning := 0.0
	while burning < 1.2:
		await _settle(0.1)
		burning += 0.1
		furthest = maxf(furthest, _flat_distance(player.global_position, panic_from))
	_check("a player on fire runs about with nobody touching the controls", furthest > 1.5,
			"%.1f m" % furthest)
	_check("a player on fire cannot use their gear",
			not player.dash() and not player.use_ability(-1))
	await _settle(0.8)
	_check("the fire goes out", not player.is_alight())
	_check("and cost no health", player.health == alight_health)

	await _check_new_gear(player)
	await _check_fetch(player)

	# --- death ---
	await _settle(0.8)
	player.is_dead = false
	player.health = player.max_health
	var loose_before := _loose_items().size()
	## Everything held but the sword and shield should end up on the ground.
	var droppable := 0
	for id in player.gear:
		if id != ItemDB.SWORD and id != ItemDB.SHIELD:
			droppable += 1
	player.take_damage(player.max_health * 2, player.global_position + Vector3(0, 0, -2), 0.0, 0.0)
	await _settle(0.5)
	_check("the player can be killed", player.is_dead)
	_check("a dead player keeps only the sword and shield",
			player.gear == ([ItemDB.SWORD, ItemDB.SHIELD] as Array[StringName]), str(player.gear))
	var loose := _loose_items()
	_check("and everything else is left on the ground", loose.size() == loose_before + droppable,
			"%d items lying about, %d before, %d held" % [loose.size(), loose_before, droppable])
	## Back on their feet a few seconds later, standing right beside what they dropped.
	await _settle(5.0)
	_check("the player gets back up", not player.is_dead)
	_check("but cannot scoop their own gear straight back up",
			not player.has_item(ItemDB.FEATHER))
	## The rest of the playtest needs to jump.
	for item in [ItemDB.FEATHER, ItemDB.BOOTS, ItemDB.HOOKSHOT, ItemDB.LANTERN]:
		player.add_item(item)
	for pickup in _loose_items():
		pickup.queue_free()


func _loose_items() -> Array[Pickup]:
	var items: Array[Pickup] = []
	for node in get_tree().get_nodes_in_group("pickups"):
		var pickup := node as Pickup
		if pickup != null and pickup.kind == Pickup.Kind.ITEM and not pickup.is_queued_for_deletion():
			items.append(pickup)
	return items


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Somewhere `distance` metres from a target that has ground under it and a clear line to it.
func _stand_off(player: PlayerCharacter, target: Vector3, distance: float) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	for step in 16:
		var angle := TAU * float(step) / 16.0
		var candidate := target + Vector3(cos(angle), 0.0, sin(angle)) * distance
		var drop := PhysicsRayQueryParameters3D.create(
				candidate + Vector3.UP * 4.0, candidate + Vector3.DOWN * 4.0)
		drop.collision_mask = Combatant.LAYER_WORLD
		var ground := space.intersect_ray(drop)
		if ground.is_empty() or absf((ground["position"] as Vector3).y - target.y) > 0.3:
			continue
		var standing: Vector3 = ground["position"]
		## Not inside a tree or a rock: those are on their own layer and a ray that starts
		## inside one does not see it.
		var inside := PhysicsPointQueryParameters3D.new()
		inside.position = standing + Vector3.UP * 0.85
		inside.collision_mask = Combatant.LAYER_SCENERY
		var blocked := false
		for offset: Vector3 in [Vector3.ZERO, Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0),
				Vector3(0, 0, 0.6), Vector3(0, 0, -0.6)]:
			inside.position = standing + Vector3.UP * 0.85 + offset
			if not space.intersect_point(inside, 1).is_empty():
				blocked = true
		if blocked:
			continue
		## The line has to reach the target itself, not a tree on the way.
		var sight := PhysicsRayQueryParameters3D.create(
				standing + Vector3.UP * 0.85, target + Vector3.UP * 0.4)
		sight.collision_mask = Combatant.LAYER_WORLD | Combatant.LAYER_SCENERY
		var seen := space.intersect_ray(sight)
		if not seen.is_empty() and seen["collider"] is TreasureChest:
			return standing
	return Vector3.INF


## The summit used to be reachable only by teleporting. This walks it: up the mountain's ramp
## from the rim to the dragon's platform, holding one direction and never jumping.
## Someone picks up a spare controller mid-match: a player is added on it, next to player 1,
## with a pane of their own and controls that answer to that controller alone.
func _check_drop_in(player: PlayerCharacter) -> void:
	var before := PlayerRegistry.local_pids().size()
	var panes_before: int = main.split_screen.panes.size()
	## A pad id nobody has; the bindings name devices by id, connected or not.
	var pad := 7
	_check("a spare controller is not playing yet",
			not PlayerBindings.in_play(pad, NetworkManager.local_slot_count))
	var pid: int = main.drop_in(pad)
	await _settle(0.5)
	var joined := PlayerRegistry.body_of(pid) as PlayerCharacter if pid >= 0 else null
	_check("pressing Start on it adds a player mid-match", joined != null
			and PlayerRegistry.local_pids().size() == before + 1,
			"%d -> %d players" % [before, PlayerRegistry.local_pids().size()])
	_check("the screen splits again for them", main.split_screen.panes.size() == panes_before + 1,
			"%d -> %d panes" % [panes_before, main.split_screen.panes.size()])
	if joined == null:
		return
	_check("they arrive beside player 1, not back in town",
			_flat_distance(joined.global_position, player.global_position) < 4.0,
			"%.1f m away" % _flat_distance(joined.global_position, player.global_position))
	_check("they are not playing the same hero as anyone already here",
			joined.archetype.id != player.archetype.id)
	var slot := PlayerRegistry.slot_of(pid)
	_check("their controls are that controller's",
			PlayerBindings.devices_of(slot) == [pad] and PlayerBindings.in_play(pad, NetworkManager.local_slot_count))
	_check("player 1's controller is still player 1's",
			not PlayerBindings.devices_of(slot).has(PlayerBindings.devices_of(0)[0]))


func _walk_the_ascent(world: GameWorld, player: PlayerCharacter) -> void:
	var mountain := world.chunk_of_biome(&"mountain")
	if mountain == null:
		return
	var foot := world.ascent_foot()
	player.global_position = foot + Vector3.UP * 1.0
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	## Movement is camera-relative: face the camera north, so "up" is -z and "right" is +x.
	main.split_screen.cameras[0].yaw = 0.0
	await _settle(0.6)
	var start_y := player.global_position.y
	var summit_y := ChunkMesher.height_to_world(WorldGenerator.summit_level())
	_check("the ascent starts below the summit", start_y < summit_y - 5.0,
			"%.1f m against %.1f m" % [start_y, summit_y])

	## The way up zigzags now, so find it over the terrain -- tile to tile, only where a body can
	## walk -- and steer along it with the stick, the way a player would.
	var route := _route_to_summit(mountain, foot)
	_check("there is a walking route up the mountain", not route.is_empty(), "%d tiles" % route.size())
	var walked := 0.0
	var next := 0
	var actions := ["p0_up", "p0_down", "p0_left", "p0_right"]
	while next < route.size() and walked < 90.0:
		## Up: the walk is over once standing on the platform, wherever on it the dragon sits.
		if player.is_on_floor() and player.global_position.y >= summit_y - 0.2:
			break
		var target: Vector3 = route[next]
		## Knocked down a terrace on the way (a monster up there): find the way again from where it
		## landed, as a player would.
		if player.is_on_floor() and target.y - player.global_position.y > 3.0:
			route = _route_to_summit(mountain, player.global_position)
			next = 0
			if route.is_empty():
				break
			continue
		var delta := Vector2(target.x - player.global_position.x, target.z - player.global_position.z)
		if delta.length() < 0.7:
			next += 1
			continue
		var wanted := {"p0_right": delta.x > 0.3, "p0_left": delta.x < -0.3,
				"p0_down": delta.y > 0.3, "p0_up": delta.y < -0.3}
		for action: String in actions:
			if wanted[action]:
				Input.action_press(action)
			else:
				Input.action_release(action)
		await _settle(0.05)
		walked += 0.05
	for action: String in actions:
		Input.action_release(action)
	await _settle(0.4)
	_check("walking the ramps up the terraces reaches the summit without a jump",
			player.global_position.y >= summit_y - 0.2,
			"climbed %.1f m of %.1f in %.1f s (%d of %d steps)" % [
				player.global_position.y - start_y, summit_y - start_y, walked, next, route.size()])
	_check("the top of the road is the dragon's platform", player.is_on_floor()
			and absf(player.global_position.y - summit_y) < 0.5,
			"y = %.2f" % player.global_position.y)


## Tile centres from the tile under `from` to the nearest tile of the summit platform, walking
## only where TerrainData.can_walk allows. Empty if there is no such way.
func _route_to_summit(mountain: Chunk, from: Vector3) -> Array[Vector3]:
	var terrain := mountain.terrain
	var size := terrain.size
	var local := from - mountain.global_position
	var start := Vector2i(int(local.x / ChunkMesher.TILE_SIZE), int(local.z / ChunkMesher.TILE_SIZE))
	var summit := WorldGenerator.summit_level()
	var came := {start: start}
	var queue: Array[Vector2i] = [start]
	var goal := Vector2i(-1, -1)
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		if terrain.level(at.x, at.y) == summit:
			goal = at
			break
		for side in 4:
			var to := at + Vector2i(ChunkMesher.NEIGHBOUR_DX[side], ChunkMesher.NEIGHBOUR_DZ[side])
			if not terrain.in_bounds(to.x, to.y) or came.has(to) or not terrain.can_walk(at.x, at.y, side):
				continue
			came[to] = at
			queue.append(to)
	var route: Array[Vector3] = []
	if goal.x < 0:
		return route
	var step := goal
	while step != start:
		route.push_front(mountain.global_position + mountain._tile_centre(step.x, step.y))
		step = came[step]
	## A couple of tiles on into the platform, so the climb ends standing on it.
	route.append(mountain.global_position + mountain._tile_centre(size / 2, size / 2))
	return route


func _fight_dragon(world: GameWorld, player: PlayerCharacter) -> void:
	var dragon := world.dragon
	if dragon == null:
		_check("the dragon exists to fight", false)
		return

	var centre := dragon.arena_centre
	## Nothing should be standing on the platform to break line of sight or block a knockback.
	var clutter := 0
	var found := ""
	var mountain := world.chunk_of_biome(&"mountain")
	if mountain != null:
		for node in mountain.get_children():
			if node.name != "Props" and node.name != "Monsters" and node.name != "Chests":
				continue
			for item in node.get_children():
				var offset := (item as Node3D).global_position - centre
				offset.y = 0.0
				if offset.length() <= WorldGenerator.arena_radius():
					clutter += 1
					found += " %s at %s" % [item.name, offset]
	_check("the boss arena is clear of scenery and monsters", clutter == 0,
			"%d things on the platform:%s" % [clutter, found])

	## The climb before this can leave the tester on the platform long enough to wake it; the
	## fight is checked from the start, from the foot of the mountain.
	player.global_position = world.ascent_foot() + Vector3.UP * 1.0
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	## Long enough for it to see the platform is empty; then, if it woke, back to sleep.
	await _settle(1.0)
	if dragon.state != Dragon.State.DORMANT:
		dragon._target = null
		dragon._reset_fight()
	await _settle(0.5)
	_check("the dragon starts dormant", dragon.state == Dragon.State.DORMANT)
	_check("the boss health bar is hidden before the fight", not dragon.is_engaged())

	## Between fights it flies. Send it off now, from an empty summit, and watch it go.
	if not dragon.is_flying():
		dragon._net_take_off(7)
	await _settle(4.0)
	## Off the summit it drops towards the terraces, so it is measured against the ground under
	## it -- which is where its shadow is.
	var shadow := dragon.get_node_or_null("FlightShadow") as MeshInstance3D
	var above := dragon.global_position.y - shadow.global_position.y if shadow != null else 0.0
	_check("the dragon takes off and flies", dragon.is_flying() and above > 6.0,
			"%.1f m above the ground" % above)
	_check("and its shadow follows it over the ground", shadow != null and shadow.visible
			and Vector2(shadow.global_position.x - dragon.global_position.x,
					shadow.global_position.z - dragon.global_position.z).length() < 0.5)
	_check("it cannot be hurt on the wing", _shrugs_off_a_hit(dragon))

	## Step onto the platform. Everything about engagement is measured from the arena centre,
	## so this is the moment the fight is supposed to start -- once the dragon is home.
	player.is_dead = false
	player.health = player.max_health
	player.global_position = centre + Vector3(6.0, 2.0, 0.0)
	await _settle(1.0)
	_check("someone on the summit calls it home", dragon.flight_state == Dragon.Flight.HOME
			or not dragon.is_flying())
	var homeward := 0.0
	while dragon.is_flying() and homeward < 90.0:
		player.global_position = centre + Vector3(6.0, 2.0, 0.0)
		await _settle(1.0)
		homeward += 1.0
	_check("and it lands back on its perch", not dragon.is_flying()
			and dragon.global_position.distance_to(dragon.perch) < 1.0,
			"after %.0f s" % homeward)
	player.global_position = centre + Vector3(6.0, 2.0, 0.0)
	await _settle(1.2)
	_check("standing on the platform wakes the dragon",
			dragon.state != Dragon.State.DORMANT, "state %d" % dragon.state)
	_check("the dragon counts the player as present",
			dragon.players_in_arena().size() >= 1)

	## Let it work through its moveset. Four attacks on cooldowns of 3.4-8.5 s need a while to
	## all come round, and the point is to see damage actually land.
	## Watch what the dragon does rather than what the player is left with. The tester has to be
	## revived and put back on the platform to keep the fight observable, and that healing would
	## erase the evidence if damage were measured by comparing health at the end.
	## A one-element array rather than a bool, because GDScript lambdas capture locals by value:
	## assigning to a captured bool updates the closure's own copy and the outer variable never
	## changes, which reads exactly like "the dragon never hit anybody".
	var hits: Array[int] = [0]
	var was_shoved := false
	player.damaged.connect(func(_amount: int, _from: Vector3) -> void: hits[0] += 1)
	var attacked := false
	var fired := false
	var watched := 0.0
	while watched < 26.0:
		await _settle(0.25)
		watched += 0.25
		player.magic = player.max_magic
		if dragon.state == Dragon.State.ATTACKING:
			attacked = true
		if player.knockback_time > 0.0:
			was_shoved = true
		if _fire_patches() > 0:
			fired = true
		## Stand in one band, then the other, rather than circling. Each attack owns a different
		## band -- the breath is not even considered inside 7 m -- but a tester that keeps moving
		## can dodge everything by accident, and then "the dragon never hit anybody" says
		## nothing about whether its attacks work.
		var far_phase := fmod(watched, 12.0) >= 6.0
		var stand: float = 16.0 if far_phase else 5.0
		if player.health <= Combatant.POINTS_PER_HEART or _off_platform(player, dragon):
			player.is_dead = false
			player.health = player.max_health
		player.global_position = centre + Vector3(stand, 1.5, 0.0)

	_check("the dragon attacks", attacked)
	_check("the dragon damages the player", hits[0] > 0, "%d hits taken" % hits[0])
	_check("the dragon knocks the player around", was_shoved)
	_check("the breath leaves fire on the ground", fired,
			"no fire patch seen in %.0f s" % watched)

	## Hitting it back. Melee reach is measured to its surface, so just inside claw range.
	player.is_dead = false
	player.health = player.max_health
	player.archetype = ArchetypeDB.get_archetype(&"knight")
	var boss_before := dragon.health
	var swings := 0
	while dragon.health >= boss_before and swings < 14:
		player.global_position = dragon.global_position + Vector3(3.6, 1.0, 0.0)
		## Selected explicitly so the swing aims at the dragon rather than at whatever direction
		## the previous step left the player facing.
		player.targeting.set_target(dragon)
		await get_tree().physics_frame
		player.visual.stop_action()
		player.use_ability(-1)
		await _settle(0.6)
		swings += 1
	_check("the dragon can be damaged", dragon.health < boss_before,
			"%d -> %d after %d swings" % [boss_before, dragon.health, swings])

	## Enrage. Dropped straight to the threshold rather than fought down to it, since the
	## transition is what is being checked and not the hour it would take to get there.
	dragon.health = int(dragon.max_health * Dragon.ENRAGE_AT) - 1
	await _settle(0.6)
	_check("the dragon enrages at half health", dragon.enraged)

	## The reset. Everyone off the platform for longer than the grace period, and the fight
	## should go back to the start with its health restored -- this is what makes falling down
	## the mountain a real setback.
	## Held away across the map for the whole grace period, not merely placed there once.
	## Falling out of the world respawns a player on the last ground they stood on -- which,
	## having just been fighting, is the platform -- so a single teleport can bounce straight
	## back and the arena never reads as empty.
	var cleared := 0.0
	while cleared < Dragon.RESET_DELAY + 3.0:
		for pid in PlayerRegistry.all_pids():
			var body := PlayerRegistry.body_of(pid) as PlayerCharacter
			if body != null:
				body.is_dead = false
				body.health = body.max_health
				body.global_position = centre + Vector3(70.0, 2.0, 70.0)
		await _settle(0.2)
		cleared += 0.2
	_check("an empty platform resets the fight", dragon.state == Dragon.State.DORMANT,
			"state %d" % dragon.state)
	_check("the reset restores the dragon's health", dragon.health == dragon.max_health,
			"%d/%d" % [dragon.health, dragon.max_health])
	_check("the reset calms it back down", not dragon.enraged)

	## The win.
	player.is_dead = false
	player.health = player.max_health
	player.global_position = centre + Vector3(6.0, 2.0, 0.0)
	await _settle(1.0)
	dragon.health = 2
	dragon.take_damage(99, player.global_position, 0.0, 0.0)
	await _settle(1.0)
	_check("the dragon can be killed", dragon.is_dead)
	_check("killing the dragon wins the run",
			GameState.phase == GameState.Phase.VICTORY, "phase %d" % GameState.phase)


## Right-button drag routed through the real input pipeline, because the interesting part is
## not the maths -- unit tests cover that -- but the routing: finding which pane the drag
## started in, holding it there, and giving the pointer back afterwards.
func _check_mouse_look(player: PlayerCharacter) -> void:
	var screen: SplitScreen = main.split_screen
	if screen == null or screen.cameras.is_empty():
		_check("there is a camera to look with", false)
		return
	var rig: PlayerCamera = screen.cameras[0]
	var yaw_before := rig.yaw
	var pitch_before := rig.pitch_offset
	## Started through the same call _gui_input makes. Which pane a click lands in is Godot's
	## own hit-testing and is not worth simulating; everything after that point is this game's
	## code and is what these checks are for.
	screen.begin_look(0)
	_check("starting a drag hands the pointer to that pane", screen.is_looking())
	## Pointer capture needs a real window, so it is only asserted when there is one -- headless
	## has no pointer to capture and would fail this for reasons that say nothing about the game.
	if not _headless():
		_check("starting a drag captures the pointer",
				Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)

	_parse_motion(Vector2(120.0, 0.0))
	await get_tree().process_frame
	_check("dragging turns the camera", not is_equal_approx(rig.yaw, yaw_before),
			"%.3f -> %.3f" % [yaw_before, rig.yaw])

	_parse_motion(Vector2(0.0, 80.0))
	await get_tree().process_frame
	_check("dragging tilts the camera", rig.pitch_offset > pitch_before)

	_parse_button(MOUSE_BUTTON_RIGHT, false)
	await get_tree().process_frame
	_check("releasing ends the drag", not screen.is_looking())
	if not _headless():
		_check("releasing gives the pointer back",
				Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)

	## After release the camera must stop following, or it would spin every time the player
	## moves the cursor to click something.
	var yaw_after_release := rig.yaw
	_parse_motion(Vector2(200.0, 0.0))
	await get_tree().process_frame
	_check("the camera stops following once released",
			is_equal_approx(rig.yaw, yaw_after_release))

	## Movement stays camera-relative after turning, which is the whole reason the player reads
	## its basis from its own pane rather than from the world.
	await get_tree().physics_frame
	_check("the player follows the new camera angle",
			is_equal_approx(player.camera_yaw, rig.yaw),
			"player %.3f, camera %.3f" % [player.camera_yaw, rig.yaw])


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _parse_button(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


## Only `relative` matters to the camera, which is also why the drag can be verified without
## simulating where the pointer is.
func _parse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	Input.parse_input_event(event)


func _fire_patches() -> int:
	var count := 0
	for node in GameWorld.effects_root(get_tree()).get_children():
		if node is FirePatch:
			count += 1
	return count


func _off_platform(player: PlayerCharacter, dragon: Dragon) -> bool:
	var offset := player.global_position - dragon.arena_centre
	offset.y = 0.0
	return offset.length() > dragon.arena_radius \
			or player.global_position.y < dragon.arena_centre.y - 5.0


## Power glove, the shop, the bug net and the fan, played through the real controls where there
## is a control to press.
## The boomerang and the hookshot both bring back loot lying out of reach.
func _check_fetch(player: PlayerCharacter) -> void:
	var town := (main.world as GameWorld).chunk_of_biome(&"town")
	if town == null:
		return
	player.add_item(ItemDB.BOOMERANG)
	player.add_item(ItemDB.HOOKSHOT)
	for tool in ["boomerang", "hookshot"]:
		await _settle(0.8)
		player.visual.stop_action()
		player.targeting.set_target(null)
		var spot := _clear_line_position(player, 7.0, true)
		if spot == Vector3.INF:
			_check("there is clear ground to throw the %s over" % tool, false)
			continue
		var gold_before := player.gold_collected
		town._net_spawn_pickup(Pickup.Kind.GOLD, 5, spot + Vector3.UP * 0.3)
		var toward := spot - player.global_position
		player.rotation.y = atan2(toward.x, toward.z)
		player.velocity = Vector3.ZERO
		await _settle(0.2)
		var thrown := player.throw_boomerang() if tool == "boomerang" else player.fire_hookshot()
		_check("the %s goes out after the coin" % tool, thrown)
		var waited := 0.0
		while waited < 3.0 and player.gold_collected == gold_before:
			await _settle(0.1)
			waited += 0.1
		_check("the %s brings the coin back to the player" % tool,
				player.gold_collected > gold_before, "after %.1f s" % waited)


func _check_new_gear(player: PlayerCharacter) -> void:
	var world := main.world as GameWorld
	await _settle(0.6)
	player.visual.stop_action()
	player.targeting.set_target(null)

	# --- shop ---
	var town := world.chunk_of_biome(&"town")
	_check("the town has a shop", town != null and town.shop != null)
	if town != null and town.shop != null:
		player.global_position = town.shop.global_position + Vector3(0.0, 0.4, 3.6)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		await _settle(0.5)
		Input.action_press("p0_interact")
		await _settle(0.1)
		Input.action_release("p0_interact")
		await _settle(0.2)
		_check("interact at the stall opens the shop", player.shop_open)
		var stood := player.global_position
		Input.action_press("p0_up")
		await _settle(0.3)
		Input.action_release("p0_up")
		_check("the shopper stays put while it is open",
				_flat_distance(player.global_position, stood) < 0.3)
		## The net is first on the list and free.
		## A real key event rather than a forced action: the panel reads its buttons once per
		## drawn frame, and only an event that came through the input queue is seen there.
		_parse_key(KEY_SPACE, true)
		await _settle(0.1)
		_parse_key(KEY_SPACE, false)
		await _settle(0.2)
		_check("the buy button buys the free net", player.has_item(ItemDB.NET))
		_check("and buying is not jumping", player.is_on_floor())
		Input.action_press("p0_interact")
		await _settle(0.1)
		Input.action_release("p0_interact")
		await _settle(0.2)
		_check("interact again leaves the shop", not player.shop_open)

	# --- bug net ---
	_check("the town has bugs", town != null and town.bugs != null and town.bugs.count() > 0)
	if town != null and town.bugs != null and town.bugs.count() > 0:
		player.equip(ItemDB.NET)
		var before := player.bugs
		for _try in 6:
			if player.bugs > before:
				break
			## Stand under the bug, a step back, facing it; it will have moved on a little by
			## the time the net comes round, which is what the net's reach is for.
			var bug := town.bugs.bug_position(0)
			player.global_position = Vector3(bug.x, player.global_position.y + 0.2, bug.z - 1.0)
			player.rotation.y = 0.0
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
			await _settle(0.15)
			Input.action_press("p0_item_3")
			await _settle(0.1)
			Input.action_release("p0_item_3")
			await _settle(0.6)
		_check("the usable button swings the net and catches a bug", player.bugs > before,
				"%d bugs" % player.bugs)

	# --- power glove ---
	var rock := Vector3.INF
	for chunk in world.chunks:
		for at in chunk.liftable_props():
			if at.distance_to(player.global_position) < rock.distance_to(player.global_position):
				rock = at
	_check("the world has a rock to lift", rock != Vector3.INF)
	if rock != Vector3.INF:
		player.add_item(ItemDB.GLOVE)
		player.equip(ItemDB.GLOVE)
		var rock_chunk := Chunk.containing(get_tree(), rock)
		var rocks_before := rock_chunk.liftable_props().size()
		var beside := Vector3.ZERO
		## Whichever side of it is open ground at its own height.
		for side in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]:
			beside = side
			var spot: Vector3 = rock + side * 3.2
			var probe := PhysicsRayQueryParameters3D.create(
					spot + Vector3.UP * 3.0, spot + Vector3.DOWN * 3.0)
			probe.collision_mask = Combatant.LAYER_WORLD | Combatant.LAYER_SCENERY
			var ground := player.get_world_3d().direct_space_state.intersect_ray(probe)
			if not ground.is_empty() and absf((ground["position"] as Vector3).y - rock.y) < 0.4:
				break
		player.global_position = rock + beside * 3.2 + Vector3.UP * 0.4
		player.rotation.y = atan2(-beside.x, -beside.z)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		await _settle(0.5)
		Input.action_press("p0_item_3")
		await _settle(0.1)
		Input.action_release("p0_item_3")
		await _settle(0.2)
		_check("the usable button lifts the rock in front", player.carried != null)
		_check("and it is gone from the ground",
				rock_chunk.liftable_props().size() == rocks_before - 1)
		Input.action_press("p0_dash")
		await _settle(0.1)
		Input.action_release("p0_dash")
		_check("nobody dashes with a rock overhead", not player.is_dashing())
		await _settle(0.8)
		Input.action_press("p0_item_3")
		await _settle(0.1)
		Input.action_release("p0_item_3")
		await _settle(0.15)
		_check("pressing it again throws the rock", player.carried == null
				and _count_of("ThrownRock") > 0)
		var waited := 0.0
		var broke := false
		while waited < 3.0 and not broke:
			await _settle(0.1)
			waited += 0.1
			broke = _count_of("RockShards") > 0
		_check("and it shatters where it lands", broke and _count_of("ThrownRock") == 0)

	# --- crates: lifted with the interact button, no glove, and thrown open ---
	var crate_chunk: Chunk = null
	var crate_index := -1
	for chunk in world.chunks:
		for index in chunk._props.size():
			if not chunk.is_crate(index) or not chunk.can_lift(index):
				continue
			var at := (chunk._props[index]["node"] as Node3D).global_position
			if crate_chunk == null or at.distance_to(player.global_position) \
					< (crate_chunk._props[crate_index]["node"] as Node3D).global_position.distance_to(player.global_position):
				crate_chunk = chunk
				crate_index = index
	_check("the world has a crate to lift", crate_chunk != null)
	if crate_chunk != null:
		var crate := (crate_chunk._props[crate_index]["node"] as Node3D).global_position
		var parked := _park_monsters_near(crate, 16.0)
		player.remove_item(ItemDB.GLOVE)
		player.global_position = crate + Vector3(0.0, 0.4, 1.3)
		player.rotation.y = atan2(0.0, -1.0)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		await _settle(0.8)
		player.visual.stop_action()
		player.lift_crate()
		await _settle(0.3)
		_check("a crate is lifted without the glove", player.carried != null
				and player.carried.has_meta("crate"))
		await _settle(0.8)
		player.throw_rock()
		var waited := 0.0
		while waited < 3.0 and _count_of("ThrownRock") > 0:
			await _settle(0.1)
			waited += 0.1
		_check("and thrown, it breaks", player.carried == null and _count_of("RockShards") > 0)
		_unpark_monsters(parked)

	# --- fan ---
	## Nothing nearby to knock the hero about while they wave it.
	var fan_parked := _park_monsters_near(player.global_position, 16.0)
	await _settle(0.6)
	player.visual.stop_action()
	player.add_item(ItemDB.FAN)
	player.equip(ItemDB.FAN)
	Input.action_press("p0_item_3")
	await _settle(0.1)
	Input.action_release("p0_item_3")
	_check("the usable button waves the fan", _count_of("Gust") > 0
			and not player.item_ready(ItemDB.FAN))
	_unpark_monsters(fan_parked)
	## Back to town for what follows.
	if town != null:
		player.global_position = town.ground_spawn(GameState.chunk_rng(31))
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
	await _settle(0.8)


func _parse_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _count_of(kind: String) -> int:
	var count := 0
	for node in main.get_children():
		if (kind == "ThrownRock" and node is ThrownRock) or (kind == "RockShards" and node is RockShards) \
				or (kind == "Gust" and node is Gust):
			count += 1
	return count


func _finish() -> void:
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## A spot `distance` away that the player can actually shoot: on real ground, with nothing
## between the two chests. Terrain blocking a shot is correct behaviour -- a bolt aimed downhill
## at something below a lip should hit the lip -- but it is not what this check is measuring, so
## the search drops each candidate onto the ground first and only then tests the line to where
## the target will really be standing.
func _clear_line_position(player: PlayerCharacter, distance: float,
		level_only: bool = false) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var from := player.hit_centre()
	for step in 16:
		var angle := TAU * float(step) / 16.0
		var candidate := player.global_position \
				+ Vector3(cos(angle), 0.0, sin(angle)) * distance

		var drop := PhysicsRayQueryParameters3D.create(
				candidate + Vector3.UP * 8.0, candidate + Vector3.DOWN * 12.0)
		drop.exclude = [player.get_rid()]
		var ground := space.intersect_ray(drop)
		if ground.is_empty():
			continue
		var standing: Vector3 = ground["position"]
		## Not inside a tree or a rock: those are on their own layer and a ray that starts
		## inside one does not see it.
		var inside := PhysicsPointQueryParameters3D.new()
		inside.position = standing + Vector3.UP * 0.85
		inside.collision_mask = Combatant.LAYER_SCENERY
		var blocked := false
		for offset: Vector3 in [Vector3.ZERO, Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0),
				Vector3(0, 0, 0.6), Vector3(0, 0, -0.6)]:
			inside.position = standing + Vector3.UP * 0.85 + offset
			if not space.intersect_point(inside, 1).is_empty():
				blocked = true
		if blocked:
			continue
		if level_only and absf(standing.y - player.global_position.y) > 0.3:
			continue

		var sight := PhysicsRayQueryParameters3D.create(from, standing + Vector3.UP * 0.85)
		sight.exclude = [player.get_rid()]
		if space.intersect_ray(sight).is_empty():
			return standing
	return Vector3.INF


## Moves every live monster within `radius` of `at` far away and stops it, returning what is
## needed to put each back with _unpark_monsters.
func _park_monsters_near(at: Vector3, radius: float) -> Array:
	var parked: Array = []
	for node in get_tree().get_nodes_in_group("monsters"):
		var monster := node as Monster
		if monster == null or monster.is_dead or _flat_distance(monster.global_position, at) > radius:
			continue
		parked.append([monster, monster.global_position])
		monster.set_physics_process(false)
		monster.global_position = at + Vector3(0.0, 400.0, 0.0)
	return parked


func _unpark_monsters(parked: Array) -> void:
	for entry: Array in parked:
		var monster := entry[0] as Monster
		if is_instance_valid(monster):
			monster.global_position = entry[1]
			monster.reset_physics_interpolation()
			monster.set_physics_process(true)


## An undamaged monster, so a class that misses cannot be credited with an earlier class's hit.
func _fresh_monster() -> Monster:
	for node in get_tree().get_nodes_in_group("monsters"):
		var monster := node as Monster
		if monster != null and not monster.is_dead and monster.health >= monster.max_health:
			return monster
	return null


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


func _shrugs_off_a_hit(dragon: Dragon) -> bool:
	var before := dragon.health
	dragon.take_damage(1, dragon.global_position + Vector3.FORWARD, 0.0, 0.0)
	return dragon.health == before


## The lake's deep middle and the sea past its shallows: walking off the drop is a splash, a
## little damage, and being put back on the shore just short of where you went in -- not back
## where you started walking.
func _check_deep_water(player: PlayerCharacter) -> void:
	var world := main.world as GameWorld
	main.split_screen.cameras[0].yaw = 0.0
	## The checks after this one expect the hero where the river check left them.
	var home := player.global_position
	var home_safe := player._safe_position
	for biome: StringName in [&"beach", &"lake"]:
		var chunk := world.chunk_of_biome(biome)
		if chunk == null:
			continue
		var run := _walk_into_deep(chunk)
		_check("the %s has deep water to walk into from the shallows" % biome, not run.is_empty())
		if run.is_empty():
			continue
		player.is_dead = false
		player.health = player.max_health
		player.respawn_at(run["start"])
		await _settle(0.8)
		var before := player.health
		var went_in := [false]
		var on_respawn := func() -> void: went_in[0] = true
		player.respawned.connect(on_respawn)
		var action: String = run["action"]
		var walked := 0.0
		Input.action_press(action)
		while not went_in[0] and walked < 8.0:
			await _settle(0.05)
			walked += 0.05
		Input.action_release(action)
		player.respawned.disconnect(on_respawn)
		var back := _flat_distance(player.global_position, run["last_safe"])
		_check("walking off the %s's shallows goes into deep water" % biome, went_in[0],
				"walked %.1f s" % walked)
		_check("and puts you back on the shore close to where you went in, a little hurt",
				went_in[0] and back < 3.0 and player.health < before
				and _flat_distance(player.global_position, run["start"]) > back + 2.0,
				"%.1f m from the last safe tile, %.1f m from the start, hp %d -> %d" % [back,
					_flat_distance(player.global_position, run["start"]), before, player.health])
		await _settle(0.5)
	player.health = player.max_health
	player.respawn_at(home - Vector3.UP * 1.5)
	player._safe_position = home_safe
	await _settle(0.5)


## The dungeons in a real match: every way in opened the way it is meant to be -- the desert's
## rock lifted with the glove, the fields' tree struck with the sword, the plains' wall blown open
## with a bomb, the lake's portal reached by swimming and diving with flippers -- and gone
## through; then, in two of them, the guardian beaten, the big chest opened and its reward taken,
## and back out beside the door.
func _check_dungeons(player: PlayerCharacter) -> void:
	var world := main.world as GameWorld
	_check("all eight dungeons are built beside the map", world.dungeons.size() == Dungeon.IDS.size())
	main.split_screen.cameras[0].yaw = 0.0
	var home := player.global_position
	player.is_dead = false
	player.health = player.max_health

	## The desert: lift the marked rock and the stairwell opens.
	var desert := DungeonEntrance.for_dungeon(get_tree(), &"desert")
	if desert != null:
		var rock: Vector3 = (desert._chunk._props[desert._rock_index]["node"] as Node3D).global_position
		var parked := _park_monsters_near(rock, 18.0)
		var stand := rock + desert.global_basis.z * 2.6
		_place(player, stand, rock)
		await _settle(0.6)
		player.add_item(ItemDB.GLOVE)
		player.equip(ItemDB.GLOVE)
		await _press("p0_item_3")
		_check("lifting the desert's marked rock opens a stairwell", desert.revealed and player.carried != null,
				"%.1f m from the rock" % _flat_distance(player.global_position, rock))
		await _press("p0_item_3")
		await _settle(1.0)
		_unpark_monsters(parked)
		await _through(player, desert, true)

	## The fields: a swing at the great tree.
	var fields := DungeonEntrance.for_dungeon(get_tree(), &"fields")
	if fields != null:
		var parked := _park_monsters_near(fields.global_position, 18.0)
		_place(player, fields.global_position + fields.global_basis.z * 2.6, fields.global_position)
		await _settle(0.6)
		_check("the great tree hides its door", not fields.revealed)
		await _press("p0_item_1")
		await _settle(0.8)
		_check("a swing at the great tree opens the door in its trunk", fields.revealed)
		_unpark_monsters(parked)
		await _through(player, fields, false)

	## The plains: a bomb set down by the cracked wall, standing still; and one thrown on the run.
	var plains := DungeonEntrance.for_dungeon(get_tree(), &"plains")
	if plains != null:
		var wall := plains.to_global(Vector3(0, 0, DungeonEntrance.WALL_FACE))
		var parked := _park_monsters_near(wall, 18.0)
		player.add_item(ItemDB.BOMB)
		player.equip(ItemDB.BOMB)
		_place(player, plains.to_global(Vector3(0, 0, DungeonEntrance.WALL_FACE + 1.6)), wall)
		await _settle(0.6)
		var before := player.health
		await _press("p0_item_3")
		var bomb := player.bomb
		_check("standing still, a bomb is set down at your feet", bomb != null
				and bomb.velocity == Vector3.ZERO
				and _flat_distance(bomb.global_position, player.global_position) < 1.5)
		await _settle(0.4)
		_check("the wall holds until the bomb goes off", not plains.revealed)
		await _settle(Bomb.FUSE)
		_check("the bomb blows open the cracked wall", plains.revealed)
		_check("and catches whoever set it down", player.health < before, "%d -> %d" % [before, player.health])
		## On the move, it flies.
		player.health = player.max_health
		await _settle(0.6)
		Input.action_press("p0_down")
		await _settle(0.35)
		await _press("p0_item_3")
		Input.action_release("p0_down")
		var thrown := player.bomb
		var from := player.global_position
		await _settle(0.9)
		## Well past the 1.5 m a set-down bomb lands within. Not much further: on some seeds the
		## throw lands on top of a cliff just ahead, which cuts its flight short.
		_check("on the move, a bomb is thrown", thrown != null and is_instance_valid(thrown)
				and _flat_distance(thrown.global_position, from) > 2.5,
				"%.1f m" % (_flat_distance(thrown.global_position, from) if is_instance_valid(thrown) else -1.0))
		await _settle(Bomb.FUSE)
		_unpark_monsters(parked)
		player.health = player.max_health
		await _through(player, plains, false)

	## The lake: swim out over the portal and dive to it.
	var lake := DungeonEntrance.for_dungeon(get_tree(), &"lake")
	if lake != null:
		player.add_item(ItemDB.FLIPPERS)
		var surface := lake._chunk.terrain.still_surface
		var above := lake.global_position
		above.y = surface - 0.2
		player.global_position = above
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		await _settle(0.8)
		_check("with flippers, deep water is for swimming", player.is_swimming()
				and absf(player.global_position.y - (surface - PlayerCharacter.SWIM_DEPTH)) < 0.3,
				"y %.2f, surface %.2f" % [player.global_position.y, surface])
		var went := [false]
		var on_respawn := func() -> void: went[0] = true
		player.respawned.connect(on_respawn)
		await _press("p0_jump")
		var waited := 0.0
		while not went[0] and waited < 2.5:
			await _settle(0.05)
			waited += 0.05
		player.respawned.disconnect(on_respawn)
		var inside := Dungeon.containing(get_tree(), player.global_position)
		_check("diving to the lake's portal takes you into its dungeon",
				inside != null and inside.dungeon_id == &"lake", "after %.1f s" % waited)
		if inside != null:
			await _clear(player, inside, lake)

	## The ones that stand open.
	for id: StringName in [&"well", &"forest", &"temple_low", &"temple_high"]:
		var entrance := DungeonEntrance.for_dungeon(get_tree(), id)
		if entrance != null:
			await _through(player, entrance, id == &"well")

	player.health = player.max_health
	player.respawn_at(home - Vector3.UP * 1.5)
	await _settle(0.5)


## Stands `player` at `at`, facing `target`.
func _place(player: PlayerCharacter, at: Vector3, target: Vector3) -> void:
	player.global_position = at + Vector3.UP * 0.3
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var toward := target - at
	player.rotation.y = atan2(toward.x, toward.z)


func _press(action: String) -> void:
	Input.action_press(action)
	await _settle(0.1)
	Input.action_release(action)
	await _settle(0.1)


## In through `entrance` with the interact button and out again -- clearing the dungeon on the
## way if `clear` is set.
func _through(player: PlayerCharacter, entrance: DungeonEntrance, clear: bool) -> void:
	var id := entrance.dungeon_id
	_place(player, entrance.exit_position().lerp(entrance.door_position(), 0.6),
			entrance.door_position())
	await _settle(0.5)
	await _press("p0_interact")
	await _settle(0.4)
	var inside := Dungeon.containing(get_tree(), player.global_position)
	_check("%s: through the door and into its dungeon" % id, inside != null and inside.dungeon_id == id,
			"%.1f m from the door" % player.global_position.distance_to(entrance.door_position()))
	if inside == null:
		return
	_check("%s: down there it is dark, not daylight" % id,
			main.split_screen.cameras[0].camera.environment != null)
	if clear:
		await _clear(player, inside, entrance)
	else:
		await _leave(player, inside, entrance)


## The guardian, the big chest and the way out.
func _clear(player: PlayerCharacter, dungeon: Dungeon, entrance: DungeonEntrance) -> void:
	var id := dungeon.dungeon_id
	var parked := _park_monsters_near(dungeon.entry_position(), 300.0)
	var chest := dungeon.big_chest
	## From the side: the reward lands in front of it, and would be picked up on landing.
	_place(player, chest.global_position + chest.global_basis.x * 2.6, chest.global_position)
	await _settle(0.5)
	await _press("p0_interact")
	_check("%s: the big chest is locked while its guardian stands" % id, chest.locked and not chest.is_open)
	var boss := dungeon.boss
	boss.take_damage(boss.max_health * 3, boss.global_position + Vector3.FORWARD, 0.0, 0.0)
	await _settle(0.4)
	_check("%s: beating the guardian unlocks it" % id, not chest.locked)
	await _press("p0_interact")
	await _settle(0.6)
	_check("%s: the big chest opens" % id, chest.is_open)
	var reward := dungeon.reward_item
	var lying: Pickup = null
	for node in get_tree().get_nodes_in_group("pickups"):
		var pickup := node as Pickup
		if pickup != null and pickup.item_id() == reward and dungeon.is_ancestor_of(pickup):
			lying = pickup
	_check("%s: with %s inside" % [id, reward], lying != null)
	if lying != null:
		player.remove_item(reward)
		## Hearts and armour are used up on the spot rather than held.
		var hearts := player.max_health
		var armour := player.armor_level
		_place(player, lying.global_position, lying.global_position + Vector3.FORWARD)
		await _settle(1.2)
		_check("%s: and it can be picked up" % id, player.has_item(reward)
				or player.max_health > hearts or player.armor_level > armour)
	_unpark_monsters(parked)
	await _leave(player, dungeon, entrance)


func _leave(player: PlayerCharacter, dungeon: Dungeon, entrance: DungeonEntrance) -> void:
	var door := dungeon.exit_door()
	_place(player, door.door_position(), door.global_position)
	await _settle(1.1)
	await _press("p0_interact")
	await _settle(0.4)
	_check("%s: out through the door and back beside the way in" % dungeon.dungeon_id,
			Dungeon.containing(get_tree(), player.global_position) == null
			and _flat_distance(player.global_position, entrance.exit_position()) < 2.5,
			"%.1f m from it" % _flat_distance(player.global_position, entrance.exit_position()))


## A straight walk into a chunk's deep water: {"start" (world, a run-up on dry footing), "action"
## (the direction to hold, with the camera facing north), "last_safe" (the last tile on the way
## that counts as safe footing)}. Empty if no clear run is found.
func _walk_into_deep(chunk: Chunk) -> Dictionary:
	for run_up in [8, 6, 5]:
		var run := _walk_into_deep_from(chunk, run_up)
		if not run.is_empty():
			return run
	return {}


func _walk_into_deep_from(chunk: Chunk, run_up: int) -> Dictionary:
	var terrain := chunk.terrain
	var size := terrain.size
	var actions := ["p0_left", "p0_up", "p0_right", "p0_down"]
	for z in size:
		for x in size:
			if not terrain.is_deep(x, z):
				continue
			for side in 4:
				var dx := ChunkMesher.NEIGHBOUR_DX[side]
				var dz := ChunkMesher.NEIGHBOUR_DZ[side]
				var clear := true
				for k in range(1, run_up + 1):
					var tx := x + dx * k
					var tz := z + dz * k
					if not terrain.in_bounds(tx, tz) or terrain.is_hazard(tx, tz) \
							or chunk._occupied.has(Vector2i(tx, tz)) \
							or terrain.rim(tx, tz) < WorldGenerator.BORDER \
							or (k > 1 and not terrain.can_walk(tx, tz, (side + 2) % 4)):
						clear = false
						break
				if not clear:
					continue
				var last_safe := Vector3.INF
				for k in range(1, run_up + 1):
					var at := chunk.global_position + chunk.tile_surface(x + dx * k, z + dz * k)
					if Chunk.is_safe_footing(get_tree(), at):
						last_safe = at
						break
				var start := chunk.global_position + chunk.tile_surface(x + dx * run_up, z + dz * run_up)
				## Far enough back that being put on the shore is not being put back at the start.
				if last_safe == Vector3.INF or _flat_distance(last_safe, start) < 5.0:
					continue
				## Walking towards the water is the opposite of `side`: +x is right, +z is down.
				return {
					"start": start,
					"action": actions[side],
					"last_safe": last_safe,
				}
	return {}


## The river, in the real world: a raft rides it and drifts downstream; without one it sweeps you
## back to the bank.
func _check_river(player: PlayerCharacter) -> void:
	var world := main.world as GameWorld
	var spot := world.river_landmark("river")
	_check("the world has a river", spot != Vector3.INF)
	if spot == Vector3.INF:
		return
	var bank := world.river_landmark("bridge")
	_check("and a bridge over it", bank != Vector3.INF)
	player.is_dead = false
	player.health = player.max_health
	## Somewhere safe to be swept back to: on the bridge's bank.
	player.respawn_at(bank)
	await _settle(1.0)
	player.add_item(ItemDB.RAFT)
	player.respawn_at(spot + Vector3.UP * 0.2)
	await _settle(0.6)
	var start := player.global_position
	_check("a raft rides on the river", player.is_rafting(),
			"%.2f m above the bank" % (player.global_position.y - spot.y))
	await _settle(2.0)
	var drift := Vector2(player.global_position.x - start.x, player.global_position.z - start.z)
	_check("and the current carries it downstream", drift.length() > 1.5 or not player.is_rafting(),
			"%.1f m in 2 s" % drift.length())
	var before := player.health
	player.remove_item(ItemDB.RAFT)
	player.respawn_at(spot + Vector3.UP * 0.2)
	await _settle(1.5)
	_check("without a raft the river sweeps you back to the bank",
			player.global_position.distance_to(spot) > 2.0 and player.health < before,
			"%.1f m from the water, hp %d -> %d" % [player.global_position.distance_to(spot), before,
					player.health])

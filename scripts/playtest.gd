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
		victim.set_physics_process(true)
		player.visual.stop_action()

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

	# --- right-button free look ---
	await _check_mouse_look(player)

	# --- the dragon fight ---
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

	_finish()


## The boss fight end to end: waking it, being hit by it, hitting it back, the reset when the
## party is wiped off the platform, and the win. Everything here is timing the unit tests cannot
## see -- whether an attack's damage frame actually fires, whether the reset notices an empty
## arena, whether killing it ends the run.
func _fight_dragon(world: GameWorld, player: PlayerCharacter) -> void:
	var dragon := world.dragon
	if dragon == null:
		_check("the dragon exists to fight", false)
		return

	var centre := dragon.arena_centre
	## Nothing should be standing on the platform to break line of sight or block a knockback.
	var clutter := 0
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
	_check("the boss arena is clear of scenery and monsters", clutter == 0,
			"%d things on the platform" % clutter)

	_check("the dragon starts dormant", dragon.state == Dragon.State.DORMANT)
	_check("the boss health bar is hidden before the fight", not dragon.is_engaged())

	## Step onto the platform. Everything about engagement is measured from the arena centre,
	## so this is the moment the fight is supposed to start.
	player.is_dead = false
	player.health = player.max_health
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
	for node in get_tree().current_scene.get_children():
		if node is FirePatch:
			count += 1
	return count


func _off_platform(player: PlayerCharacter, dragon: Dragon) -> bool:
	var offset := player.global_position - dragon.arena_centre
	offset.y = 0.0
	return offset.length() > dragon.arena_radius \
			or player.global_position.y < dragon.arena_centre.y - 5.0


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
func _clear_line_position(player: PlayerCharacter, distance: float) -> Vector3:
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

		var sight := PhysicsRayQueryParameters3D.create(from, standing + Vector3.UP * 0.85)
		sight.exclude = [player.get_rid()]
		if space.intersect_ray(sight).is_empty():
			return standing
	return Vector3.INF


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

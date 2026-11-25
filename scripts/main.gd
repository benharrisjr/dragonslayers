class_name Main
extends Node

## The game scene: lobby, then world, then split-screen, with a pause menu over the top.
##
## The template's main menu loads this scene when Play is pressed and it hands back to that menu
## when the players leave.
##
## The host does not build the world until it says go, and clients do not build it until the
## host's seed arrives -- that single broadcast is the only thing standing between "four
## machines in a lobby" and "four machines in the same 256 m map".

const HOST_START_DELAY := 0.6

var world: GameWorld
var split_screen: SplitScreen
var lobby: LobbyScreen
var outcome: OutcomeScreen
## The overhead map, toggled with M during a match.
var map_screen: MapScreen
## Proximity voice chat. Always present, at the same path on every machine, and idle offline.
var voice: VoiceChat
var options: OptionsScreen

## The frame the pause menu last opened or closed on. One Start press can arrive twice -- once
## raw, once as the template's routed action -- and must not open the menu and shut it again.
var _menu_toggled_frame: int = -1


func _ready() -> void:
	## Projectiles and fire patches are parented here (GameWorld.effects_root).
	add_to_group(GameWorld.EFFECTS_GROUP)
	PlayerInput.enabled = true
	PlayerBindings.reapply()
	## Rendered now rather than on first use, so the first sword swing does not hitch.
	GameSfx.register()
	voice = VoiceChat.new()
	voice.name = "VoiceChat"
	add_child(voice)

	lobby = LobbyScreen.new()
	lobby.name = "Lobby"
	add_child(lobby)
	lobby.start_requested.connect(_on_lobby_start)
	lobby.begin_requested.connect(func() -> void: NetworkManager.start_match(_pending_seed))
	lobby.cancel_requested.connect(func() -> void: NetworkManager.leave())
	lobby.back_requested.connect(_quit_to_main_menu)
	NetworkManager.match_started.connect(_on_match_started)
	NetworkManager.join_failed.connect(_on_join_failed)
	GameState.phase_changed.connect(func(_phase: GameState.Phase) -> void: _sync_input_state())
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	_handle_command_line()


func _exit_tree() -> void:
	PlayerInput.enabled = true


## `--playtest`, `--host`, `--join=ADDR`, `--slots=N` and `--seed=N` exist so a match can be
## driven from a shell -- both for the automated playtest and for opening two windows quickly
## when testing netcode by hand.
func _handle_command_line() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", false, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "1"

	var slots := int(args.get("slots", "1"))
	## `--season=winter` plays every match in that season rather than the one the seed rolls.
	Season.forced = Season.from_name(String(args.get("season", "")))
	## `--no-comic` draws everything without the comic cel shading.
	if not args.has("no-comic"):
		ComicLook.start(self)
	## `--time=0.75` starts every match at that time of day (0 sunrise, 0.25 noon, 0.5 sunset, 0.75
	## midnight); `--freeze-time` keeps it there.
	DayNight.forced = float(args["time"]) if args.has("time") else -1.0
	DayNight.frozen = args.has("freeze-time")
	## `--heroes=mage,archer` picks each local player's hero, as the character select would.
	if args.has("heroes"):
		var heroes: Array[StringName] = []
		for hero in String(args["heroes"]).split(",", false):
			heroes.append(StringName(hero.strip_edges()))
		NetworkManager.local_heroes = heroes
	var world_seed := int(args.get("seed", "0"))
	## `--world=new` plays a fresh saved world (from --seed, if given); `--world=N` loads world N.
	if args.has("world") and not args.has("join"):
		var which := String(args["world"])
		world_seed = _use_world(LobbyScreen.NEW_WORLD if which == "new" else int(which), world_seed)

	## Diagnostics are installed before the mode is chosen, not after: the join and host
	## branches used to return early and silently skip every hook that came below them.
	if args.has("goto"):
		## Debug teleport, mostly for looking at the mountain without walking there. Deferred
		## until the world exists, since that is what it needs to aim at.
		NetworkManager.match_started.connect(func(_seed: int) -> void:
			_goto.call_deferred(args["goto"]), CONNECT_ONE_SHOT)
	if args.has("give"):
		## `--give=lantern,raft`: every local hero starts with these.
		NetworkManager.match_started.connect(func(_seed: int) -> void:
			(func() -> void:
				for pid in PlayerRegistry.local_pids():
					for item in String(args["give"]).split(",", false):
						(PlayerRegistry.body_of(pid) as PlayerCharacter).add_item(StringName(item))).call_deferred(),
			CONNECT_ONE_SHOT)
	if args.has("reveal-entrances"):
		## Opens every hidden dungeon entrance as soon as the world is up, to look at them open.
		NetworkManager.match_started.connect(func(_seed: int) -> void:
			(func() -> void:
				for entrance in DungeonEntrance.all(get_tree()):
					entrance.reveal_quietly()).call_deferred(), CONNECT_ONE_SHOT)

	if args.has("netcheck"):
		var check := NetCheck.new()
		check.name = "NetCheck"
		check.main = self
		check.report_delay = maxf(2.0, float(args["netcheck"]))
		add_child(check)

	if args.has("perf"):
		var probe := PerfProbe.new()
		probe.name = "PerfProbe"
		add_child(probe)

	if args.has("capture"):
		var capture := DebugCapture.new()
		capture.name = "DebugCapture"
		capture.path = args["capture"]
		capture.delay = float(args.get("capture-delay", "5"))
		capture.follow_up = int(args.get("capture-count", "0"))
		capture.overview = args.has("capture-overview")
		capture.overview_focus = String(args.get("capture-overview", ""))
		capture.annotate = args.has("capture-annotate")
		capture.gear = args.has("capture-gear") or args.has("capture-wheel")
		capture.wheel = args.has("capture-wheel")
		capture.map = args.has("capture-map")
		capture.shop = args.has("capture-shop")
		capture.look_only = args.get("capture-shop", "") == "look"
		capture.rock = args.has("capture-rock")
		capture.lobby = args.has("capture-lobby")
		capture.lobby_view = String(args.get("capture-lobby", ""))
		capture.walk = args.has("capture-walk")
		capture.armor = int(args.get("capture-armor", "-1"))
		capture.dragon_view = String(args.get("capture-dragon", ""))
		capture.charge_view = String(args.get("capture-charge", ""))
		capture.raft = args.has("capture-raft")
		capture.drop_in = args.has("capture-dropin")
		add_child(capture)

	if args.has("jitter"):
		var jitter := JitterProbe.new()
		jitter.name = "JitterProbe"
		jitter.main = self
		add_child(jitter)

	if args.has("playtest"):
		var playtest := Playtest.new()
		playtest.name = "Playtest"
		playtest.main = self
		add_child(playtest)

	if args.has("join"):
		PlayerBindings.apply_auto(slots)
		_start_session("join", args["join"], slots)
	elif args.has("host"):
		PlayerBindings.apply_auto(slots)
		## Hosting from the command line skips the waiting room, since nobody is there to
		## press Start. Late joiners are handled by NetworkManager anyway.
		if NetworkManager.host_game(slots):
			lobby.visible = false
			_start_match_soon(world_seed)
	elif args.has("playtest") or args.has("solo") or args.has("perf"):
		PlayerBindings.apply_auto(slots)
		_start_session("offline", "", slots, world_seed if world_seed != 0 else 4242)



## Puts every local player next to a named landmark. "dragon" is the summit, "ramp" the foot of
## the mountain's ascent; anything else is read as a biome id.
func _goto(destination: String) -> void:
	if world == null:
		return
	var at := Vector3.ZERO
	if destination.begins_with("entrance:"):
		## In front of a dungeon's way in, looking at it.
		var entrance := DungeonEntrance.for_dungeon(get_tree(), StringName(destination.get_slice(":", 1)))
		if entrance == null:
			return
		at = entrance.global_position + entrance.global_basis.z * 9.0 + Vector3.UP * 1.0
		if entrance.kind == DungeonEntrance.Kind.LAKE:
			at = entrance.exit_position() + Vector3.UP * 1.0
		if split_screen != null:
			var back := entrance.global_basis.z
			for camera in split_screen.cameras:
				camera.yaw = atan2(back.x, back.z)
		destination = ""
	elif destination.begins_with("dungeon:"):
		var dungeon := Dungeon.by_id(get_tree(), StringName(destination.get_slice(":", 1)))
		if dungeon == null:
			return
		at = dungeon.entry_position() + Vector3.UP * 1.0
		destination = ""
	if destination == "":
		pass
	elif destination == "dragon" and world.dragon != null:
		at = world.dragon.global_position + Vector3(0.0, 1.0, 12.0)
	elif destination.begins_with("ledge"):
		## `ledge` or `ledge:N`: on top of a ledged cliff (the Nth chunk that has one), a few
		## steps back from its lip, facing it. `ledge:N:below` stands at its foot instead.
		var parts := destination.split(":")
		var skip := int(parts[1]) if parts.size() > 1 else 0
		var below := parts.size() > 2 and parts[2] == "below"
		for chunk in world.chunks:
			if chunk.ledges.is_empty() or chunk.biome.id == &"town":
				continue
			if skip > 0:
				skip -= 1
				continue
			var segment: Array = chunk.ledges[chunk.ledges.size() / 2]
			var middle := ((segment[0] as Vector2) + (segment[1] as Vector2)) * 0.5
			var inward: Vector2 = segment[3]
			if below:
				inward = -inward
			var spot := middle + inward * 4.0
			## Below, dropped from the top's height onto whatever ground is there.
			at = chunk.global_position + Vector3(spot.x, float(segment[2]) + 1.0, spot.y)
			if split_screen != null:
				for camera in split_screen.cameras:
					camera.yaw = atan2(inward.x, inward.y)
			break
	elif destination.begins_with("shrine"):
		## `shrine` or `shrine:N`: in front of the Nth dungeon's shrine on the mountain
		## (0 the well's, at the bottom), facing it.
		var mountain := world.chunk_of_biome(&"mountain")
		var which := int(destination.get_slice(":", 1)) if destination.contains(":") else 0
		if mountain == null or which >= mountain.shrines.size():
			return
		var shrine := mountain.shrines[which]
		var front := shrine.global_basis.z
		at = shrine.global_position + front * 2.6 + Vector3.UP * 1.0
		if split_screen != null:
			for camera in split_screen.cameras:
				camera.yaw = atan2(front.x, front.z)
	elif destination.begins_with("bluff") or destination.begins_with("landbridge"):
		## `bluff[:N]`: on a bluff, at the near end of the Nth bluff bridge, looking across it.
		## `landbridge[:N]`: on the bank a little way back from the Nth land bridge, facing it.
		var kind := &"sky" if destination.begins_with("bluff") else &"land"
		var skip := int(destination.get_slice(":", 1)) if destination.contains(":") else 0
		for chunk in world.chunks:
			for spec: Dictionary in chunk.terrain.bridges:
				if spec.get("kind", &"plank") != kind:
					continue
				if skip > 0:
					skip -= 1
					continue
				var from := Vector2(spec["from"]) * ChunkMesher.TILE_SIZE
				var to := (Vector2(spec["to"]) + Vector2.ONE) * ChunkMesher.TILE_SIZE
				var middle := (from + to) * 0.5
				var heading := Vector2(1.0, 0.0) if spec["along_x"] else Vector2(0.0, 1.0)
				var back := (to - from).dot(heading) * 0.5 + (1.0 if kind == &"sky" else 6.0)
				var spot := middle - heading * back
				at = chunk.global_position + Vector3(spot.x,
						int(spec["level"]) * ChunkMesher.STEP_HEIGHT + 1.0, spot.y)
				if split_screen != null:
					for camera in split_screen.cameras:
						camera.yaw = atan2(-heading.x, -heading.y)
				break
			if at != Vector3.ZERO:
				break
		if at == Vector3.ZERO:
			return
	elif destination == "crate" or destination == "gems":
		## `crate`: beside the first crate in the world, facing it. `gems`: the same spot, with one
		## of every gem laid out in a row in front, to look at.
		for chunk in world.chunks:
			for index in chunk._props.size():
				if not chunk.is_crate(index) or not chunk.can_lift(index):
					continue
				var crate := (chunk._props[index]["node"] as Node3D).global_position
				at = crate + Vector3(0.0, 1.0, 4.5)
				if split_screen != null:
					for camera in split_screen.cameras:
						camera.yaw = PI
				if destination == "gems":
					for i in Gem.VALUES.size():
						chunk._net_spawn_pickup(Pickup.Kind.GOLD, Gem.VALUES[i],
								crate + Vector3((i - 2) * 1.3, 0.4, 2.0))
				break
			if at != Vector3.ZERO:
				break
		if at == Vector3.ZERO:
			return
	elif destination == "slope":
		## The foot of the first slope up from one chunk to the next.
		for chunk in world.chunks:
			if chunk.terrain.ramps.is_empty():
				continue
			var ramp: Dictionary = chunk.terrain.ramps[0]
			var foot := WorldGenerator._from_side(WorldGenerator.CHUNK_TILES, ramp["side"],
					int(ramp["length"]) + 2, int(ramp["start"]) + WorldGenerator.RAMP_WIDTH / 2)
			at = chunk.global_position + chunk.tile_surface(foot.x, foot.y) + Vector3.UP
			break
	elif destination == "ramp":
		at = world.ascent_foot() + Vector3.UP * 1.0
	elif destination in ["bridge", "waterfall", "pond", "river", "bigfall"]:
		## The river's landmarks: stood on the bank beside one.
		## Stood on the river itself without a raft, the current would sweep them away.
		var spot := world.river_landmark("bank" if destination == "river" else destination)
		if spot == Vector3.INF:
			return
		at = spot + Vector3.UP * 1.0
	elif destination == "sea":
		## The water's edge on a beach: the lowest sand still above the sea.
		var beach := world.chunk_of_biome(&"beach")
		if beach == null:
			return
		var terrain := beach.terrain
		var lowest := INF
		for z in terrain.size:
			for x in terrain.size:
				var y := ChunkMesher.height_to_world(terrain.level(x, z))
				var wet_beside := terrain.in_bounds(x, z + 1) and x > 0 and z > 0 \
						and terrain.in_bounds(x + 1, z) and minf(minf(
						ChunkMesher.height_to_world(terrain.level(x, z + 1)),
						ChunkMesher.height_to_world(terrain.level(x + 1, z))), minf(
						ChunkMesher.height_to_world(terrain.level(x, z - 1)),
						ChunkMesher.height_to_world(terrain.level(x - 1, z)))) \
						< WorldGenerator.SEA_SURFACE
				if wet_beside and y > WorldGenerator.SEA_SURFACE and y < lowest:
					lowest = y
					at = beach.global_position + Vector3((x + 0.5) * ChunkMesher.TILE_SIZE,
							y + 1.0, (z + 0.5) * ChunkMesher.TILE_SIZE)
		if lowest == INF:
			return
	elif destination == "lake":
		## On the shore, a step back from the shallows, looking out over the water.
		var lake := world.chunk_of_biome(&"lake")
		if lake == null:
			return
		var terrain := lake.terrain
		var half := terrain.size / 2
		var z := half
		while z < terrain.size - 1 and terrain.level(half, z) < terrain.base_level:
			z += 1
		at = lake.global_position + lake._tile_centre(half, mini(z + 2, terrain.size - 1)) + Vector3.UP
		if split_screen != null:
			for camera in split_screen.cameras:
				camera.yaw = 0.0
	else:
		var chunk := world.chunk_of_biome(StringName(destination))
		if chunk == null:
			return
		at = chunk.highest_tile() + Vector3.UP * 2.0
	var offset := 0
	for pid in PlayerRegistry.local_pids():
		var player := PlayerRegistry.body_of(pid) as PlayerCharacter
		if player != null:
			player.global_position = at + Vector3(offset * 2.0, 0.0, 0.0)
			player.reset_physics_interpolation()
			offset += 1


## The lobby hands over one device list and one hero per joined player; the devices become the
## players' controls before anything that reads input exists.
func _on_lobby_start(mode: String, address: String, devices: Array, heroes: Array,
		world_id: int) -> void:
	PlayerBindings.apply(devices)
	var picked: Array[StringName] = []
	for hero: StringName in heroes:
		picked.append(hero)
	NetworkManager.local_heroes = picked
	var world_seed := _use_world(world_id)
	_start_session(mode, address, devices.size(), world_seed)


## Makes `world_id` the world this session plays (LobbyScreen.NEW_WORLD makes a fresh one;
## NO_WORLD plays unsaved, as a joiner does) and returns the seed to build it from, or 0 for a
## random one. `world_seed` is the seed a new world should have, if it matters (--seed).
func _use_world(world_id: int, world_seed: int = 0) -> int:
	GameState.world = null
	if world_id == LobbyScreen.NEW_WORLD:
		GameState.world = SaveManager.new_world(world_seed)
	elif world_id != LobbyScreen.NO_WORLD:
		GameState.world = SaveManager.load_world(world_id)
	return GameState.world.world_seed if GameState.world != null else world_seed


func _start_session(mode: String, address: String, slots: int, world_seed: int = 0) -> void:
	match mode:
		"offline":
			NetworkManager.start_offline(slots)
			lobby.visible = false
			_start_match_soon(world_seed)
		"host":
			_pending_seed = world_seed
			if NetworkManager.host_game(slots):
				lobby.show_wait("Hosting on port %d  ·  waiting for players" % Transport.DEFAULT_PORT,
						true)
			else:
				lobby.show_message("Could not host: is port %d already in use?" % Transport.DEFAULT_PORT)
		"join":
			if NetworkManager.join_game(address, slots):
				lobby.show_wait("Connecting to %s ..." % address, false)
			else:
				lobby.show_message("Could not connect to %s" % address)


## The seed the host's waiting room will start with: its saved world's, or 0 for a random one.
var _pending_seed: int = 0


func _start_match_soon(world_seed: int) -> void:
	await get_tree().create_timer(HOST_START_DELAY).timeout
	NetworkManager.start_match(world_seed)


func _on_match_started(world_seed: int) -> void:
	## Tear the old match down completely before building the next one. The registry outlives
	## the world, so a rebuild that leaves it holding the previous world's bodies hands every
	## monster a list of freed players to chase.
	_teardown_match()
	lobby.visible = false

	world = GameWorld.new()
	world.name = "World"
	## Said outright rather than inherited: this scene hangs under the main scene's root
	## Control, and Control nodes do not pass physics interpolation down to 3D children.
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(world)
	world.build(world_seed)

	split_screen = SplitScreen.new()
	split_screen.name = "SplitScreen"
	add_child(split_screen)
	split_screen.build(PlayerRegistry.local_pids())
	if not PlayerRegistry.roster_changed.is_connected(_on_roster_changed):
		PlayerRegistry.roster_changed.connect(_on_roster_changed, CONNECT_DEFERRED)

	## Added after the panes so it draws over all of them.
	if outcome == null:
		outcome = OutcomeScreen.new()
		outcome.name = "OutcomeScreen"
		add_child(outcome)
		outcome.rematch_requested.connect(_on_rematch)
		outcome.main_menu_requested.connect(_quit_to_main_menu)
	else:
		move_child(outcome, get_child_count() - 1)
	if options != null:
		move_child(options, get_child_count() - 1)
	_sync_input_state()


## "Hunt again" starts a fresh world; in a saved world the button is "Keep exploring" instead,
## and play simply carries on with the dragon dead until the world is next loaded.
func _on_rematch() -> void:
	if GameState.world != null:
		GameState.phase = GameState.Phase.PLAYING
	else:
		NetworkManager.start_match()


func _teardown_match() -> void:
	if world != null:
		world.teardown()
		world.queue_free()
		world = null
	if split_screen != null:
		split_screen.queue_free()
		split_screen = null
	## The map is a picture of the world that just went.
	if map_screen != null:
		map_screen.queue_free()
		map_screen = null
	## Effects in flight belong to the match that fired them.
	for node in get_children():
		if node is Projectile or node is FirePatch or node is ThrownRock or node is Gust \
				or node is RockShards or node is SlashTrail or node is Boomerang:
			node.queue_free()


func _on_join_failed(reason: String) -> void:
	## Also how a client learns the host has gone: the match it was in no longer exists.
	_close_options()
	_teardown_match()
	if outcome != null:
		outcome.visible = false
	lobby.show_message(reason.capitalize())
	_sync_input_state()


func _quit_to_main_menu() -> void:
	if SceneManager.is_transitioning():
		return
	if world != null:
		world.save_progress()
	NetworkManager.leave()
	if world != null:
		world.teardown()
	GameState.world = null
	GameState.phase = GameState.Phase.LOBBY
	SaveManager.save_game()
	SceneManager.change_scene(ProjectConfig.MAIN_MENU_SCENE)


# --- pause menu and who owns the gamepad --------------------------------------------------

func in_match() -> bool:
	return world != null


func _menu_open() -> bool:
	return options != null and options.visible


## One place decides whether the players or the menus have the controls. During play the
## template's pad cursor is blocked, or the left stick would steer a pointer around the screen
## as well as the character; with any menu up the cursor comes back and the players stop
## reading input.
func _sync_input_state() -> void:
	var playing := in_match() and not _menu_open() \
			and GameState.phase == GameState.Phase.PLAYING
	PlayerInput.enabled = playing
	if playing and not is_in_group(PadCursor.BLOCK_GROUP):
		add_to_group(PadCursor.BLOCK_GROUP)
	elif not playing and is_in_group(PadCursor.BLOCK_GROUP):
		remove_from_group(PadCursor.BLOCK_GROUP)
	if not playing and split_screen != null and split_screen.is_looking():
		split_screen.end_look()


## Start on a pad, while playing. It has to be read raw and here: the blocked pad cursor
## swallows every joypad event, and scene nodes see events before that autoload does.
## Start on a pad nobody is playing on is someone picking it up to join; so is Enter, if
## nobody is on the keyboard.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ENTER \
			and _can_drop_in() and not PlayerBindings.in_play(PlayerBindings.KEYBOARD,
			NetworkManager.local_slot_count):
		get_viewport().set_input_as_handled()
		drop_in(PlayerBindings.KEYBOARD)
		return
	var button := event as InputEventJoypadButton
	if button == null or not button.pressed or button.button_index != JOY_BUTTON_START:
		return
	if not is_in_group(PadCursor.BLOCK_GROUP) or not in_match():
		return
	get_viewport().set_input_as_handled()
	if not PlayerBindings.in_play(button.device, NetworkManager.local_slot_count):
		if _can_drop_in():
			drop_in(button.device)
		return
	_toggle_options()


## Whether someone could join this machine's game right now: mid-match, playing, nothing open
## over it, and a seat free.
func _can_drop_in() -> bool:
	return in_match() and is_in_group(PadCursor.BLOCK_GROUP) \
			and GameState.phase == GameState.Phase.PLAYING \
			and NetworkManager.local_slot_count < PlayerRegistry.MAX_LOCAL_SLOTS


## Seats a new player on `device` in the match in progress. The world spawns their body when
## the roster changes and the screen splits again for them (_on_roster_changed).
func drop_in(device: int) -> int:
	var slot := NetworkManager.local_slot_count
	PlayerBindings.assign_device(slot, device)
	var pid := NetworkManager.add_local_player()
	if pid < 0:
		return -1
	GameSfx.play(&"charged")
	return pid


## Someone joined or left on this machine: re-split the screen for whoever is here now. Deferred
## so the world, which also listens, has spawned (or removed) their body first. Anyone new is
## brought to the first player here, rather than left at the town spawn half a map away.
func _on_roster_changed() -> void:
	if split_screen == null or world == null:
		return
	var here := PlayerRegistry.local_pids()
	var shown: Array[int] = []
	for pid in here:
		if PlayerRegistry.body_of(pid) != null:
			shown.append(pid)
	if shown == split_screen.shown_pids():
		return
	var leader := PlayerRegistry.body_of(shown[0]) as PlayerCharacter if not shown.is_empty() else null
	for pid in shown:
		var body := PlayerRegistry.body_of(pid) as PlayerCharacter
		if split_screen.shown_pids().has(pid) or body == leader or leader == null:
			continue
		var side := Vector3(1.6, 0.6, 0.0).rotated(Vector3.UP, TAU * PlayerRegistry.slot_of(pid) / 4.0)
		body.global_position = leader.global_position + side
		body.velocity = Vector3.ZERO
		body.reset_physics_interpolation()
	split_screen.build(shown)


## Escape -- and Start again once the menu is open, when the pad cursor routes it to this action.
func _unhandled_input(event: InputEvent) -> void:
	if not in_match() or Keybinds.suppress_hotkeys:
		return
	if GameState.phase != GameState.Phase.PLAYING:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_M \
			and not _menu_open():
		get_viewport().set_input_as_handled()
		toggle_map()
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_V \
			and not _menu_open() and voice.active():
		get_viewport().set_input_as_handled()
		voice.toggle_mute()
		return
	if event.is_action_pressed("open_menu"):
		get_viewport().set_input_as_handled()
		## Escape puts the map away before it opens the menu.
		if map_screen != null and map_screen.visible:
			map_screen.toggle()
			return
		_toggle_options()


func toggle_map() -> void:
	if world == null:
		return
	if map_screen == null:
		map_screen = MapScreen.new()
		map_screen.name = "MapScreen"
		add_child(map_screen)
		## Over the panes, under the pause menu and the outcome screen.
		if split_screen != null:
			move_child(map_screen, split_screen.get_index() + 1)
		map_screen.setup(world)
	map_screen.toggle()


func _toggle_options() -> void:
	if _menu_toggled_frame == Engine.get_process_frames():
		return
	_menu_toggled_frame = Engine.get_process_frames()
	if _menu_open():
		options.request_close()
	else:
		_open_options()


func _open_options() -> void:
	if options == null:
		options = OptionsScreen.new()
		options.name = "PauseMenu"
		options.closed.connect(_close_options)
		options.main_menu_requested.connect(_quit_to_main_menu)
		add_child(options)
		options.show_ingame_buttons()
	options.visible = true
	_sync_input_state()


func _close_options() -> void:
	if options != null:
		options.visible = false
	_sync_input_state()


## A pad that drops out mid-fight would leave its player standing still with no explanation,
## so the menu comes up. Plugging it back in needs nothing: the bindings name the device id.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected or not in_match() or _menu_open():
		return
	if PlayerBindings.slot_of_pad(device) >= 0 \
			and PlayerBindings.slot_of_pad(device) < NetworkManager.local_slot_count \
			and GameState.phase == GameState.Phase.PLAYING:
		_open_options()

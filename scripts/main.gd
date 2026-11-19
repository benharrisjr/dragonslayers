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
	lobby.begin_requested.connect(func() -> void: NetworkManager.start_match())
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
	var world_seed := int(args.get("seed", "0"))

	## Diagnostics are installed before the mode is chosen, not after: the join and host
	## branches used to return early and silently skip every hook that came below them.
	if args.has("goto"):
		## Debug teleport, mostly for looking at the mountain without walking there. Deferred
		## until the world exists, since that is what it needs to aim at.
		NetworkManager.match_started.connect(func(_seed: int) -> void:
			_goto.call_deferred(args["goto"]), CONNECT_ONE_SHOT)

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
		capture.gear = args.has("capture-gear") or args.has("capture-wheel")
		capture.wheel = args.has("capture-wheel")
		capture.map = args.has("capture-map")
		capture.shop = args.has("capture-shop")
		capture.look_only = args.get("capture-shop", "") == "look"
		capture.rock = args.has("capture-rock")
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
	if destination == "dragon" and world.dragon != null:
		at = world.dragon.global_position + Vector3(0.0, 1.0, 12.0)
	elif destination == "ramp":
		at = world.ascent_foot() + Vector3.UP * 1.0
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


## The lobby hands over one device list per joined player; those become the players' controls
## before anything that reads input exists.
func _on_lobby_start(mode: String, address: String, devices: Array) -> void:
	PlayerBindings.apply(devices)
	_start_session(mode, address, devices.size())


func _start_session(mode: String, address: String, slots: int, world_seed: int = 0) -> void:
	match mode:
		"offline":
			NetworkManager.start_offline(slots)
			lobby.visible = false
			_start_match_soon(world_seed)
		"host":
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

	## Added after the panes so it draws over all of them.
	if outcome == null:
		outcome = OutcomeScreen.new()
		outcome.name = "OutcomeScreen"
		add_child(outcome)
		outcome.rematch_requested.connect(func() -> void: NetworkManager.start_match())
		outcome.main_menu_requested.connect(_quit_to_main_menu)
	else:
		move_child(outcome, get_child_count() - 1)
	if options != null:
		move_child(options, get_child_count() - 1)
	_sync_input_state()


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
				or node is RockShards:
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
	NetworkManager.leave()
	if world != null:
		world.teardown()
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
func _input(event: InputEvent) -> void:
	var button := event as InputEventJoypadButton
	if button == null or not button.pressed or button.button_index != JOY_BUTTON_START:
		return
	if not is_in_group(PadCursor.BLOCK_GROUP) or not in_match():
		return
	get_viewport().set_input_as_handled()
	_toggle_options()


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

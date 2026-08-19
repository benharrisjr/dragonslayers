class_name Main
extends Node

## Entry point: menu, then world, then split-screen.
##
## The host does not build the world until it says go, and clients do not build it until the
## host's seed arrives -- that single broadcast is the only thing standing between "four
## machines in a lobby" and "four machines in the same 256 m map".

const HOST_START_DELAY := 0.6

var world: GameWorld
var split_screen: SplitScreen
var menu: MainMenu

var _pending_start: bool = false


func _ready() -> void:
	menu = MainMenu.new()
	menu.name = "MainMenu"
	add_child(menu)
	menu.start_requested.connect(_on_start_requested)
	NetworkManager.match_started.connect(_on_match_started)

	_handle_command_line()


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

	if args.has("capture"):
		var capture := DebugCapture.new()
		capture.name = "DebugCapture"
		capture.path = args["capture"]
		capture.delay = float(args.get("capture-delay", "5"))
		capture.follow_up = int(args.get("capture-count", "0"))
		add_child(capture)

	if args.has("playtest"):
		var playtest := Playtest.new()
		playtest.name = "Playtest"
		playtest.main = self
		add_child(playtest)

	if args.has("join"):
		_on_start_requested("join", args["join"], slots)
	elif args.has("host"):
		_on_start_requested("host", "", slots)
		## Hosting from the command line skips the "wait for friends" step, since nobody is
		## there to press the key. Late joiners are handled by NetworkManager anyway.
		_pending_start = false
		_start_match_soon(world_seed)
	elif args.has("playtest") or args.has("solo"):
		_on_start_requested("offline", "", slots, world_seed if world_seed != 0 else 4242)


## Puts every local player next to a named landmark. "dragon" is the summit; anything else is
## read as a biome id.
func _goto(destination: String) -> void:
	if world == null:
		return
	var at := Vector3.ZERO
	if destination == "dragon" and world.dragon != null:
		at = world.dragon.global_position + Vector3(0.0, 1.0, 12.0)
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
			offset += 1


func _on_start_requested(mode: String, address: String, slots: int,
		world_seed: int = 0) -> void:
	match mode:
		"offline":
			NetworkManager.start_offline(slots)
			menu.visible = false
			_start_match_soon(world_seed)
		"host":
			if NetworkManager.host_game(slots):
				menu.set_status("hosting -- press Space when everyone has joined")
				_pending_start = true
		"join":
			if NetworkManager.join_game(address, slots):
				menu.set_status("connecting to %s ..." % address)


func _unhandled_input(_event: InputEvent) -> void:
	## The host starts the match once the lobby looks right, rather than on a countdown that
	## either rushes a late friend or makes everyone wait.
	if _pending_start and Input.is_action_just_pressed("ui_lobby_join"):
		_pending_start = false
		menu.visible = false
		NetworkManager.start_match()


func _start_match_soon(world_seed: int) -> void:
	await get_tree().create_timer(HOST_START_DELAY).timeout
	NetworkManager.start_match(world_seed)


func _on_match_started(world_seed: int) -> void:
	## Tear the old match down completely before building the next one. The registry outlives
	## the world, so a rebuild that leaves it holding the previous world's bodies hands every
	## monster a list of freed players to chase.
	if world != null:
		world.teardown()
		world.queue_free()
	if split_screen != null:
		split_screen.queue_free()
	menu.visible = false

	world = GameWorld.new()
	world.name = "World"
	add_child(world)
	world.build(world_seed)

	split_screen = SplitScreen.new()
	split_screen.name = "SplitScreen"
	add_child(split_screen)
	split_screen.build(PlayerRegistry.local_pids())

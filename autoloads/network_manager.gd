extends Node

## Hosting, joining, and keeping the four machines agreed on who is playing what.
##
## The world is host-authoritative -- monsters, chests, gold and damage are all decided by the
## host -- but player *movement* is owned by the client driving it. That trade is deliberate:
## friendslop wants responsive movement far more than it wants cheat resistance, and it costs
## nothing that matters, because the host can still shove a player around via
## `Combatant.apply_knockback`, which the owner always obeys.
##
## Offline play is not a special case with its own code path: with no peer assigned, this node
## reports itself as host with peer id 1, so every "if is_host()" branch in the game behaves
## exactly as it does when hosting for real.

signal connection_changed
signal match_started(world_seed: int)
signal join_failed(reason: String)

enum Mode { OFFLINE, HOST, CLIENT }

var mode: Mode = Mode.OFFLINE
## How many split-screen players this machine contributes.
var local_slot_count: int = 1
## The hero each of this machine's players picked in the character select, by slot. A slot
## past the end of the list (command-line starts, tests) gets ArchetypeDB's default.
var local_heroes: Array[StringName] = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return mode != Mode.CLIENT


func local_peer_id() -> int:
	return 1 if multiplayer.multiplayer_peer == null else multiplayer.get_unique_id()


func is_networked() -> bool:
	return mode != Mode.OFFLINE


# --- session setup ----------------------------------------------------------------------

func start_offline(slots: int) -> void:
	_reset()
	mode = Mode.OFFLINE
	local_slot_count = clampi(slots, 1, PlayerRegistry.MAX_LOCAL_SLOTS)
	_register_local_players()
	connection_changed.emit()


func host_game(slots: int, port: int = Transport.DEFAULT_PORT) -> bool:
	_reset()
	var peer := Transport.create_server(port)
	if peer == null:
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	local_slot_count = clampi(slots, 1, PlayerRegistry.MAX_LOCAL_SLOTS)
	_register_local_players()
	connection_changed.emit()
	return true


func join_game(address: String, slots: int, port: int = Transport.DEFAULT_PORT) -> bool:
	_reset()
	var peer := Transport.create_client(address, port)
	if peer == null:
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	local_slot_count = clampi(slots, 1, PlayerRegistry.MAX_LOCAL_SLOTS)
	connection_changed.emit()
	return true


func leave() -> void:
	_reset()
	connection_changed.emit()


func _reset() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	PlayerRegistry.clear()


func _register_local_players() -> void:
	var peer_id := local_peer_id()
	for slot in local_slot_count:
		var pid := PlayerRegistry.make_pid(peer_id, slot)
		PlayerRegistry.add_entry(pid, hero_for_slot(slot))


## Seats one more player on this machine in the middle of a match -- someone picking up a spare
## controller. They get the first hero nobody here is playing. Offline or hosting they are in
## the roster at once (and, hosting, everyone is told); as a client the host is asked, and they
## arrive with its reply. Returns their pid, or -1 if every seat here is taken.
func add_local_player() -> int:
	if local_slot_count >= PlayerRegistry.MAX_LOCAL_SLOTS:
		return -1
	var slot := local_slot_count
	var taken: Array[StringName] = []
	for other in local_slot_count:
		taken.append(hero_for_slot(other))
	var hero := ArchetypeDB.default_for_slot(slot)
	for candidate in ArchetypeDB.ORDER:
		if not taken.has(candidate):
			hero = candidate
			break
	while local_heroes.size() < slot:
		local_heroes.append(hero_for_slot(local_heroes.size()))
	if local_heroes.size() == slot:
		local_heroes.append(hero)
	else:
		local_heroes[slot] = hero
	local_slot_count += 1
	var pid := PlayerRegistry.make_pid(local_peer_id(), slot)
	if mode == Mode.CLIENT:
		_announce_local_players.rpc_id(1, local_slot_count, _local_hero_names())
	else:
		PlayerRegistry.add_entry(pid, hero)
		if is_networked():
			_receive_roster.rpc(_serialise_roster(), GameState.world_seed)
	connection_changed.emit()
	return pid


## The hero this machine's player in `slot` picked, or the default for that slot.
func hero_for_slot(slot: int) -> StringName:
	if slot < local_heroes.size() and ArchetypeDB.has(local_heroes[slot]):
		return local_heroes[slot]
	return ArchetypeDB.default_for_slot(slot)


func _local_hero_names() -> Array:
	var names: Array = []
	for slot in local_slot_count:
		names.append(String(hero_for_slot(slot)))
	return names


# --- roster replication -------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		## The newcomer needs the full picture; everyone else only needs the delta, which
		## arrives when the newcomer announces itself below.
		_receive_roster.rpc_id(peer_id, _serialise_roster(), GameState.world_seed)
		## Joining a match already in progress is the normal case, not the exception -- someone
		## is always the last to sit down. Handing the newcomer the seed makes it build the same
		## world the others are already standing in, and the roster broadcast that follows its
		## announcement drops everyone's bodies into it.
		if GameState.phase == GameState.Phase.PLAYING:
			_begin_match.rpc_id(peer_id, GameState.world_seed)
	connection_changed.emit()


func _on_peer_disconnected(peer_id: int) -> void:
	PlayerRegistry.remove_peer(peer_id)
	connection_changed.emit()


func _on_connected_to_server() -> void:
	_announce_local_players.rpc_id(1, local_slot_count, _local_hero_names())
	connection_changed.emit()


func _on_connection_failed() -> void:
	mode = Mode.OFFLINE
	join_failed.emit("could not reach host")
	connection_changed.emit()


func _on_server_disconnected() -> void:
	_reset()
	join_failed.emit("host closed the game")
	connection_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _announce_local_players(slots: int, heroes: Array) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var count := clampi(slots, 1, PlayerRegistry.MAX_LOCAL_SLOTS)
	for slot in count:
		var pid := PlayerRegistry.make_pid(peer_id, slot)
		## Whoever they picked, as long as it is a hero this build knows about. Two players may
		## pick the same one.
		var hero := StringName(str(heroes[slot])) if slot < heroes.size() else &""
		if not ArchetypeDB.has(hero):
			hero = ArchetypeDB.default_for_slot(PlayerRegistry.roster.size())
		PlayerRegistry.add_entry(pid, hero)
	_receive_roster.rpc(_serialise_roster(), GameState.world_seed)
	connection_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_roster(entries: Array, world_seed: int) -> void:
	PlayerRegistry.roster.clear()
	for entry: Dictionary in entries:
		PlayerRegistry.add_entry(entry["pid"], StringName(entry["archetype"]), entry["name"])
	if world_seed != 0 and GameState.world_seed != world_seed:
		GameState.reset_for_match(world_seed)
	connection_changed.emit()


func _serialise_roster() -> Array:
	var out: Array = []
	for pid: int in PlayerRegistry.roster:
		var entry: Dictionary = PlayerRegistry.roster[pid]
		out.append({"pid": pid, "archetype": String(entry["archetype"]), "name": entry["name"]})
	return out


func choose_archetype(pid: int, archetype: StringName) -> void:
	_set_archetype.rpc_id(1, pid, String(archetype))
	if is_host():
		_set_archetype(pid, String(archetype))


@rpc("any_peer", "call_local", "reliable")
func _set_archetype(pid: int, archetype: String) -> void:
	if not is_host() or not PlayerRegistry.roster.has(pid):
		return
	PlayerRegistry.roster[pid]["archetype"] = StringName(archetype)
	_receive_roster.rpc(_serialise_roster(), GameState.world_seed)
	PlayerRegistry.roster_changed.emit()


# --- match start ---------------------------------------------------------------------------

## Host-only. The seed is the entire world transfer: every peer generates the same 16 chunks
## from it rather than receiving any geometry.
func start_match(world_seed: int = 0) -> void:
	if not is_host():
		return
	var chosen := world_seed if world_seed != 0 else GameState.roll_seed()
	if is_networked():
		_begin_match.rpc(chosen)
	_begin_match(chosen)


@rpc("authority", "call_remote", "reliable")
func _begin_match(world_seed: int) -> void:
	GameState.reset_for_match(world_seed)
	GameState.phase = GameState.Phase.PLAYING
	match_started.emit(world_seed)

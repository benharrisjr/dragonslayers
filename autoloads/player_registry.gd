extends Node

## Who is playing, and which body belongs to them.
##
## A player is identified by (peer_id, local_slot) rather than by peer alone, because one
## machine may be driving up to four split-screen players. Those two numbers are folded into a
## single `pid` so the rest of the game -- spawners, HUDs, targeting -- can treat a player as
## one opaque id and never think about the distinction again.

signal roster_changed
signal player_spawned(pid: int)
signal player_despawned(pid: int)

const MAX_LOCAL_SLOTS := 4
## Enough headroom for the four local slots without ever colliding between peers.
const SLOT_STRIDE := 16

## pid -> {"peer": int, "slot": int, "archetype": StringName, "name": String}
var roster: Dictionary = {}
## pid -> PlayerCharacter, only for players actually in the world.
var bodies: Dictionary = {}


func _ready() -> void:
	## The per-player input actions live in code, not project.godot, so they have to exist
	## before anything -- a match, a test, the playtest -- reads or presses one.
	PlayerBindings.reapply()


static func make_pid(peer_id: int, slot: int) -> int:
	return peer_id * SLOT_STRIDE + slot


static func peer_of(pid: int) -> int:
	return pid / SLOT_STRIDE


static func slot_of(pid: int) -> int:
	return pid % SLOT_STRIDE


func add_entry(pid: int, archetype: StringName, display_name: String = "") -> void:
	roster[pid] = {
		"peer": peer_of(pid),
		"slot": slot_of(pid),
		"archetype": archetype,
		"name": display_name if display_name else "P%d" % (roster.size() + 1),
	}
	roster_changed.emit()


func remove_peer(peer_id: int) -> void:
	for pid: int in roster.keys():
		if peer_of(pid) == peer_id:
			roster.erase(pid)
			despawn(pid)
	roster_changed.emit()


func clear() -> void:
	roster.clear()
	bodies.clear()
	roster_changed.emit()


func register_body(pid: int, body: Node) -> void:
	bodies[pid] = body
	player_spawned.emit(pid)


func despawn(pid: int) -> void:
	if bodies.erase(pid):
		player_despawned.emit(pid)


func body_of(pid: int) -> Node:
	var body: Node = bodies.get(pid)
	return body if is_instance_valid(body) else null


func archetype_of(pid: int) -> StringName:
	return roster.get(pid, {}).get("archetype", &"knight")


func name_of(pid: int) -> String:
	return roster.get(pid, {}).get("name", "P?")


## The players this machine draws viewports for. Remote players exist in the world but are not
## split-screen panes, which is the whole distinction between local slots and peers.
func local_pids() -> Array[int]:
	var out: Array[int] = []
	var me := NetworkManager.local_peer_id()
	for pid: int in roster:
		if peer_of(pid) == me:
			out.append(pid)
	out.sort()
	return out


func all_pids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in roster:
		out.append(pid)
	out.sort()
	return out


## Defensive against freed nodes rather than trusting callers to deregister: monsters poll this
## every fraction of a second, and one stale entry would spam errors from inside physics.
func living_bodies() -> Array:
	var out: Array = []
	for pid: int in bodies.keys():
		if not is_instance_valid(bodies[pid]):
			bodies.erase(pid)
			continue
		var body: PlayerCharacter = bodies[pid]
		if not body.is_dead:
			out.append(body)
	return out

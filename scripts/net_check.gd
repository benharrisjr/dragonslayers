class_name NetCheck
extends Node

## Prints what this peer thinks the world is, so a host and a client can be compared.
##
##   Godot --path . --headless -- --host --slots=1 --netcheck   # window one
##   Godot --path . --headless -- --join=127.0.0.1 --netcheck   # window two
##
## Since the map is generated from a broadcast seed rather than transmitted, "did the world
## replicate" is really "did both machines derive the same thing" -- so this reports a
## fingerprint of the generated world rather than trying to diff geometry.

var main: Node
## Seconds to wait before reporting. Set from --netcheck=N so a host can be told to outlive the
## client that is measuring it -- otherwise the client reports into a closed socket and its own
## roster reads as empty for reasons that have nothing to do with replication.
var report_delay: float = 6.0

var _elapsed: float = 0.0
var _done: bool = false
var _prodded: bool = false


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	## A couple of seconds before reporting, the host does to every player the things only a
	## host may do -- a hit, and a piece of gear dropped at their feet -- so the reports show
	## whether those reach players that another machine owns.
	if not _prodded and _elapsed > report_delay - 2.5 and NetworkManager.is_host():
		_prodded = true
		_prod_players()
	if _elapsed < report_delay:
		return
	_done = true
	_report()
	## Stay alive a moment so the other side is not left talking to a closed socket mid-report.
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


func _report() -> void:
	var role := "HOST" if NetworkManager.is_host() else "CLIENT"
	var world: GameWorld = main.world
	if world == null:
		print("%s: no world built" % role)
		return

	var monsters := get_tree().get_nodes_in_group("monsters").size()
	var chests := get_tree().get_nodes_in_group("chests").size()
	## A fingerprint of the actual generated terrain, not just the biome list -- if the two
	## peers diverged in the heightmap, the layout alone would not show it.
	var fingerprint := 0
	for chunk in world.chunks:
		fingerprint = hash([fingerprint, chunk.biome.id, chunk.heights, chunk.terrain.slopes])

	print("%s seed=%d peers=%d players=%d monsters=%d chests=%d dragon=%s terrain=%d" % [
		role, GameState.world_seed, PlayerRegistry.roster.size(),
		PlayerRegistry.bodies.size(), monsters, chests,
		"yes" if world.dragon != null else "no", fingerprint])
	for pid in PlayerRegistry.all_pids():
		var body := PlayerRegistry.body_of(pid) as PlayerCharacter
		if body == null:
			print("   %s player %d has no body" % [role, pid])
			continue
		print("   %s player %d at %s hp=%d/%d gear=%s" % [role, pid,
				body.global_position.snapped(Vector3.ONE * 0.1), body.health, body.max_health,
				",".join(body.gear)])


func _prod_players() -> void:
	for pid in PlayerRegistry.all_pids():
		var body := PlayerRegistry.body_of(pid) as PlayerCharacter
		if body == null:
			continue
		body.take_damage(3, body.global_position + Vector3(0, 0, -2), 0.0, 0.0)
		var chunk := Chunk.containing(get_tree(), body.global_position)
		if chunk != null:
			chunk.drop_item(ItemDB.FEATHER, body.global_position + Vector3.UP * 0.5)

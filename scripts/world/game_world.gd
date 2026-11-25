class_name GameWorld
extends Node3D

## Builds the whole map from the seed and puts everybody in it.
##
## No geometry is ever sent between peers. The host broadcasts one integer; each machine runs
## the same generator and ends up with byte-identical terrain, the same monsters in the same
## places with the same node names, and the same chests. Node paths therefore match everywhere,
## which is what lets combat RPCs address objects directly.

signal world_built

## Radius of the ring the party spawns in. Kept under one tile so that a spawn point cleared by
## Chunk.ground_spawn stays clear for everyone standing around it.
const PLAYER_SPAWN_SPREAD := 1.8
## The colour grade laid over the scene (1.0 = untouched).
const SATURATION := 1.3
const CONTRAST := 1.06

var chunks: Array[Chunk] = []
var layout: Array[StringName] = []
## Tier of each chunk (WorldGenerator.Tier), row-major like the layout.
var tiers: PackedInt32Array
var dragon: Dragon
## The eight dungeons, beside the map, in Dungeon.IDS order.
var dungeons: Array[Dungeon] = []
## The river's plan (WorldGenerator._plan_river): which chunks it runs through, and how.
var river: Dictionary = {}
## The time of day, and everything that goes with it.
var day_night: DayNight
## The worn paths joining the map's slopes.
var paths: PathNetwork

var _players_root: Node3D
## Only the chunks near the players on this machine are drawn, plus the mountain, which is
## always there on the horizon. True draws everything (the overview capture).
var draw_all: bool = false
var _drawn: Dictionary = {}


## Where short-lived world effects (projectiles, fire patches) are parented. The match's root
## node joins this group; the fallback keeps scenes run on their own (the tests) working.
const EFFECTS_GROUP := &"effects_root"

## The GameWorld a node is part of, however deep it sits; null outside one.
static func of(node: Node) -> GameWorld:
	var at := node.get_parent()
	while at != null and not at is GameWorld:
		at = at.get_parent()
	return at as GameWorld


static func effects_root(tree: SceneTree) -> Node:
	var found := tree.get_first_node_in_group(EFFECTS_GROUP)
	return found if found != null else tree.current_scene


func build(world_seed: int) -> void:
	var plan := WorldGenerator.plan(world_seed)
	river = plan["river"]
	layout.assign(plan["biomes"])
	tiers = plan["tiers"]
	## Before any chunk is built: the season decides their colours, trees and ground cover.
	Season.current = Season.roll(world_seed)
	_build_environment()

	## Every chunk's ground first, then the paths over all of it, then what stands on it.
	var contexts: Array[Dictionary] = []
	var generators: Array[RandomNumberGenerator] = []
	var terrains: Array[TerrainData] = []
	for index in layout.size():
		var ctx := WorldGenerator.context(tiers, index, plan["river"], plan["entrances"],
				plan["shape_seed"])
		## The whole map's biomes, so the ground's colours can blend across the borders.
		ctx["layout"] = layout
		var rng := GameState.chunk_rng(index)
		ctx["terrain"] = WorldGenerator.heightmap(BiomeLibrary.get_biome(layout[index]), rng, ctx)
		contexts.append(ctx)
		generators.append(rng)
		terrains.append(ctx["terrain"])
	paths = PathNetwork.lay(terrains, layout, plan["shape_seed"])
	var torches := paths.torches()
	var ground := ChunkMesher.make_material()
	ground.set_shader_parameter("paths", ImageTexture.create_from_image(paths.image()))
	for index in layout.size():
		var chunk := Chunk.new()
		add_child(chunk)
		contexts[index]["torches"] = torches.get(index, [])
		chunk.build(index, layout[index], generators[index], contexts[index])
		chunks.append(chunk)

	_place_dragon()
	_build_dungeons()

	## Built after the chunks; it stands directly against the outer rims, whatever tier they are.
	var boundary := WorldBoundary.new()
	add_child(boundary)
	boundary.build()
	day_night.settle()

	_start_season()
	_prewarm_effects()

	_players_root = Node3D.new()
	_players_root.name = "Players"
	add_child(_players_root)
	_spawn_players()
	_resume_progress()
	world_built.emit()


## A spot beside one of the river's sights, for --goto and the captures: the first "bridge", the
## highest "waterfall", the "pond" at its source, a stretch of open "river" (on the water itself)
## or the "bank" beside one. Upstream first, in the order the river runs. Vector3.INF if there is no river.
func river_landmark(kind: String) -> Vector3:
	var cells: Array = river.get("cells", [])
	var best := Vector3.INF
	var best_tile := Vector2i.ZERO
	var best_chunk: Chunk = null
	for cell: int in cells:
		var chunk := chunks[cell]
		## Open river is lowland river: on the mountain it is all ponds and falls between
		## narrow terraces, with nowhere level to stand and watch it from.
		if (kind == "river" or kind == "bank") and layout[cell] == &"mountain":
			continue
		var terrain := chunk.terrain
		var size := terrain.size
		match kind:
			"bridge":
				if not terrain.bridges.is_empty():
					var spec: Dictionary = terrain.bridges[0]
					var from: Vector2i = spec["from"]
					return chunk.global_position + Vector3(from.x * 2.0 - 3.0,
							int(spec["level"]) * ChunkMesher.STEP_HEIGHT, from.y * 2.0 - 3.0)
			"pond":
				var pond: Vector2 = (river["parts"][cell] as Dictionary).get("pond", Vector2.INF)
				if pond != Vector2.INF:
					return _dry_beside(chunk, Vector2i(pond))
			_:
				for z in size:
					for x in size:
						if not terrain.is_water(x, z) or terrain.is_bridge(x, z):
							continue
						var wanted := terrain.level(x, z) == terrain.base_level - 1
						if kind == "waterfall":
							wanted = RiverBuilder.is_below_fall(terrain, x, z)
						elif kind == "bigfall":
							## The foot of a fall of five levels or more: a cliff between tiers.
							wanted = false
							for side in 4:
								var above := RiverBuilder.bed_beyond(terrain, x, z, side)
								wanted = wanted or (not is_nan(above) and above - terrain.level(x, z) >= 5)
						if not wanted:
							continue
						var at := chunk.global_position + Vector3((x + 0.5) * 2.0,
								(terrain.level(x, z) + 1) * ChunkMesher.STEP_HEIGHT, (z + 0.5) * 2.0)
						if kind == "river":
							return at
						if kind == "bank":
							return _dry_beside(chunk, Vector2i(x, z))
						if best == Vector3.INF or at.y > best.y:
							best = at
							best_tile = Vector2i(x, z)
							best_chunk = chunk
	## Somewhere dry to stand and look at it from, not the water itself.
	return _dry_beside(best_chunk, best_tile) if best_chunk != null else best


## The nearest dry, flat tile to `tile` in `chunk`, on top of it.
func _dry_beside(chunk: Chunk, tile: Vector2i) -> Vector3:
	var terrain := chunk.terrain
	for reach in range(1, 10):
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var x := tile.x + dx
				var z := tile.y + dz
				if terrain.in_bounds(x, z) and not terrain.is_water(x, z) \
						and not terrain.is_hole(x, z) and not terrain.is_slope(x, z):
					return chunk.global_position + Vector3((x + 0.5) * 2.0,
							terrain.level(x, z) * ChunkMesher.STEP_HEIGHT, (z + 0.5) * 2.0)
	return Vector3.INF


## Winter's tracks in the snow and summer's grass bending round whoever walks through it are
## both driven from here, every frame. The ground material is shared between matches, so the
## snow is switched off as well as on.
var snow: SnowTrails


## The ground's material outlives the match: it must not keep this one's paths.
func _exit_tree() -> void:
	ChunkMesher.make_material().set_shader_parameter("paths", null)


func _start_season() -> void:
	var ground := ChunkMesher.make_material()
	ground.set_shader_parameter("snow", false)
	if Season.current == Season.Kind.WINTER:
		snow = SnowTrails.new()
		add_child(snow)
		snow.attach(ground)


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	_tick_autosave(delta)
	_update_drawn_chunks()
	match Season.current:
		Season.Kind.SUMMER:
			GrassField.apply_pushers(GrassField.material(), GrassField.collect_pushers(get_tree()))
		Season.Kind.FALL:
			LeafField.apply_pushers(GrassField.collect_pushers(get_tree()))


func _physics_process(_delta: float) -> void:
	if Season.current == Season.Kind.FALL and is_inside_tree():
		LeafField.kick_from_bodies(get_tree())


## Called before this world is freed. queue_free() is deferred, so without this the registry
## still reports the old bodies as valid while the new world is deciding what to spawn.
func teardown() -> void:
	if SaveManager.world_flush == save_progress:
		SaveManager.world_flush = Callable()
	if PlayerRegistry.roster_changed.is_connected(reconcile_players):
		PlayerRegistry.roster_changed.disconnect(reconcile_players)
	for pid in PlayerRegistry.all_pids():
		PlayerRegistry.despawn(pid)
	PlayerRegistry.bodies.clear()


# --- saved worlds -------------------------------------------------------------------------

## Seconds between autosaves of a saved world.
const AUTOSAVE_EVERY := 120.0
var _autosave_left: float = AUTOSAVE_EVERY
## Saved kits that arrived for a player whose body this machine has not built yet (the roster
## and the world can reach a client in either order); applied when the body is spawned.
var _pending_restore: Dictionary = {}


## The chunk whose square of the map `point` lies in, or null off the map.
func chunk_containing(point: Vector3) -> Chunk:
	var cell := Vector2i((Vector2(point.x, point.z) / WorldGenerator.CHUNK_SIZE).floor())
	if cell.x < 0 or cell.y < 0 or cell.x >= WorldGenerator.GRID or cell.y >= WorldGenerator.GRID:
		return null
	var index := cell.y * WorldGenerator.GRID + cell.x
	return chunks[index] if index < chunks.size() else null


## Picks up where the world left off. The host lays its save (if this is a saved world) over the
## fresh build; a client asks the host what has changed so far -- which is also how someone
## joining mid-match sees the chests already opened, the party's gold and everyone's kit.
func _resume_progress() -> void:
	if NetworkManager.is_host():
		if GameState.world != null:
			WorldPersistence.apply_world(self, GameState.world)
			SaveManager.world_flush = save_progress
	else:
		_request_catch_up.rpc_id(1)


## Host: writes the match into its save and the save to disk. A no-op in an unsaved match.
func save_progress() -> void:
	if not NetworkManager.is_host() or GameState.world == null or not is_inside_tree():
		return
	WorldPersistence.capture(self, GameState.world)
	SaveManager.save_world(GameState.world)
	_autosave_left = AUTOSAVE_EVERY


func _tick_autosave(delta: float) -> void:
	if GameState.world == null or not NetworkManager.is_host() \
			or GameState.phase != GameState.Phase.PLAYING or get_tree().paused:
		return
	GameState.world.play_time_seconds += delta
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		save_progress()


@rpc("any_peer", "call_remote", "reliable")
func _request_catch_up() -> void:
	if not NetworkManager.is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	var opened := PackedStringArray()
	for node in get_tree().get_nodes_in_group("chests"):
		var chest := node as TreasureChest
		if chest != null and chest.is_open:
			opened.append(String(chest.name))
	_net_catch_up.rpc_id(peer, opened, GameState.gold, DungeonEntrance.revealed_names(get_tree()),
			unlocked_chests(), day_night.time)
	for pid: int in PlayerRegistry.bodies:
		var body := PlayerRegistry.body_of(pid) as PlayerCharacter
		if body != null:
			_net_restore_player.rpc_id(peer, pid, body.save_state())


@rpc("authority", "call_remote", "reliable")
func _net_catch_up(opened: PackedStringArray, gold: int, revealed: PackedStringArray = [],
		unlocked: PackedStringArray = [], time_of_day: float = DayNight.MORNING) -> void:
	day_night.time = time_of_day
	WorldPersistence.open_chests(get_tree(), opened)
	GameState.gold = gold
	DungeonEntrance.reveal_named(get_tree(), revealed)
	WorldPersistence.unlock_chests(get_tree(), unlocked)


## Big chests whose guardian has been beaten but which are still shut.
func unlocked_chests() -> PackedStringArray:
	var names := PackedStringArray()
	for dungeon in dungeons:
		if dungeon.big_chest != null and not dungeon.big_chest.locked and not dungeon.big_chest.is_open:
			names.append(String(dungeon.big_chest.name))
	return names


## Host: someone has just appeared whose hero this world remembers. Sent once the roster that
## brings them has gone out, so the other machines have built the body it is addressed to.
func _broadcast_restore(pid: int, state: Dictionary) -> void:
	if not is_inside_tree():
		return
	if NetworkManager.is_networked():
		_net_restore_player.rpc(pid, state)
	_net_restore_player(pid, state)


@rpc("authority", "call_remote", "reliable")
func _net_restore_player(pid: int, state: Dictionary) -> void:
	var body := PlayerRegistry.body_of(pid) as PlayerCharacter
	if body == null:
		_pending_restore[pid] = state
		return
	body.restore_state(state)


## Every dungeon scene, instanced on every machine and placed off the edge of the map.
func _build_dungeons() -> void:
	var root := Node3D.new()
	root.name = "Dungeons"
	add_child(root)
	for index in Dungeon.IDS.size():
		var id := Dungeon.IDS[index]
		var packed := load(Dungeon.scene_path(id)) as PackedScene
		if packed == null:
			push_warning("No dungeon scene for %s" % id)
			continue
		var dungeon := packed.instantiate() as Dungeon
		if dungeon == null:
			push_warning("%s is not a Dungeon scene" % Dungeon.scene_path(id))
			continue
		dungeon.dungeon_id = id
		root.add_child(dungeon)
		dungeon.build(index)
		dungeons.append(dungeon)


## World position of the foot of the mountain's road up, on the rim walkway.
func ascent_foot() -> Vector3:
	var mountain := chunk_of_biome(&"mountain")
	if mountain == null:
		return Vector3.ZERO
	var side: int = WorldGenerator.context(tiers, mountain.index)["ascent_side"]
	var foot := WorldGenerator.ascent_foot_tile(side, WorldGenerator.CHUNK_TILES)
	var tile := WorldGenerator._from_side(WorldGenerator.CHUNK_TILES, side, foot.z, foot.y)
	return mountain.global_position + mountain._tile_centre(tile.x, tile.y)


## Unit vector pointing up the ascent ramp, from the rim towards the summit.
func ascent_direction() -> Vector3:
	var mountain := chunk_of_biome(&"mountain")
	if mountain == null:
		return Vector3.FORWARD
	var side: int = WorldGenerator.context(tiers, mountain.index)["ascent_side"]
	return -Vector3(ChunkMesher.NEIGHBOUR_DX[side], 0.0, ChunkMesher.NEIGHBOUR_DZ[side])


## Draws the chunk each local player stands in and the eight round it, and the mountain; the
## rest of the map is not drawn at all. A chunk is 128 m across, further than the camera sees
## on the ground, so the next ring out is never in view -- except the mountain, which stands
## tall enough to be seen from anywhere and is the thing everyone is heading for.
## Only drawing: everything in a hidden chunk keeps running, and its skeletons stay drawn (they
## can follow a player out of it).
func _update_drawn_chunks() -> void:
	var wanted := {}
	var mountain := layout.find(&"mountain")
	if mountain >= 0:
		wanted[mountain] = true
	var anyone := false
	for pid in PlayerRegistry.local_pids():
		var body := PlayerRegistry.body_of(pid) as Node3D
		if body == null:
			continue
		anyone = true
		var cell := Vector2i((Vector2(body.global_position.x, body.global_position.z)
				/ WorldGenerator.CHUNK_SIZE).floor())
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var at := cell + Vector2i(dx, dz)
				if at.x >= 0 and at.y >= 0 and at.x < WorldGenerator.GRID and at.y < WorldGenerator.GRID:
					wanted[at.y * WorldGenerator.GRID + at.x] = true
	for index in chunks.size():
		var on := draw_all or not anyone or wanted.has(index)
		if _drawn.get(index, not on) != on:
			_drawn[index] = on
			chunks[index].set_drawn(on)
	## A dungeon is drawn, lights and all, only while someone here is down in it.
	for dungeon in dungeons:
		var inside := draw_all
		for pid in PlayerRegistry.local_pids():
			var body := PlayerRegistry.body_of(pid) as Node3D
			if body != null and dungeon.bounds.has_point(body.global_position):
				inside = true
		if dungeon.visible != inside:
			dungeon.visible = inside


## How many chunks are being drawn right now.
func drawn_chunk_count() -> int:
	var count := 0
	for index in chunks.size():
		if _drawn.get(index, true):
			count += 1
	return count


func chunk_of_biome(biome_id: StringName) -> Chunk:
	for chunk in chunks:
		if chunk.biome.id == biome_id:
			return chunk
	return null


## The dragon stands on the highest tile of the mountain chunk, which is also where the arena
## and the long fall back down will go in Milestone 4.
func _place_dragon() -> void:
	var mountain := chunk_of_biome(&"mountain")
	if mountain == null:
		return
	## The centre of the flat summit platform, not merely the highest tile: the arena is carved
	## by the generator and the whole fight -- engagement, reset, where fire lands -- is measured
	## from its middle.
	var centre := mountain.centre_tile_position()
	dragon = Dragon.new()
	add_child(dragon)
	dragon.global_position = centre + Vector3.UP * 0.5
	dragon.configure(centre, WorldGenerator.arena_radius())
	## Facing the middle of the map, so it is looking at the party as they climb.
	dragon.look_at_from_position(dragon.global_position,
			Vector3(WorldGenerator.map_centre().x, dragon.global_position.y,
					WorldGenerator.map_centre().z), Vector3.UP)
	dragon.reset_physics_interpolation()
	dragon.defeated.connect(_on_dragon_defeated)


## Killing the dragon is how the game is won, so this is the one death in the game that ends
## the match rather than dropping loot.
func _on_dragon_defeated() -> void:
	GameState.phase = GameState.Phase.VICTORY
	## Counted per save slot; the counter drives the "Veteran Slayer" achievement.
	SaveManager.add_stat(&"dragons_slain")
	Achievements.grant(&"dragon_slain")
	Achievements.evaluate()
	SaveManager.save_game()
	## A saved world remembers the kill; the dragon itself is back on the next load.
	if GameState.world != null and NetworkManager.is_host():
		GameState.world.dragons_slain += 1
		save_progress()


## The party starts together in town: it is the only chunk with no monsters, and starting at the
## shop is the shape the whole run hangs off.
func _spawn_players() -> void:
	reconcile_players()
	## Re-run whenever the roster changes, so someone joining a match already in progress walks
	## into the world instead of watching an empty lobby -- and so a player who quits leaves no
	## body behind.
	PlayerRegistry.roster_changed.connect(reconcile_players)


## Brings the bodies in the world into line with the roster. Idempotent, because it runs on
## every roster change on every peer and most of those changes affect nobody.
func reconcile_players() -> void:
	if _players_root == null:
		return
	for pid in PlayerRegistry.all_pids():
		if PlayerRegistry.body_of(pid) == null:
			_spawn_player(pid)
	for pid: int in PlayerRegistry.bodies.keys():
		if not PlayerRegistry.roster.has(pid):
			var body := PlayerRegistry.body_of(pid)
			if body != null:
				body.queue_free()
			PlayerRegistry.despawn(pid)


func _spawn_player(pid: int) -> void:
	var archetype := ArchetypeDB.get_archetype(PlayerRegistry.archetype_of(pid))
	if archetype == null:
		return
	var town := chunk_of_biome(&"town")
	var rng := GameState.chunk_rng(999)
	var origin := town.ground_spawn(rng) if town != null else WorldGenerator.map_centre()

	var player := PlayerCharacter.new()
	player.name = "Player_%d" % pid
	Chunk._add_body_shape(player, 0.42, 1.6)
	_players_root.add_child(player)
	## Spread by slot rather than by arrival order, so the same pid lands in the same spot on
	## every peer even if the roster arrived in a different order.
	## By position in the sorted roster, which every peer agrees on. The pid itself will not do:
	## two machines' first players can share a remainder and land on the same spot.
	var order := PlayerRegistry.all_pids()
	order.sort()
	var angle := TAU * float(maxi(0, order.find(pid))) / 8.0
	player.global_position = origin + Vector3(
		cos(angle) * PLAYER_SPAWN_SPREAD, 1.0, sin(angle) * PLAYER_SPAWN_SPREAD)
	player.reset_physics_interpolation()
	player.configure(pid, archetype)
	_add_player_sync(player)
	if _pending_restore.has(pid):
		player.restore_state(_pending_restore[pid])
		_pending_restore.erase(pid)
	elif NetworkManager.is_host():
		var saved := WorldPersistence.character_for(GameState.world, archetype.id)
		if not saved.is_empty():
			_broadcast_restore.call_deferred(pid, saved)


## Position and facing are pushed by whichever peer owns the player. Built in code rather than
## authored in a scene because the players themselves are built in code, and a synchroniser
## configured anywhere else would have to guess at the node path.
func _add_player_sync(player: PlayerCharacter) -> void:
	if not NetworkManager.is_networked():
		return
	var config := SceneReplicationConfig.new()
	## `blocking` rides along because the host is the one that applies a block when a hit lands.
	## `fidget` so a player left exercising is seen exercising everywhere.
	## `charge_level` so everyone sees a charge building -- the tell before a spin or a flurry.
	for property in [".:position", ".:rotation", ".:velocity", ".:blocking", ".:fidget",
			".:charge_level"]:
		config.add_property(NodePath(property))
		config.property_set_replication_mode(NodePath(property),
				SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.replication_interval = 0.033
	player.add_child(sync)
	sync.set_multiplayer_authority(PlayerRegistry.peer_of(player.pid))


## Draws one of every runtime-built effect once, out of sight, during the load.
##
## The first time a material reaches the screen its shader is compiled, and that compile is a
## stall of a hundred milliseconds or more. Left to happen naturally it lands on the frame the
## dragon first breathes fire -- a hitch precisely when the fight starts. Paying it here moves
## it into a moment nobody is playing through.
func _prewarm_effects() -> void:
	var hidden := Vector3(0.0, Combatant.KILL_HEIGHT - 200.0, 0.0)

	var fire := FirePatch.new()
	add_child(fire)
	fire.ignite(hidden, 1.0)

	var bolt := MeshInstance3D.new()
	bolt.mesh = BoxMesh.new()
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color.WHITE
	glow.emission_enabled = true
	glow.emission = Color.WHITE
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt.material_override = glow
	bolt.position = hidden
	add_child(bolt)

	## Scenery and gear. Every distinct prop model in this map, and every item, drawn once at a
	## speck of its size right where the party is standing. Walking towards a chunk used to
	## stall for a seventh of a second each time a kind of tree or rock came into view for the
	## first time; this pays for all of them during the load instead. Unlike the fire above they
	## have to be in front of a camera to count, so they sit at the spawn, far too small to see.
	var warm := Node3D.new()
	warm.name = "Prewarm"
	add_child(warm)
	var town := chunk_of_biome(&"town")
	warm.global_position = (town.centre_tile_position() if town != null
			else WorldGenerator.map_centre()) + Vector3.UP * 1.0
	var seen := {}
	for biome_id in layout:
		for prop: Dictionary in BiomeLibrary.get_biome(biome_id).props:
			if seen.has(prop["path"]):
				continue
			seen[prop["path"]] = true
			var packed := load(prop["path"]) as PackedScene
			if packed != null:
				var model := packed.instantiate() as Node3D
				model.scale = Vector3.ONE * 0.002
				warm.add_child(model)
	## Skeletons too: a skinned model is a different shader from a tree, and the first one to
	## walk into draw range paid for it mid-stride.
	for monster_id: StringName in MonsterDB.all_ids():
		var packed := load(MonsterDB.get_monster(monster_id).model_path) as PackedScene
		if packed != null:
			var model := packed.instantiate() as Node3D
			model.scale = Vector3.ONE * 0.002
			warm.add_child(model)
	for item in ItemDB.ORDER:
		var gear := ItemDB.build_model(item)
		gear.scale = Vector3.ONE * 0.002
		warm.add_child(gear)

	## A few frames, so the panes' cameras exist and have drawn everything at least once.
	for _frame in 6:
		await get_tree().process_frame
	fire.queue_free()
	bolt.queue_free()
	warm.queue_free()


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_material.sky_horizon_color = Color(0.72, 0.82, 0.9)
	sky_material.ground_bottom_color = Color(0.28, 0.3, 0.28)
	sky_material.ground_horizon_color = Color(0.6, 0.62, 0.55)
	sky.sky_material = sky_material
	environment.sky = sky
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	## A flat colour rather than the sky itself: it changes all day long, and reading it off the
	## sky each time would mean working the sky's light out again.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	## Distant chunks fade rather than popping at the far plane; the map is 256 m across and the
	## camera can see a long way from the mountain.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.72, 0.8, 0.88)
	## Thinned to match the larger map: at the old density the far side of a 512 m world
	## disappeared into haze entirely, including the mountain the party is walking towards.
	environment.fog_density = 0.0009
	## A colour grade over the whole scene: the art kits' flat palettes read a little washed out
	## under the sky light and haze, so saturation is pushed up and contrast a touch with it.
	## Applied after tonemapping, so it costs one pass and changes no lighting.
	environment.adjustment_enabled = true
	environment.adjustment_saturation = SATURATION
	environment.adjustment_contrast = CONTRAST

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	day_night = DayNight.new()
	add_child(day_night)
	day_night.setup(environment, sky_material)

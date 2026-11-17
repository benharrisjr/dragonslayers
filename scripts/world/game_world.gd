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

var chunks: Array[Chunk] = []
var layout: Array[StringName] = []
## Tier of each chunk (WorldGenerator.Tier), row-major like the layout.
var tiers: PackedInt32Array
var dragon: Dragon

var _players_root: Node3D


## Where short-lived world effects (projectiles, fire patches) are parented. The match's root
## node joins this group; the fallback keeps scenes run on their own (the tests) working.
const EFFECTS_GROUP := &"effects_root"

static func effects_root(tree: SceneTree) -> Node:
	var found := tree.get_first_node_in_group(EFFECTS_GROUP)
	return found if found != null else tree.current_scene


func build(world_seed: int) -> void:
	var plan := WorldGenerator.plan(world_seed)
	layout.assign(plan["biomes"])
	tiers = plan["tiers"]
	_build_environment()

	for index in layout.size():
		var chunk := Chunk.new()
		add_child(chunk)
		chunk.build(index, layout[index], GameState.chunk_rng(index),
				WorldGenerator.context(tiers, index))
		chunks.append(chunk)

	_place_dragon()

	## Built after the chunks; it stands directly against the outer rims, whatever tier they are.
	var boundary := WorldBoundary.new()
	add_child(boundary)
	boundary.build()

	_prewarm_effects()

	_players_root = Node3D.new()
	_players_root.name = "Players"
	add_child(_players_root)
	_spawn_players()
	world_built.emit()


## Called before this world is freed. queue_free() is deferred, so without this the registry
## still reports the old bodies as valid while the new world is deciding what to spawn.
func teardown() -> void:
	if PlayerRegistry.roster_changed.is_connected(reconcile_players):
		PlayerRegistry.roster_changed.disconnect(reconcile_players)
	for pid in PlayerRegistry.all_pids():
		PlayerRegistry.despawn(pid)
	PlayerRegistry.bodies.clear()


## World position of the bottom of the mountain's ascent ramp, on the rim walkway.
func ascent_foot() -> Vector3:
	var mountain := chunk_of_biome(&"mountain")
	if mountain == null:
		return Vector3.ZERO
	var side: int = WorldGenerator.context(tiers, mountain.index)["ascent_side"]
	var tile := WorldGenerator._from_side(WorldGenerator.CHUNK_TILES, side,
			WorldGenerator.BORDER - 2, WorldGenerator.CHUNK_TILES / 2)
	return mountain.global_position + mountain._tile_centre(tile.x, tile.y)


## Unit vector pointing up the ascent ramp, from the rim towards the summit.
func ascent_direction() -> Vector3:
	var mountain := chunk_of_biome(&"mountain")
	if mountain == null:
		return Vector3.FORWARD
	var side: int = WorldGenerator.context(tiers, mountain.index)["ascent_side"]
	return -Vector3(ChunkMesher.NEIGHBOUR_DX[side], 0.0, ChunkMesher.NEIGHBOUR_DZ[side])


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


## Position and facing are pushed by whichever peer owns the player. Built in code rather than
## authored in a scene because the players themselves are built in code, and a synchroniser
## configured anywhere else would have to guess at the node path.
func _add_player_sync(player: PlayerCharacter) -> void:
	if not NetworkManager.is_networked():
		return
	var config := SceneReplicationConfig.new()
	## `blocking` rides along because the host is the one that applies a block when a hit lands.
	for property in [".:position", ".:rotation", ".:velocity", ".:blocking"]:
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
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	## Steep enough that the plateau cliffs cast readable shadows -- seeing the edge is what
	## makes a ledge a hazard rather than a surprise.
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	## Shadows only near the action. The default 100 m covers most of the visible map from a
	## hilltop, and rendering the whole thing into the shadow atlas costs far more than the
	## distant shadows are worth at this art scale.
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)

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
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.6
	## Distant chunks fade rather than popping at the far plane; the map is 256 m across and the
	## camera can see a long way from the mountain.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.72, 0.8, 0.88)
	## Thinned to match the larger map: at the old density the far side of a 512 m world
	## disappeared into haze entirely, including the mountain the party is walking towards.
	environment.fog_density = 0.0009

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

extends Node

## Headless checks for the parts that are logic rather than pixels: the asset pipeline that has
## to line up before anything can animate, map generation determinism, and the combat maths.
##
##   Godot --path . --headless res://scenes/tests.tscn
##
## Run as a scene rather than with --script, because the autoloads (RigAnimations, AbilityDB,
## ArchetypeDB, MonsterDB) are only instantiated for a real scene run and almost everything
## here depends on them.

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_animation_libraries()
	_test_archetypes()
	_test_monsters()
	_test_dragon_model()
	_test_layout()
	_test_heightmaps()
	_test_mesher()
	_test_combat_math()
	_test_hearts()
	_test_pid_packing()

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s%s" % [label, (" -- " + detail) if detail else ""])


# --- asset pipeline ---------------------------------------------------------------------------

func _test_animation_libraries() -> void:
	print("\n--- animation libraries")
	_check("all eight packs loaded", RigAnimations.library_count() == 8,
			"got %d" % RigAnimations.library_count())
	## These are the exact clips the four archetypes and the skeletons reference. If the
	## animation_library import ever regresses to a plain scene import, this is what catches it.
	for clip in ["general/Idle_A", "general/Hit_A", "general/Death_A",
			"move/Running_A", "move/Jump_Idle", "move/Jump_Land",
			"melee/Melee_1H_Attack_Chop", "melee/Melee_2H_Attack_Chop",
			"melee/Melee_Block_Attack", "melee/Melee_1H_Attack_Slice_Horizontal",
			"melee/Melee_Dualwield_Attack_Slice",
			"ranged/Ranged_Bow_Release", "ranged/Ranged_Magic_Shoot",
			"ranged/Ranged_Magic_Summon", "ranged/Ranged_Magic_Spellcasting",
			"special/Skeletons_Idle", "special/Skeletons_Walking",
			"special/Skeletons_Death", "special/Skeletons_Awaken_Standing"]:
		_check("clip %s" % clip, RigAnimations.has_clip(clip))
	_check("clip lengths are non-zero", RigAnimations.clip_length("general/Idle_A") > 0.0)
	_check("unknown clips report missing", not RigAnimations.has_clip("melee/NotAClip"))


func _test_archetypes() -> void:
	print("\n--- archetypes")
	var expected := {
		&"knight": "Knight.glb", &"shaman": "Barbarian.glb",
		&"archer": "Rogue_Hooded.glb", &"wizard": "Mage.glb",
	}
	for id: StringName in expected:
		var archetype := ArchetypeDB.get_archetype(id)
		_check("%s exists" % id, archetype != null)
		if archetype == null:
			continue
		_check("%s uses %s" % [id, expected[id]], archetype.model_path.ends_with(expected[id]),
				archetype.model_path)
		_check("%s model on disk" % id, ResourceLoader.exists(archetype.model_path))
		_check("%s has a basic attack" % id, archetype.basic_attack != null)
		_check("%s has an ability" % id, archetype.abilities.size() > 0)
		for bone: String in archetype.weapon_paths:
			_check("%s weapon %s on disk" % [id, bone],
					ResourceLoader.exists(archetype.weapon_paths[bone]),
					archetype.weapon_paths[bone])
		for clip in [archetype.idle_anim, archetype.run_anim, archetype.jump_anim,
				archetype.hit_anim, archetype.death_anim, archetype.basic_attack.animation]:
			_check("%s clip %s" % [id, clip], RigAnimations.has_clip(clip))
	_check("slot defaults cover all four",
			ArchetypeDB.default_for_slot(0) == &"knight"
			and ArchetypeDB.default_for_slot(3) == &"wizard")


func _test_monsters() -> void:
	print("\n--- monsters")
	for id: StringName in MonsterDB.all_ids():
		var data := MonsterDB.get_monster(id)
		_check("%s model on disk" % id, ResourceLoader.exists(data.model_path), data.model_path)
		_check("%s knocks back" % id, data.knockback > 0.0)
		for clip in [data.idle_anim, data.walk_anim, data.attack_anim, data.death_anim]:
			_check("%s clip %s" % [id, clip], RigAnimations.has_clip(clip))
	_check("there is a rare monster",
			MonsterDB.get_monster(&"skeleton_mage").is_rare)


func _test_dragon_model() -> void:
	print("\n--- dragon")
	_check("converted glb exists", ResourceLoader.exists(Dragon.MODEL_PATH),
			"run tools/convert_dragon.py")
	if not ResourceLoader.exists(Dragon.MODEL_PATH):
		return
	var instance := (load(Dragon.MODEL_PATH) as PackedScene).instantiate()
	var skeleton := _find_skeleton(instance)
	_check("has a skeleton", skeleton != null)
	if skeleton != null:
		_check("20 bones", skeleton.get_bone_count() == 20,
				"got %d" % skeleton.get_bone_count())
		## Every bone the fight will drive must exist by name, since the attacks address them
		## directly rather than through an authored animation.
		for group: String in Dragon.BONES:
			for bone_name: String in Dragon.BONES[group]:
				_check("bone %s" % bone_name, skeleton.find_bone(bone_name) >= 0)
	var aabb := _combined_aabb(instance)
	_check("stands 5-6 m tall", aabb.size.y > 5.0 and aabb.size.y < 6.5,
			"%.2f m" % aabb.size.y)
	_check("wingspan 12-13 m", aabb.size.x > 12.0 and aabb.size.x < 13.5,
			"%.2f m" % aabb.size.x)
	_check("feet on the origin plane", absf(aabb.position.y) < 0.05,
			"%.3f" % aabb.position.y)
	instance.free()


# --- world generation --------------------------------------------------------------------------

func _test_layout() -> void:
	print("\n--- map layout")
	var counts_ok := true
	var rules_ok := true
	for world_seed in [1, 7, 4242, 99991, 123456789]:
		var cells := WorldGenerator.layout(world_seed)
		if cells.size() != 16:
			counts_ok = false
			continue
		var tally := {}
		for id: StringName in cells:
			tally[id] = tally.get(id, 0) + 1
		for id: StringName in WorldGenerator.COUNTS:
			if tally.get(id, 0) != WorldGenerator.COUNTS[id]:
				counts_ok = false
		## Mountain on an edge and town well away from it; a run that starts next to the boss
		## has no journey in it.
		var mountain := cells.find(&"mountain")
		var town := cells.find(&"town")
		if not WorldGenerator._is_edge(mountain) or WorldGenerator._chebyshev(town, mountain) < 2:
			rules_ok = false
	_check("16 chunks with the exact requested distribution", counts_ok)
	_check("placement rules hold across seeds", rules_ok)
	_check("same seed gives the same layout",
			WorldGenerator.layout(4242) == WorldGenerator.layout(4242))
	_check("different seeds differ",
			WorldGenerator.layout(1) != WorldGenerator.layout(2))


func _test_heightmaps() -> void:
	print("\n--- terrain")
	var biome := BiomeLibrary.get_biome(&"plains")
	var first := WorldGenerator.heightmap(biome, _rng(4242))
	var second := WorldGenerator.heightmap(biome, _rng(4242))
	_check("heightmaps are deterministic", first == second)
	_check("heightmap is the right size",
			first.size() == WorldGenerator.CHUNK_TILES * WorldGenerator.CHUNK_TILES)

	## Chunk rims must be flat and solid or neighbouring chunks would not meet, and the party
	## could not walk between them.
	var tiles := WorldGenerator.CHUNK_TILES
	var rim_ok := true
	for id: StringName in BiomeLibrary.all_ids():
		var heights := WorldGenerator.heightmap(BiomeLibrary.get_biome(id), _rng(77))
		for i in tiles:
			for index in [i, (tiles - 1) * tiles + i, i * tiles, i * tiles + tiles - 1]:
				if heights[index] != 0:
					rim_ok = false
	_check("every biome's rim is level 0", rim_ok)

	var mountain := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"mountain"), _rng(5))
	var peak := 0
	for level in mountain:
		peak = maxi(peak, level)
	_check("the mountain has a summit to climb", peak >= 6, "peak level %d" % peak)

	var pitted := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"temple"), _rng(11))
	var holes := 0
	for level in pitted:
		if level == ChunkMesher.HOLE:
			holes += 1
	_check("pits get carved for players to fall into", holes > 0)


func _test_mesher() -> void:
	print("\n--- mesher")
	var biome := BiomeLibrary.get_biome(&"forest")
	var heights := WorldGenerator.heightmap(biome, _rng(9))
	var mesh := ChunkMesher.build(heights, WorldGenerator.CHUNK_TILES, biome, _rng(9))
	_check("mesh has geometry", mesh != null and mesh.get_surface_count() == 1)
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check("vertices are coloured per biome", colors.size() == vertices.size())
	_check("chunk is one chunk wide",
			mesh.get_aabb().size.x <= WorldGenerator.CHUNK_SIZE + 0.01)
	_check("collision shape builds", mesh.create_trimesh_shape() != null)
	## One step of elevation is a hop; two is not. If this drifts, the platforming changes
	## character without anyone touching the movement code.
	var jump_apex := (10.5 * 10.5) / (2.0 * 24.0)
	_check("one step is jumpable, two is not",
			ChunkMesher.STEP_HEIGHT < jump_apex and ChunkMesher.STEP_HEIGHT * 3.0 > jump_apex,
			"apex %.2f m, step %.2f m" % [jump_apex, ChunkMesher.STEP_HEIGHT])


# --- combat ----------------------------------------------------------------------------------

func _test_combat_math() -> void:
	print("\n--- combat")
	var victim := Combatant.new()
	victim.max_health = 12
	add_child(victim)
	victim.global_position = Vector3(5, 0, 0)

	victim.take_damage(3, Vector3.ZERO, 10.0, 0.5)
	_check("damage lands", victim.health == 9, "health %d" % victim.health)
	_check("knockback pushes away from the source", victim.velocity.x > 0.0,
			str(victim.velocity))
	_check("knockback lifts", victim.velocity.y > 0.0)
	_check("knockback locks out input briefly", victim.knockback_time > 0.0)

	## A hit from exactly on top has no horizontal direction to work with; it must still shove
	## rather than silently swallowing the knockback.
	var overhead := Combatant.new()
	add_child(overhead)
	overhead.take_damage(1, overhead.global_position, 8.0, 0.3)
	_check("a hit from directly above still knocks back",
			Vector2(overhead.velocity.x, overhead.velocity.z).length() > 0.1)

	victim.take_damage(20, Vector3.ZERO, 1.0, 0.0)
	_check("health floors at zero", victim.health == 0)
	_check("death is registered", victim.is_dead)
	victim.take_damage(5, Vector3.ZERO, 1.0, 0.0)
	_check("the dead take no further damage", victim.health == 0)

	var heavy := Combatant.new()
	heavy.knockback_resistance = 0.5
	add_child(heavy)
	heavy.global_position = Vector3(2, 0, 0)
	heavy.take_damage(1, Vector3.ZERO, 10.0, 0.0)
	_check("resistance reduces the shove", absf(heavy.velocity.x - 5.0) < 0.01,
			"vx %.2f" % heavy.velocity.x)

	_check("every ability declares knockback or heals", _all_abilities_shove())
	var bash := AbilityDB.get_ability(&"shield_bash")
	_check("shield bash costs magic", bash.magic_cost > 0.0)
	_check("basic attacks are free", ArchetypeDB.get_archetype(&"knight").basic_attack.magic_cost == 0.0)
	_check("a drained player can still swing", bash.can_afford(0.0) == false
			and ArchetypeDB.get_archetype(&"knight").basic_attack.can_afford(0.0))

	victim.queue_free()
	overhead.queue_free()
	heavy.queue_free()


func _all_abilities_shove() -> bool:
	for id: StringName in AbilityDB.all_ids():
		var ability := AbilityDB.get_ability(id)
		if ability.damage > 0 and ability.knockback <= 0.0:
			return false
		if ability.damage == 0 and ability.heal == 0 and ability.knockback == 0.0:
			return false
	return true


func _test_hearts() -> void:
	print("\n--- hearts")
	var hearts := HeartsDisplay.new()
	hearts.set_health(12, 12)
	_check("three full hearts", hearts.max_hearts() == 3)
	hearts.set_health(7, 12)
	_check("seven points is one and three quarters of a heart",
			hearts.current == 7 and hearts.max_hearts() == 3)
	hearts.set_health(1, 12)
	_check("one point still shows three hearts", hearts.max_hearts() == 3)
	hearts.set_health(16, 20)
	_check("upgrading max hearts adds a heart", hearts.max_hearts() == 5)
	hearts.free()

	var body := Combatant.new()
	body.max_health = 12
	add_child(body)
	body.set_max_health(20)
	_check("raising max health keeps current health", body.health == 12)
	_check("hearts read from points", absf(body.hearts() - 3.0) < 0.001)
	body.queue_free()


func _test_pid_packing() -> void:
	print("\n--- player ids")
	var round_trips := true
	for peer in [1, 2, 1234567, 2147483]:
		for slot in PlayerRegistry.MAX_LOCAL_SLOTS:
			var pid := PlayerRegistry.make_pid(peer, slot)
			if PlayerRegistry.peer_of(pid) != peer or PlayerRegistry.slot_of(pid) != slot:
				round_trips = false
	_check("peer and slot survive packing into one id", round_trips)
	_check("different peers never collide on a slot",
			PlayerRegistry.make_pid(1, 3) != PlayerRegistry.make_pid(2, 0))


# --- helpers ----------------------------------------------------------------------------------

func _rng(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _combined_aabb(node: Node) -> AABB:
	var out := AABB()
	var started := false
	for mesh in _find_meshes(node):
		var box := mesh.get_aabb()
		if not started:
			out = box
			started = true
		else:
			out = out.merge(box)
	return out


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_meshes(child))
	return out

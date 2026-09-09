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
	_test_dragon_fight()
	_test_heightmaps()
	_test_mesher()
	_test_boundary_and_voids()
	_test_culling()
	_test_camera_look()
	_test_combat_math()
	_test_reach()
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


## The boss fight's data: its moveset, the timings the animation and the damage share, and the
## platform it is fought on.
func _test_dragon_fight() -> void:
	print("\n--- dragon fight")

	## Each attack owns a band of ground, and together the bands must leave no gap where the
	## dragon simply has no answer -- that is what would let a party stand somewhere and win by
	## waiting.
	var covered_to := 0.0
	var bands: Array = []
	for id: String in Dragon.ATTACKS:
		bands.append(Dragon.ATTACKS[id])
	bands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["min_range"]) < float(b["min_range"]))
	var gapless := true
	for spec: Dictionary in bands:
		if float(spec["min_range"]) > covered_to + 0.01:
			gapless = false
		covered_to = maxf(covered_to, float(spec["max_range"]))
	_check("attack ranges leave no safe gap", gapless)
	_check("something reaches across the whole arena",
			covered_to >= WorldGenerator.arena_radius() * 1.5,
			"reach %.1f m, arena radius %.1f m" % [covered_to, WorldGenerator.arena_radius()])

	for id: String in Dragon.ATTACKS:
		var spec: Dictionary = Dragon.ATTACKS[id]
		_check("%s has an animation" % id, DragonAnimator.has(spec["clip"]))
		## The damage frame has to land inside the clip, or the attack either never resolves or
		## resolves after the animation has already finished.
		var length := DragonAnimator.duration(spec["clip"])
		_check("%s lands inside its animation" % id,
				float(spec["hit_at"]) > 0.0 and float(spec["hit_at"]) < length,
				"hit_at %.2f of %.2f s" % [spec["hit_at"], length])
		_check("%s knocks back" % id, float(spec["knockback"]) > 0.0)
		_check("%s does damage" % id, int(spec["damage"]) > 0)
		## A tell shorter than the wind-up on a player's own swing is not a tell.
		_check("%s telegraphs before it lands" % id, float(spec["hit_at"]) >= 0.4)

	_check("the tail sweep is the hardest shove",
			float(Dragon.ATTACKS["tail_sweep"]["knockback"])
			== _largest_knockback(), "tail %.0f" % Dragon.ATTACKS["tail_sweep"]["knockback"])
	_check("the tail hits behind the dragon", Dragon.ATTACKS["tail_sweep"]["behind"])
	_check("the breath cannot be used point blank",
			float(Dragon.ATTACKS["breath"]["min_range"]) > 0.0)
	_check("only the breath leaves fire",
			Dragon.ATTACKS["breath"].get("fire", false)
			and not Dragon.ATTACKS["claw"].get("fire", false))

	## Knockback has to be able to clear the platform edge, or "getting knocked off the
	## mountain" is a promise the numbers do not keep.
	var sweep: float = Dragon.ATTACKS["tail_sweep"]["knockback"]
	_check("the tail sweep can throw a player off the platform",
			sweep > WorldGenerator.arena_radius() * 0.9,
			"%.0f m/s against a %.0f m radius" % [sweep, WorldGenerator.arena_radius()])

	## Animation sampling: clips must start and end at rest, or an attack would snap the dragon
	## into its wind-up pose and leave it there.
	for clip_name in ["claw", "breath", "tail_sweep", "wing_flap", "roar"]:
		var start := DragonAnimator.sample(clip_name, 0.0)
		var finish := DragonAnimator.sample(clip_name, DragonAnimator.duration(clip_name))
		_check("%s starts at rest" % clip_name, start.is_empty() or _is_rest(start))
		_check("%s returns to rest" % clip_name, finish.is_empty() or _is_rest(finish))
	## Sampled at the coil and at the follow-through rather than in between: the tail passes
	## through neutral at the midpoint of the swing, so the middle is the one moment that proves
	## nothing.
	var coiled := DragonAnimator.sample("tail_sweep", 0.85)
	var whipped := DragonAnimator.sample("tail_sweep", 1.15)
	_check("the tail coils before the sweep",
			coiled.has("tail_4") and (coiled["tail_4"] as Quaternion).get_angle() > 0.5)
	## Opposite signs on the yaw: the tail has to travel through the arc behind the dragon
	## rather than merely twitching to one side.
	_check("the tail whips through to the other side",
			whipped.has("tail_4")
			and signf((coiled["tail_4"] as Quaternion).y) != signf((whipped["tail_4"] as Quaternion).y))
	_check("clips only pose bones the rig has",
			_poses_known_bones("tail_sweep") and _poses_known_bones("breath"))

	## The arena the generator carves has to be flat, or knockback stops against a step instead
	## of carrying someone over the edge.
	var mountain := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"mountain"), _rng(4242))
	var tiles := WorldGenerator.CHUNK_TILES
	var half := tiles / 2
	var platform_level := mountain[half * tiles + half]
	var flat := true
	for z in tiles:
		for x in tiles:
			var radial := Vector2(x - (tiles - 1) * 0.5, z - (tiles - 1) * 0.5).length()
			if radial <= WorldGenerator.ARENA_RADIUS_TILES \
					and mountain[z * tiles + x] != platform_level:
				flat = false
	_check("the summit arena is dead flat", flat)
	_check("the summit is the highest ground on the mountain",
			platform_level == _peak_level(mountain))
	_check("the arena is wide enough for a dragon and four players",
			WorldGenerator.arena_radius() >= 12.0,
			"%.0f m radius" % WorldGenerator.arena_radius())


func _largest_knockback() -> float:
	var best := 0.0
	for id: String in Dragon.ATTACKS:
		best = maxf(best, float(Dragon.ATTACKS[id]["knockback"]))
	return best


func _is_rest(pose: Dictionary) -> bool:
	for bone: String in pose:
		if (pose[bone] as Quaternion).get_angle() > 0.02:
			return false
	return true


func _poses_known_bones(clip_name: String) -> bool:
	for frame: Dictionary in DragonAnimator.clip(clip_name):
		for bone: String in frame["pose"]:
			if not DragonAnimator.DRIVEN_BONES.has(bone):
				return false
	return true


func _peak_level(heights: PackedInt32Array) -> int:
	var peak := -999
	for level in heights:
		peak = maxi(peak, level)
	return peak


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

## The two things that stop players seeing out of the world: the cliff ring around the map, and
## the caps sealing the bottom of every pit.
func _test_boundary_and_voids() -> void:
	print("\n--- world edges")

	var span := WorldGenerator.GRID * WorldGenerator.CHUNK_SIZE
	_check("the boundary reaches beyond the map", WorldBoundary.extent() > 40.0,
			"%.0f m" % WorldBoundary.extent())
	## Tall enough to fill the horizon from ground level rather than being looked over.
	_check("the boundary stands high enough to hide the drop", WorldBoundary.height() > 20.0,
			"%.0f m" % WorldBoundary.height())
	## The whole point of the ring: no step in it may be climbable, or the party walks out of
	## the world.
	var jump_apex := (11.4 * 11.4) / (2.0 * 24.0)  ## The Archer jumps highest.
	## Every terrace, not just the first: they grow outward, so the shortest one is the test.
	var shortest := INF
	for step in WorldBoundary.STEPS:
		shortest = minf(shortest, WorldBoundary.rise_of(step))
	_check("no boundary step can be jumped", shortest > jump_apex + 0.5,
			"shortest step %.1f m, best jump %.2f m" % [shortest, jump_apex])
	## And it has to out-top the mountain, or the summit looks straight over it into nothing.
	var summit := ChunkMesher.height_to_world(BiomeLibrary.get_biome(&"mountain").height_levels)
	_check("the ring stands taller than the mountain", WorldBoundary.height() > summit + 10.0,
			"ring %.0f m, summit %.0f m" % [WorldBoundary.height(), summit])

	var boundary := WorldBoundary.new()
	add_child(boundary)
	boundary.build()
	var cliffs := boundary.get_node_or_null("Cliffs") as MeshInstance3D
	_check("the boundary builds geometry", cliffs != null and cliffs.mesh != null)
	if cliffs != null and cliffs.mesh != null:
		var box := cliffs.mesh.get_aabb()
		## It has to enclose the map on every side, not merely exist somewhere near it.
		_check("the ring encloses the whole map",
				box.position.x <= 0.1 and box.position.z <= 0.1
				and box.end.x >= span - 0.1 and box.end.z >= span - 0.1,
				str(box))
		_check("the ring rises above the play area", box.end.y >= WorldBoundary.height() - 0.1)
	_check("the boundary is solid", boundary.get_node_or_null("CliffBody") != null)
	boundary.queue_free()

	## Void caps. A pitted biome must produce them; a flat one must not waste a mesh on nothing.
	var pitted := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"temple"), _rng(11))
	var caps := ChunkMesher.build_void_caps(pitted, WorldGenerator.CHUNK_TILES)
	_check("pits get a floor", caps != null)
	if caps != null:
		var cap_box := caps.get_aabb()
		## Level with the bottom of the pit walls, so the shaft is closed rather than merely
		## having something floating in it.
		_check("the floor sits at the bottom of the shaft",
				absf(cap_box.position.y - ChunkMesher.height_to_world(ChunkMesher.VOID_DEPTH)) < 0.01,
				"%.2f m" % cap_box.position.y)
		_check("the floor is below all playable ground",
				cap_box.end.y < 0.01, "%.2f m" % cap_box.end.y)

	var town := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"town"), _rng(3))
	_check("a chunk with no pits gets no floor",
			ChunkMesher.build_void_caps(town, WorldGenerator.CHUNK_TILES) == null)

	## The cap must never end up in the terrain mesh, because that mesh is what the collider is
	## generated from -- a floor welded in turns every pit into something you land on, and the
	## whole knockback-off-a-ledge design stops working. The pit *walls* do legitimately reach
	## that depth, so the test looks for an upward-facing surface rather than for the depth.
	var terrain := ChunkMesher.build(pitted, WorldGenerator.CHUNK_TILES,
			BiomeLibrary.get_biome(&"temple"), _rng(11))
	var arrays := terrain.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var floor_depth := ChunkMesher.height_to_world(ChunkMesher.VOID_DEPTH)
	var standable_in_pit := 0
	for i in vertices.size():
		if absf(vertices[i].y - floor_depth) < 0.05 and normals[i].y > 0.5:
			standable_in_pit += 1
	_check("nothing standable exists at the bottom of a pit", standable_in_pit == 0,
			"%d upward-facing vertices at %.1f m" % [standable_in_pit, floor_depth])
	## And the cap itself must be the thing that is upward-facing, or it would not be visible
	## looking down the shaft.
	var cap_arrays := caps.surface_get_arrays(0)
	var cap_normals: PackedVector3Array = cap_arrays[Mesh.ARRAY_NORMAL]
	_check("the void floor faces upwards", cap_normals.size() > 0 and cap_normals[0].y > 0.5,
			str(cap_normals[0]) if cap_normals.size() > 0 else "none")


## Distance culling. The rules have to be generous enough that nothing switches off while it
## could still matter to a player, and the sleep condition has to be safe for a body that is
## still moving.
func _test_culling() -> void:
	print("\n--- culling")

	## Monsters must stay awake well past the range at which they would notice a player, or one
	## would freeze just as the party walked into its aggro radius.
	var widest_aggro := 0.0
	for id: StringName in MonsterDB.all_ids():
		widest_aggro = maxf(widest_aggro, MonsterDB.get_monster(id).aggro_range)
	_check("monsters stay awake beyond their own aggro range",
			Culling.MONSTER_ACTIVE_RANGE > widest_aggro + 20.0,
			"active %.0f m, widest aggro %.0f m" % [Culling.MONSTER_ACTIVE_RANGE, widest_aggro])
	_check("monsters are drawn further than they are simulated",
			Culling.MONSTER_VISIBLE_RANGE > Culling.MONSTER_ACTIVE_RANGE)
	## A dragon 60 m away on its platform still has to be visible from the climb.
	_check("props are drawn far enough to fill the middle distance",
			Culling.PROP_BASE_RANGE >= 80.0)
	_check("draw distance fades rather than pops", Culling.FADE_MARGIN > 5.0)

	var mesh := MeshInstance3D.new()
	add_child(mesh)
	Culling.apply_prop_range(mesh, 2.4)
	var big := mesh.visibility_range_end
	Culling.apply_prop_range(mesh, 0.4)
	_check("bigger props stay visible longer", big > mesh.visibility_range_end,
			"%.0f m vs %.0f m" % [big, mesh.visibility_range_end])
	_check("small props stop casting shadows",
			mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	mesh.queue_free()

	## The world has one floor, shared by everything that can fall off it.
	_check("the kill height is below every playable surface",
			Combatant.KILL_HEIGHT < ChunkMesher.height_to_world(ChunkMesher.VOID_DEPTH),
			"kill %.1f m, pit floor %.1f m" % [Combatant.KILL_HEIGHT,
					ChunkMesher.height_to_world(ChunkMesher.VOID_DEPTH)])


## Right-button free-look.
func _test_camera_look() -> void:
	print("\n--- camera look")
	var rig := PlayerCamera.new()
	add_child(rig)

	var before := rig.yaw
	rig.apply_mouse_look(Vector2(100.0, 0.0))
	_check("dragging horizontally turns the camera", not is_equal_approx(rig.yaw, before))
	## Same direction as the Q/E keys, so the two controls do not fight each other.
	_check("dragging right turns the same way as E", rig.yaw < before)

	rig.pitch_offset = 0.0
	rig.apply_mouse_look(Vector2(0.0, 60.0))
	_check("dragging vertically tilts the camera", rig.pitch_offset > 0.0)
	## Bounded, because the fixed high angle is what makes a ledge visible before you are
	## knocked over it.
	for _i in 40:
		rig.apply_mouse_look(Vector2(0.0, 500.0))
	_check("tilt is clamped downward", rig.pitch_offset <= PlayerCamera.PITCH_RANGE + 0.001,
			"%.1f deg" % rig.pitch_offset)
	for _i in 40:
		rig.apply_mouse_look(Vector2(0.0, -500.0))
	_check("tilt is clamped upward", rig.pitch_offset >= -PlayerCamera.PITCH_RANGE - 0.001,
			"%.1f deg" % rig.pitch_offset)
	rig.queue_free()


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

	## Faction and group membership must not be able to drift apart. Bodies are added to the
	## tree and configured afterwards, so _ready() files them under the default faction; when a
	## later `faction = PLAYER` did not move them, every player sat in the "monsters" group.
	## Nothing looked broken -- but no monster attack could find a player to hit, and players
	## became legal targets for each other.
	var late := Combatant.new()
	add_child(late)
	_check("a body defaults to the monster group", late.is_in_group("monsters"))
	late.faction = Combatant.Faction.PLAYER
	_check("changing faction moves it to the player group", late.is_in_group("players"))
	_check("changing faction takes it out of the old group", not late.is_in_group("monsters"))

	var beast := Combatant.new()
	add_child(beast)
	var ally := Combatant.new()
	ally.faction = Combatant.Faction.PLAYER
	add_child(ally)
	_check("a monster is hostile to a player", beast.is_hostile_to(late))
	_check("a monster is not hostile to another monster", not beast.is_hostile_to(_a_monster()))
	_check("a player is not hostile to another player", not late.is_hostile_to(ally))

	## The resolver must agree, even if a group is ever wrong again.
	## Well inside a skeleton's 2.4 m reach, so the check is about who is a legal target rather
	## than about range.
	late.global_position = Vector3(0, 0, -1.8)
	ally.global_position = Vector3(0, 0, -1.8)
	beast.global_position = Vector3.ZERO
	var swing := AbilityDB.get_ability(&"skeleton_slash")
	var forward := Vector3(0, 0, -1)
	var monster_finds := CombatResolver.arc_targets(get_tree(), beast, Vector3.ZERO, forward, swing)
	_check("a monster's attack can reach a player", monster_finds.has(late))
	var friendly := CombatResolver.arc_targets(get_tree(), late, Vector3.ZERO, forward, swing)
	_check("a player's attack never catches a teammate", not friendly.has(ally))
	for body in [late, beast, ally]:
		body.queue_free()

	## Bodies must not be able to carry each other. Two characters overlapping used to feed each
	## other velocity through move_and_slide's moving-platform handling, doubling it every frame
	## until a player was launched to 230 km up and could never fall back into the world.
	var body := Combatant.new()
	Combatant.setup_body(body, 0.4, 1.6)
	add_child(body)
	_check("characters and terrain are on different layers",
			Combatant.LAYER_COMBATANT != Combatant.LAYER_WORLD)
	_check("a character collides with terrain and other characters",
			body.collision_mask == (Combatant.LAYER_WORLD | Combatant.LAYER_COMBATANT))
	_check("only static ground can carry a character",
			body.platform_floor_layers == Combatant.LAYER_WORLD)

	body.velocity = Vector3(0.0, 1565989.0, 0.0)
	body.clamp_speed()
	_check("a runaway velocity is contained", body.velocity.length() <= Combatant.MAX_SPEED,
			"%.0f m/s" % body.velocity.length())
	## The clamp must not be tight enough to blunt the hardest hit in the game.
	body.velocity = Vector3(0.0, float(Dragon.ATTACKS["tail_sweep"]["knockback"]), 0.0)
	var intended := body.velocity
	body.clamp_speed()
	_check("the hardest knockback survives the clamp", body.velocity.is_equal_approx(intended))
	body.queue_free()

	_check("every ability declares knockback or heals", _all_abilities_shove())
	var bash := AbilityDB.get_ability(&"shield_bash")
	_check("shield bash costs magic", bash.magic_cost > 0.0)
	_check("basic attacks are free", ArchetypeDB.get_archetype(&"knight").basic_attack.magic_cost == 0.0)
	_check("a drained player can still swing", bash.can_afford(0.0) == false
			and ArchetypeDB.get_archetype(&"knight").basic_attack.can_afford(0.0))

	victim.queue_free()
	overhead.queue_free()
	heavy.queue_free()


func _a_monster() -> Combatant:
	var beast := Combatant.new()
	add_child(beast)
	beast.queue_free()
	return beast


func _all_abilities_shove() -> bool:
	for id: StringName in AbilityDB.all_ids():
		var ability := AbilityDB.get_ability(id)
		if ability.damage > 0 and ability.knockback <= 0.0:
			return false
		if ability.damage == 0 and ability.heal == 0 and ability.knockback == 0.0:
			return false
	return true


## Reach against bodies of different sizes. This is the geometry that made the Archer and the
## Wizard unable to damage anything at all, and the dragon unhittable from outside its own
## collision capsule: hit tests measured to a combatant's origin, which sits at its feet, and
## treated every body as a dimensionless point.
func _test_reach() -> void:
	print("\n--- reach")
	var attacker := Combatant.new()
	attacker.faction = Combatant.Faction.PLAYER
	attacker.hit_radius = 0.42
	attacker.hit_height = 1.6
	add_child(attacker)
	attacker.global_position = Vector3.ZERO

	_check("hit centre is mid-body, not underfoot",
			absf(attacker.hit_centre().y - 0.8) < 0.001, str(attacker.hit_centre()))

	var skeleton := Combatant.new()
	skeleton.hit_radius = 0.45
	skeleton.hit_height = 1.7
	add_child(skeleton)

	## A 5.6 m dragon whose collision capsule is 2 m across: any melee reach shorter than that
	## radius is unusable, because the player cannot physically stand that close.
	var dragon := Combatant.new()
	dragon.hit_radius = 2.0
	dragon.hit_height = 5.0
	add_child(dragon)

	var swing := AbilityDB.get_ability(&"knight_swing")
	var forward := Vector3(0, 0, -1)

	skeleton.global_position = Vector3(0, 0, -2.5)
	_check("a swing reaches a skeleton just inside its range",
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).size() == 1)
	skeleton.global_position = Vector3(0, 0, -8.0)
	_check("a swing does not reach across the chunk",
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).is_empty())
	skeleton.global_position = Vector3(0, 0, 2.5)
	_check("a swing does not hit behind the attacker",
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).is_empty())
	skeleton.global_position = Vector3(0, 0, -900.0)

	## The regression itself: standing outside a big target's capsule must still be in reach.
	dragon.global_position = Vector3(0, 0, -4.0)
	_check("a swing reaches a dragon from outside its collision capsule",
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).size() == 1,
			"melee range %.1f m, dragon radius %.1f m" % [swing.range, dragon.hit_radius])
	dragon.global_position = Vector3(0, 0, -9.0)
	_check("a dragon is not swingable from across the arena",
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).is_empty())

	## A tall target's mid-body sits metres above the attacker's; a fixed vertical gate rejected
	## it outright.
	dragon.global_position = Vector3(0, 0, -3.0)
	_check("a dragon's height does not put it out of the vertical gate",
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).size() == 1)
	dragon.global_position = Vector3(0, 12.0, -3.0)
	_check("something on the plateau above is still out of reach",
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).is_empty())
	dragon.global_position = Vector3(0, 0, -900.0)

	## Projectiles fly at mid-body height, so the sphere test has to be done there too --
	## measuring to the feet meant the test could never succeed for a flat shot.
	skeleton.global_position = Vector3(0, 0, -6.0)
	var in_flight := skeleton.hit_centre()
	_check("a projectile at the target's chest scores",
			CombatResolver.radius_targets(get_tree(), attacker, in_flight,
					Projectile.HIT_RADIUS).size() == 1)
	_check("a projectile level with the target's feet does not",
			CombatResolver.radius_targets(get_tree(), attacker,
					skeleton.global_position + Vector3(0, -1.6, 0),
					Projectile.HIT_RADIUS).is_empty())

	for body in [attacker, skeleton, dragon]:
		body.queue_free()


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

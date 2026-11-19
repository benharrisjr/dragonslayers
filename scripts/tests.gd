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
	_test_gear()
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
		## The heroes are looks, not classes: every one of them swings the same sword.
		_check("%s swings the sword" % id, archetype.basic_attack != null
				and archetype.basic_attack.id == &"sword_swing")
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
	var shape_ok := true
	var tiers_ok := true
	var sea_ok := true
	var detail := ""
	for world_seed in [1, 7, 4242, 99991, 123456789, 31, 2026, 555]:
		var plan := WorldGenerator.plan(world_seed)
		var cells: Array = plan["biomes"]
		var tiers: PackedInt32Array = plan["tiers"]
		if cells.size() != 16 or cells.count(&"mountain") != 1 or cells.count(&"town") != 1:
			shape_ok = false
			continue
		var mountain := cells.find(&"mountain")
		if not WorldGenerator._is_edge(mountain):
			shape_ok = false
		var sea := 0
		for index in 16:
			## The map steps down from the mountain: its own cell, then the ring touching it,
			## then everything beyond -- some of which, furthest out, drops to the sea.
			var distance := WorldGenerator._chebyshev(index, mountain)
			var tier := tiers[index]
			var expected := WorldGenerator.Tier.GROUND
			if distance == 0:
				expected = WorldGenerator.Tier.SUMMIT
			elif distance == 1:
				expected = WorldGenerator.Tier.HIGHLANDS
			if tier == WorldGenerator.Tier.SEA:
				sea += 1
				if distance < 3 or cells[index] != &"beach" or not WorldGenerator._is_edge(index):
					sea_ok = false
			elif tier != expected:
				tiers_ok = false
				detail = "seed %d cell %d" % [world_seed, index]
			if cells[index] == &"town" and tier != WorldGenerator.Tier.GROUND:
				tiers_ok = false
		if sea < 2 or sea > 4:
			sea_ok = false
			detail = "seed %d has %d sea chunks" % [world_seed, sea]
	_check("16 chunks with one mountain on an edge and one town", shape_ok)
	_check("tiers step down with distance from the mountain", tiers_ok, detail)
	_check("two to four of the furthest chunks are beach, on the coast", sea_ok, detail)
	_check("each tier is lower than the one inside it",
			WorldGenerator.base_level(WorldGenerator.Tier.SEA)
					< WorldGenerator.base_level(WorldGenerator.Tier.GROUND)
			and WorldGenerator.base_level(WorldGenerator.Tier.GROUND)
					< WorldGenerator.base_level(WorldGenerator.Tier.HIGHLANDS)
			and WorldGenerator.base_level(WorldGenerator.Tier.HIGHLANDS)
					< WorldGenerator.summit_level())
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
	var mountain := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"mountain"), _rng(4242)).heights
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
	_check("heightmaps are deterministic",
			first.heights == second.heights and first.slopes == second.slopes)
	_check("heightmap is the right size",
			first.heights.size() == WorldGenerator.CHUNK_TILES * WorldGenerator.CHUNK_TILES)

	## Chunk rims must sit at the chunk's own ground level or neighbouring chunks on the same
	## tier would not meet, and the party could not walk between them.
	var tiles := WorldGenerator.CHUNK_TILES
	var rim_ok := true
	var pits_ok := true
	var pit_detail := ""
	for id: StringName in BiomeLibrary.all_ids():
		var data := BiomeLibrary.get_biome(id)
		var terrain := WorldGenerator.heightmap(data, _rng(77))
		for i in tiles:
			for index in [i, (tiles - 1) * tiles + i, i * tiles, i * tiles + tiles - 1]:
				var x: int = index % tiles
				var z: int = index / tiles
				## Sides facing the open sea have nothing to meet and are allowed to fall away.
				if WorldGenerator._rim_to_neighbour(terrain, x, z) == 0 \
						and terrain.heights[index] != terrain.base_level:
					rim_ok = false
		## Pits are a deliberate handful in the biomes that ask for them, and absent elsewhere.
		var holes := 0
		for level in terrain.heights:
			if level == ChunkMesher.HOLE:
				holes += 1
		if (data.pit_count == 0 and holes > 0) or holes > data.pit_count * 25 \
				or (data.pit_count > 0 and holes == 0):
			pits_ok = false
			pit_detail = "%s has %d hole tiles for %d pits" % [id, holes, data.pit_count]
	_check("every biome's rim sits at its own ground level", rim_ok)
	_check("pits are rare and only where a biome asks for them", pits_ok, pit_detail)
	var pitted_biomes := 0
	for id: StringName in BiomeLibrary.all_ids():
		if BiomeLibrary.get_biome(id).pit_count > 0:
			pitted_biomes += 1
	_check("only a couple of biomes have pits at all", pitted_biomes <= 2, "%d" % pitted_biomes)

	var mountain := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"mountain"), _rng(5))
	var peak := _peak_level(mountain.heights)
	_check("the mountain has a summit to climb", peak == WorldGenerator.summit_level(),
			"peak level %d" % peak)
	## The summit used to be unreachable on foot -- the playtest teleported there. It now has to
	## be walkable from the mountain's rim with no jump at all.
	var half := tiles / 2
	_check("the summit can be walked to from the mountain's rim",
			mountain.reach[half * tiles + half] == 1)

	## Slopes. A ramp tile rises exactly one level across its length, which at 0.9 m over 2 m
	## is about 24 degrees -- inside the 50 degree limit a body can walk.
	var ramp_tiles := 0
	var ramp_ok := true
	for z in tiles:
		for x in tiles:
			if not mountain.is_slope(x, z):
				continue
			ramp_tiles += 1
			var low := INF
			var high := -INF
			for which in 4:
				low = minf(low, mountain.corner(x, z, which))
				high = maxf(high, mountain.corner(x, z, which))
			if not is_equal_approx(high - low, 1.0):
				ramp_ok = false
	_check("the mountain has an ascent ramp",
			ramp_tiles == WorldGenerator.SUMMIT_RISE * WorldGenerator.RAMP_WIDTH, "%d tiles" % ramp_tiles)
	_check("every ramp tile rises exactly one level", ramp_ok)
	var slope_degrees := rad_to_deg(atan(ChunkMesher.STEP_HEIGHT / ChunkMesher.TILE_SIZE))
	_check("ramps are shallow enough to walk", slope_degrees < 45.0, "%.0f degrees" % slope_degrees)

	## A chunk next to lower ground cuts a ramp down to it.
	var ground := WorldGenerator.base_level(WorldGenerator.Tier.GROUND)
	var high_ground := WorldGenerator.base_level(WorldGenerator.Tier.HIGHLANDS)
	var stepped := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"forest"), _rng(21), {
		"base": high_ground, "ascent_side": -1,
		"sides": PackedInt32Array([ground, high_ground, TerrainData.MAP_EDGE, high_ground]),
	})
	var foot_reached := false
	for lane in tiles:
		var index := lane * tiles + tiles - 1
		if stepped.heights[index] == ground and stepped.reach[index] == 1:
			foot_reached = true
	_check("a ramp runs down to a lower neighbour and can be walked", foot_reached)

	## The beach: dry sand, then a shore that slopes under the water rather than stepping.
	var beach := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"beach"), _rng(8))
	var dry := 0
	var wet_reached := 0
	for index in tiles * tiles:
		if beach.heights[index] == beach.base_level:
			dry += 1
		elif beach.heights[index] < beach.base_level and beach.reach[index] == 1:
			wet_reached += 1
	_check("the beach has dry sand", dry > tiles * tiles / 5, "%d tiles" % dry)
	_check("the sea can be waded into from the sand", wet_reached > tiles * tiles / 5,
			"%d tiles" % wet_reached)
	_check("the sand stands above the water line and the shallows below it",
			ChunkMesher.height_to_world(beach.base_level) > WorldGenerator.SEA_SURFACE
			and ChunkMesher.height_to_world(beach.base_level - 1) < WorldGenerator.SEA_SURFACE)

	_test_walkable_world()


## The promise the whole terrain rework rests on: with no feather, no hookshot and no jump, a
## player can walk from the town to the dragon, to the beach, and into every chunk on the map.
func _test_walkable_world() -> void:
	var tiles := WorldGenerator.CHUNK_TILES
	var grid := WorldGenerator.GRID
	var failures := ""
	var seeds := [4242, 7, 99991, 31, 2026, 8]
	for world_seed: int in seeds:
		var plan := WorldGenerator.plan(world_seed)
		var tiers: PackedInt32Array = plan["tiers"]
		var terrains: Array[TerrainData] = []
		for index in grid * grid:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(world_seed) ^ (index * 2654435761)
			terrains.append(WorldGenerator.heightmap(BiomeLibrary.get_biome(plan["biomes"][index]),
					rng, WorldGenerator.context(tiers, index)))

		## Flood across the whole map from a tile on the town's rim.
		var town: int = plan["biomes"].find(&"town")
		var seen := PackedByteArray()
		seen.resize(grid * grid * tiles * tiles)
		var start := town * tiles * tiles + _first_rim_tile(terrains[town])
		seen[start] = 1
		var queue: Array[int] = [start]
		var head := 0
		while head < queue.size():
			var node := queue[head]
			head += 1
			var cell := node / (tiles * tiles)
			var tile := node % (tiles * tiles)
			var x := tile % tiles
			var z := tile / tiles
			var terrain := terrains[cell]
			for side in 4:
				var nx := x + ChunkMesher.NEIGHBOUR_DX[side]
				var nz := z + ChunkMesher.NEIGHBOUR_DZ[side]
				var next := -1
				if terrain.in_bounds(nx, nz):
					if terrain.can_walk(x, z, side):
						next = cell * tiles * tiles + nz * tiles + nx
				else:
					## Across a chunk border: the two edges have to meet at the same height.
					var other := WorldGenerator.neighbour_cell(cell, side)
					if other < 0:
						continue
					var ox := posmod(nx, tiles)
					var oz := posmod(nz, tiles)
					var beyond := terrains[other]
					if terrain.is_hole(x, z) or beyond.is_hole(ox, oz):
						continue
					var mine := terrain.edge(x, z, side)
					var theirs := beyond.edge(ox, oz, (side + 2) % 4)
					if absf(mine.x - theirs.y) < 0.01 and absf(mine.y - theirs.x) < 0.01:
						next = other * tiles * tiles + oz * tiles + ox
				if next >= 0 and seen[next] == 0:
					seen[next] = 1
					queue.append(next)

		for index in grid * grid:
			var terrain := terrains[index]
			## Anything a chunk marks as walkable from its own rim -- which is where its large
			## chest and any spawn point go -- is reachable from town if its rim is.
			var rim_tile := _first_rim_tile(terrain)
			if seen[index * tiles * tiles + rim_tile] == 0:
				failures += " seed %d: chunk %d (%s) cannot be walked to;" % [
					world_seed, index, plan["biomes"][index]]
		var mountain: int = plan["biomes"].find(&"mountain")
		var half := tiles / 2
		if seen[mountain * tiles * tiles + half * tiles + half] == 0:
			failures += " seed %d: the dragon's arena cannot be walked to;" % world_seed
		var beach_found := false
		for index in grid * grid:
			if plan["biomes"][index] != &"beach":
				continue
			for tile in tiles * tiles:
				if terrains[index].heights[tile] < terrains[index].base_level \
						and seen[index * tiles * tiles + tile] == 1:
					beach_found = true
					break
		if not beach_found:
			failures += " seed %d: the sea cannot be walked into;" % world_seed
	_check("town to the dragon, the sea and every chunk, on foot with no jump (%d seeds)" % seeds.size(),
			failures.is_empty(), failures)


## A tile on the chunk's outer ring that sits at the chunk's ground level.
func _first_rim_tile(terrain: TerrainData) -> int:
	for index in terrain.size * terrain.size:
		if terrain.rim(index % terrain.size, index / terrain.size) == 0 \
				and terrain.heights[index] == terrain.base_level and terrain.reach[index] == 1:
			return index
	return 0


func _test_mesher() -> void:
	print("\n--- mesher")
	var biome := BiomeLibrary.get_biome(&"forest")
	var heights := WorldGenerator.heightmap(biome, _rng(9))
	var mesh := ChunkMesher.build(heights, biome, _rng(9))
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
	## Every terrace beyond the inner wall: they grow outward, so the shortest one is the test.
	var shortest := INF
	for step in range(1, WorldBoundary.STEPS):
		shortest = minf(shortest, WorldBoundary.rise_of(step))
	## The inner wall stands against edge chunks at every tier, so it has to clear the tallest.
	var tallest_edge := ChunkMesher.height_to_world(
			WorldGenerator.base_level(WorldGenerator.Tier.HIGHLANDS) + 2)
	_check("the inner wall out-tops the highest ground on the map's edge",
			WorldBoundary.INNER_WALL_TOP > tallest_edge + jump_apex + 0.5,
			"wall %.1f m, edge %.1f m" % [WorldBoundary.INNER_WALL_TOP, tallest_edge])
	_check("no boundary step can be jumped", shortest > jump_apex + 0.5,
			"shortest step %.1f m, best jump %.2f m" % [shortest, jump_apex])
	## And it has to out-top the mountain, or the summit looks straight over it into nothing.
	var summit := ChunkMesher.height_to_world(WorldGenerator.summit_level())
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
	var caps := ChunkMesher.build_void_caps(pitted.heights, WorldGenerator.CHUNK_TILES)
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

	var town := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"town"), _rng(3)).heights
	_check("a chunk with no pits gets no floor",
			ChunkMesher.build_void_caps(town, WorldGenerator.CHUNK_TILES) == null)

	## The cap must never end up in the terrain mesh, because that mesh is what the collider is
	## generated from -- a floor welded in turns every pit into something you land on, and the
	## whole knockback-off-a-ledge design stops working. The pit *walls* do legitimately reach
	## that depth, so the test looks for an upward-facing surface rather than for the depth.
	var terrain := ChunkMesher.build(pitted, BiomeLibrary.get_biome(&"temple"), _rng(11))
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
			body.collision_mask == (Combatant.LAYER_WORLD | Combatant.LAYER_COMBATANT
					| Combatant.LAYER_SCENERY))
	_check("scenery is on its own layer, so the camera can ignore it",
			Combatant.LAYER_SCENERY != Combatant.LAYER_WORLD
			and Combatant.LAYER_SCENERY != Combatant.LAYER_COMBATANT)
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
	_check("the sword is free to swing", ArchetypeDB.get_archetype(&"knight").basic_attack.magic_cost == 0.0
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

	var swing := AbilityDB.get_ability(&"sword_swing")
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

# --- gear ------------------------------------------------------------------------------------

func _test_gear() -> void:
	print("\n--- gear")
	var pid := PlayerRegistry.make_pid(1, 0)
	PlayerRegistry.add_entry(pid, &"knight")
	var hero := PlayerCharacter.new()
	Combatant.setup_body(hero, 0.42, 1.6)
	add_child(hero)
	hero.configure(pid, ArchetypeDB.get_archetype(&"knight"))

	_check("everyone starts with a sword and a shield",
			hero.gear == ([ItemDB.SWORD, ItemDB.SHIELD] as Array[StringName]))
	_check("and has them on the first two hotkeys",
			hero.hotkeys[0] == ItemDB.SWORD and hero.hotkeys[1] == ItemDB.SHIELD
			and hero.hotkeys[2] == &"")
	_check("no feather to begin with, so no jump", not hero.has_item(ItemDB.FEATHER))

	_check("a found item is taken", hero.add_item(ItemDB.HOOKSHOT))
	_check("and is equipped on the third button straight away",
			hero.equipped() == ItemDB.HOOKSHOT)
	_check("a second one is left on the ground", not hero.add_item(ItemDB.HOOKSHOT))
	hero.add_item(ItemDB.FEATHER)
	hero.add_item(ItemDB.BOOTS)
	_check("passive gear takes no hotkey",
			not hero.hotkeys.has(ItemDB.FEATHER) and not hero.hotkeys.has(ItemDB.BOOTS))
	_check("static gear cannot be equipped", not hero.equip(ItemDB.FEATHER))
	_check("nor can the sword: it has its own button", not hero.equip(ItemDB.SWORD)
			and hero.hotkeys[0] == ItemDB.SWORD and hero.hotkeys[1] == ItemDB.SHIELD)
	_check("an item nobody holds cannot be equipped", not hero.equip(&"nonsense"))

	## The shield. Every character faces +Z at rest.
	var front := hero.global_position + Vector3(0, 0, 3)
	var behind := hero.global_position + Vector3(0, 0, -3)
	_check("the shield covers the front", hero.blocks_from(front))
	_check("and not the back", not hero.blocks_from(behind))
	hero.blocking = true
	var before := hero.health
	hero.take_damage(3, front, 9.0, 0.3)
	_check("a blocked hit does no damage", hero.health == before, "%d -> %d" % [before, hero.health])
	_check("a blocked hit shoves a third as hard",
			Vector2(hero.velocity.x, hero.velocity.z).length()
					< 9.0 * hero.knockback_resistance * 0.5,
			"%.1f m/s" % Vector2(hero.velocity.x, hero.velocity.z).length())
	hero.take_damage(3, behind, 9.0, 0.3)
	_check("a hit from behind gets past the shield", hero.health == before - 3)
	hero.blocking = false
	hero.take_damage(3, front, 9.0, 0.3)
	_check("a lowered shield blocks nothing", hero.health == before - 6)

	## Death: everything but the sword and shield.
	var dropped := hero._strip_droppable_gear()
	_check("dying drops the hookshot, feather and boots",
			dropped.size() == 3 and dropped.has(ItemDB.HOOKSHOT) and dropped.has(ItemDB.FEATHER)
			and dropped.has(ItemDB.BOOTS), str(dropped))
	_check("and keeps the sword and shield",
			hero.gear == ([ItemDB.SWORD, ItemDB.SHIELD] as Array[StringName]))
	_check("a dropped item comes off its hotkey", not hero.hotkeys.has(ItemDB.HOOKSHOT))

	## Pickups.
	var feather := Pickup.new()
	add_child(feather)
	feather.setup(Pickup.Kind.ITEM, ItemDB.ORDER.find(ItemDB.FEATHER), Vector3(50, 0, 50))
	_check("an item pickup knows what it is", feather.item_id() == ItemDB.FEATHER)
	_check("a player without it may take it", feather._may_take(hero))
	feather.dropped_by = pid
	_check("but not straight after dropping it themselves", not feather._may_take(hero))
	feather.dropped_by = 0
	feather._net_collected(hero.get_path())
	_check("walking into it grants the item", hero.has_item(ItemDB.FEATHER))
	var spare := Pickup.new()
	add_child(spare)
	spare.setup(Pickup.Kind.ITEM, ItemDB.ORDER.find(ItemDB.FEATHER), Vector3(50, 0, 50))
	_check("a player who already has it leaves it for someone else", not spare._may_take(hero))
	spare.queue_free()

	_check("the town's chest always holds a feather",
			ItemDB.chest_item(0, &"town") == ItemDB.FEATHER
			and ItemDB.chest_item(7, &"town") == ItemDB.FEATHER)
	var found := {}
	for index in 16:
		found[ItemDB.chest_item(index, &"plains")] = true
	_check("the other chests hand out all three finds",
			found.has(ItemDB.FEATHER) and found.has(ItemDB.BOOTS) and found.has(ItemDB.HOOKSHOT))
	_check("sword and shield are kept, the rest can be dropped",
			not ItemDB.is_droppable(ItemDB.SWORD) and not ItemDB.is_droppable(ItemDB.SHIELD)
			and ItemDB.is_droppable(ItemDB.HOOKSHOT) and ItemDB.is_droppable(ItemDB.FEATHER)
			and ItemDB.is_droppable(ItemDB.BOOTS))

	## The lantern. Two usables share one button.
	hero.add_item(ItemDB.HOOKSHOT)
	_check("a second usable waits in the panel",
			hero.add_item(ItemDB.LANTERN) and hero.equipped() == ItemDB.HOOKSHOT)
	_check("and can be equipped in place of the first",
			hero.equip(ItemDB.LANTERN) and hero.equipped() == ItemDB.LANTERN
			and hero.hotkeys[0] == ItemDB.SWORD and hero.hotkeys[1] == ItemDB.SHIELD,
			str(hero.hotkeys))
	hero.remove_item(ItemDB.LANTERN)
	_check("losing the equipped one puts the other on the button",
			hero.equipped() == ItemDB.HOOKSHOT)
	hero.add_item(ItemDB.LANTERN)
	hero.equip(ItemDB.LANTERN)
	_check("the lantern is dropped on death like the other finds", ItemDB.is_droppable(ItemDB.LANTERN))

	## Its fire burns monsters and leaves the party alone; the dragon's does the reverse.
	var skeleton := _a_monster()
	skeleton.global_position = Vector3(80, 0, 80)
	hero.global_position = Vector3(80, 0, 80.5)
	var skeleton_before := skeleton.health
	var hero_before := hero.health
	var lantern_fire := FirePatch.new()
	add_child(lantern_fire)
	## Dropped by somebody else: pid 999 is not the hero.
	lantern_fire.ignite(Vector3(80, 0, 80), 2.0, Combatant.Faction.MONSTER, true, 999)
	lantern_fire.burn_once()
	_check("lantern fire burns a monster standing in it", skeleton.health < skeleton_before,
			"%d -> %d" % [skeleton_before, skeleton.health])
	_check("lantern fire does not burn the party", hero.health == hero_before)
	## Friends are another matter: no damage, but they catch light and lose the reins.
	_check("a lantern's fire sets another player alight", hero.is_alight())
	_check("being alight costs no health", hero.health == hero_before)
	hero._alight_left = 0.0
	var own_fire := FirePatch.new()
	add_child(own_fire)
	own_fire.ignite(Vector3(80, 0, 80), 2.0, Combatant.Faction.MONSTER, true, pid)
	own_fire.burn_once()
	_check("but never the player who dropped it", not hero.is_alight())
	own_fire.queue_free()
	var dragon_fire := FirePatch.new()
	add_child(dragon_fire)
	dragon_fire.ignite(Vector3(80, 0, 80), 2.0)
	skeleton_before = skeleton.health
	dragon_fire.burn_once()
	_check("the dragon's fire burns the party and not its own side",
			hero.health < hero_before and skeleton.health == skeleton_before)
	_check("trees, grass and wood are flammable; rock and stone are not",
			Chunk._is_flammable("res://art/x/tree-tall.glb") and Chunk._is_flammable("res://x/grass-large.glb")
			and Chunk._is_flammable("res://x/fence.glb")
			and not Chunk._is_flammable("res://x/rock-a.glb")
			and not Chunk._is_flammable("res://x/pillar-large.glb"))
	lantern_fire.queue_free()
	dragon_fire.queue_free()
	skeleton.queue_free()

	_test_new_gear(hero)

	hero.queue_free()
	PlayerRegistry.clear()


## Power glove, bug net, fan, heart container, the shop, the hookshot's stun and the sounds.
func _test_new_gear(hero: PlayerCharacter) -> void:
	print("\n--- glove, net, fan, hearts, shop")
	hero._alight_left = 0.0
	hero.knockback_time = 0.0
	hero.visual.stop_action()
	hero.global_position = Vector3(200, 0, 200)
	hero.rotation.y = 0.0

	_check("glove, net and fan are usable equipment and are dropped on death",
			ItemDB.is_usable(ItemDB.GLOVE) and ItemDB.is_usable(ItemDB.NET)
			and ItemDB.is_usable(ItemDB.FAN) and ItemDB.is_droppable(ItemDB.GLOVE)
			and ItemDB.is_droppable(ItemDB.NET) and ItemDB.is_droppable(ItemDB.FAN))
	var found := {}
	for index in 16:
		found[ItemDB.chest_item(index, &"plains")] = true
	_check("the chests hand out every find", found.size() == ItemDB.CHEST_CYCLE.size(),
			str(found.keys()))
	_check("every item still has a number for the wire, old ones unchanged",
			ItemDB.ORDER.find(ItemDB.LANTERN) == 5 and ItemDB.ORDER.has(ItemDB.HEART)
			and ItemDB.ORDER.has(ItemDB.GLOVE) and ItemDB.ORDER.has(ItemDB.NET)
			and ItemDB.ORDER.has(ItemDB.FAN))

	## Heart containers.
	var most := hero.max_health
	_check("a heart container is taken", hero.add_item(ItemDB.HEART))
	_check("it adds one heart and fills the bar",
			hero.max_health == most + Combatant.POINTS_PER_HEART and hero.health == hero.max_health,
			"%d/%d" % [hero.health, hero.max_health])
	_check("it is used up, not carried", not hero.has_item(ItemDB.HEART))
	_check("a second one is welcome too", hero.can_take(ItemDB.HEART))
	hero.max_health = ItemDB.MAX_HEARTS * Combatant.POINTS_PER_HEART
	_check("until the bar is as long as it gets", not hero.can_take(ItemDB.HEART)
			and not hero.add_item(ItemDB.HEART))
	hero.max_health = most
	hero.health = most

	## The shop.
	_check("the net is free, so anyone can start catching", ItemDB.price(ItemDB.NET) == 0)
	_check("the shop does not sell swords", ItemDB.price(ItemDB.SWORD) < 0
			and not hero.can_buy(ItemDB.SWORD))
	hero.bugs = 0
	_check("nothing can be bought without the bugs", not hero.buy(ItemDB.GLOVE)
			and not hero.has_item(ItemDB.GLOVE))
	_check("but the net can", hero.buy(ItemDB.NET) and hero.has_item(ItemDB.NET))
	hero.bugs = ItemDB.price(ItemDB.GLOVE) + 1
	_check("with the bugs, the glove is bought and paid for",
			hero.buy(ItemDB.GLOVE) and hero.has_item(ItemDB.GLOVE) and hero.bugs == 1,
			"%d bugs left" % hero.bugs)
	_check("nobody buys a second one", not hero.can_buy(ItemDB.GLOVE))
	hero.bugs = ItemDB.price(ItemDB.HEART)
	_check("a heart can be bought", hero.buy(ItemDB.HEART) and hero.bugs == 0
			and hero.max_health == most + Combatant.POINTS_PER_HEART)

	## Bugs and the net.
	var swarm := BugSwarm.new()
	add_child(swarm)
	var homes: Array[Vector3] = [Vector3(200, 0, 202), Vector3(200, 0, 190), Vector3(240, 0, 240)]
	swarm.build(homes, _rng(5))
	for index in swarm.count():
		swarm._bugs[index]["radius"] = 0.0
	swarm._place(0.0)
	var reach := swarm.in_reach(hero.global_position, hero.facing(), PlayerCharacter.NET_REACH)
	_check("the net reaches the bug in front and not the ones behind or far off",
			reach.size() == 1 and reach[0] == 0, str(reach))
	hero.bugs = 0
	hero.equip(ItemDB.NET)
	_check("swinging the net catches it", hero.swing_net() and hero.bugs == 1,
			"%d bugs" % hero.bugs)
	_check("a caught bug is out of the air", not swarm.is_flying(0) and swarm.is_flying(1))
	_check("and cannot be caught twice", not swarm.take(0))
	swarm._place(BugSwarm.RESPAWN_TIME + 1.0)
	_check("it comes back after a while", swarm.is_flying(0))
	swarm.queue_free()

	## The fan.
	hero.visual.stop_action()
	var ahead := _a_monster()
	ahead.global_position = hero.global_position + Vector3(0, 0, 4)
	var behind := _a_monster()
	behind.global_position = hero.global_position + Vector3(0, 0, -4)
	var friend_pid := PlayerRegistry.make_pid(1, 1)
	PlayerRegistry.add_entry(friend_pid, &"knight")
	var friend := PlayerCharacter.new()
	Combatant.setup_body(friend, 0.42, 1.6)
	add_child(friend)
	friend.configure(friend_pid, ArchetypeDB.get_archetype(&"knight"))
	friend.global_position = hero.global_position + Vector3(1, 0, 5)
	var blown := hero.gust_targets(hero.global_position, hero.facing())
	_check("a gust reaches enemies and friends in front, and nobody behind",
			blown.has(ahead) and blown.has(friend) and not blown.has(behind)
			and not blown.has(hero), str(blown.size()))
	hero.add_item(ItemDB.FAN)
	var health_before := ahead.health
	ahead.velocity = Vector3.ZERO
	_check("the fan can be waved", hero.use_fan())
	_check("it shoves without hurting", ahead.health == health_before and ahead.velocity.z > 5.0
			and friend.velocity.z > 5.0, "%.1f / %.1f m/s" % [ahead.velocity.z, friend.velocity.z])
	_check("and needs a moment before the next", not hero.use_fan()
			and not hero.item_ready(ItemDB.FAN))

	## A thrown rock.
	var rock := Node3D.new()
	var rock_mesh := MeshInstance3D.new()
	rock_mesh.mesh = BoxMesh.new()
	rock.add_child(rock_mesh)
	var thrown := ThrownRock.new()
	add_child(thrown)
	thrown.launch(hero, rock, ahead.global_position + Vector3.UP * 3.0, Vector3.DOWN)
	ahead.velocity = Vector3.ZERO
	var friend_before := friend.health
	var hero_before := hero.health
	friend.global_position = ahead.global_position + Vector3(1, 0, 0)
	hero.global_position = ahead.global_position + Vector3(-1, 0, 0)
	var shards_before := _shards().size()
	thrown._shatter(ahead.global_position + Vector3(0, 0, -0.5))
	_check("a rock hurts and throws back the monster it lands on",
			ahead.health == health_before - ThrownRock.DAMAGE
			and Vector2(ahead.velocity.x, ahead.velocity.z).length() > 5.0,
			"%d -> %d" % [health_before, ahead.health])
	_check("and a player beside it", friend.health == friend_before - ThrownRock.DAMAGE)
	_check("but not the one who threw it", hero.health == hero_before)
	_check("it breaks into pieces made of its own mesh",
			_shards().size() == shards_before + 1
			and (_shards()[-1] as RockShards).mesh == rock_mesh.mesh
			and (_shards()[-1] as RockShards).piece_count() == RockShards.COUNT)

	## The hookshot's stun.
	var stunned := Monster.new()
	Combatant.setup_body(stunned, 0.45, 1.7)
	add_child(stunned)
	stunned.configure(MonsterDB.get_monster(&"skeleton_minion"))
	_check("a monster is not stunned to begin with", not stunned.is_stunned())
	stunned.stun(PlayerCharacter.HOOK_STUN)
	_check("the hookshot stuns it for 300 ms", stunned.is_stunned()
			and is_equal_approx(stunned._stun_left, 0.3))

	## Sounds.
	var silent: Array[StringName] = []
	for id: StringName in GameSfx.RECIPES:
		var stream := GameSfx.render(GameSfx.RECIPES[id])
		if stream.data.size() < 1000 or _peak(stream) < 2000:
			silent.append(id)
	_check("every placeholder sound renders to something audible", silent.is_empty(), str(silent))
	GameSfx.register()
	var missing: Array[StringName] = []
	for id: StringName in [&"attack", &"hook_fire", &"hook_grab", &"lantern", &"jump", &"hurt",
			&"chest", &"coin", &"heart", &"item", &"rock_lift", &"rock_shatter", &"rock_throw",
			&"fan", &"net", &"bug", &"buy"]:
		if not SoundManager.has_sfx(id):
			missing.append(id)
	_check("and every one the game asks for is registered", missing.is_empty(), str(missing))

	## Sound fall-off.
	_check("a sound is full volume close by, quieter further off, and silent past earshot",
			is_equal_approx(GameSfx.loudness(2.0), 1.0)
			and GameSfx.loudness(15.0) < 1.0 and GameSfx.loudness(15.0) > GameSfx.loudness(30.0)
			and GameSfx.loudness(30.0) > 0.0 and GameSfx.loudness(GameSfx.HEARING + 1.0) == 0.0,
			"%.2f / %.2f" % [GameSfx.loudness(15.0), GameSfx.loudness(30.0)])
	hero.global_position = Vector3(200, 0, 200)
	friend.global_position = hero.global_position
	_check("a sound in the world is played at the volume its distance gives it",
			is_equal_approx(GameSfx.play_at(&"coin", Vector3(200, 0, 203)), 1.0)
			and is_equal_approx(GameSfx.play_at(&"coin", Vector3(200, 0, 220)), GameSfx.loudness(20.0))
			and GameSfx.play_at(&"coin", Vector3(200, 0, 300)) == 0.0)

	## Voice chat and the mirror. `hero` listens on this machine; `friend` is the one talking.
	_check("the mirror is static gear, sold at the shop and dropped on death",
			ItemDB.is_passive(ItemDB.MIRROR) and ItemDB.STATIC.has(ItemDB.MIRROR)
			and ItemDB.price(ItemDB.MIRROR) > 0 and ItemDB.is_droppable(ItemDB.MIRROR))
	var ears: Array = [hero]
	friend.global_position = hero.global_position + Vector3(0, 0, 4)
	_check("a voice close by is at full volume",
			is_equal_approx(VoiceChat.gain_between(friend, ears), 1.0))
	friend.global_position = hero.global_position + Vector3(0, 0, 24)
	var distant := VoiceChat.gain_between(friend, ears)
	_check("it fades with distance", distant > 0.0 and distant < 0.6, "%.2f" % distant)
	friend.global_position = hero.global_position + Vector3(0, 0, 200)
	_check("and cannot be heard across the map", VoiceChat.gain_between(friend, ears) == 0.0)
	friend.add_item(ItemDB.MIRROR)
	_check("one mirror alone changes nothing", VoiceChat.gain_between(friend, ears) == 0.0)
	hero.add_item(ItemDB.MIRROR)
	_check("with a mirror at each end the voice carries any distance",
			is_equal_approx(VoiceChat.gain_between(friend, ears), 1.0))
	_check("and so does the reply", is_equal_approx(VoiceChat.gain_between(hero, [friend]), 1.0))
	friend.remove_item(ItemDB.MIRROR)
	_check("losing the mirror ends it", VoiceChat.gain_between(friend, ears) == 0.0)

	## The voice itself: packed to a byte a sample and back, close enough to be speech.
	var spoken := PackedFloat32Array()
	for index in 480:
		spoken.append(sin(index * 0.11) * 0.5)
	var packed := VoiceChat.encode(spoken)
	var heard := VoiceChat.decode(packed)
	var worst := 0.0
	for index in spoken.size():
		worst = maxf(worst, absf(heard[index] - spoken[index]))
	_check("a voice packet is one byte a sample and survives the trip",
			packed.size() == spoken.size() and worst < 0.03, "worst error %.4f" % worst)
	var stereo := PackedVector2Array()
	for index in 400:
		stereo.append(Vector2(0.4, 0.2))
	var mono := VoiceChat.downsample(stereo, 4)
	_check("the microphone is cut down to mono at a quarter of the rate",
			mono.size() == 100 and is_equal_approx(mono[0], 0.3))
	_check("silence is below the gate and speech above it",
			VoiceChat.loudness(PackedFloat32Array([0.001, -0.002, 0.001])) < VoiceChat.GATE
			and VoiceChat.loudness(spoken) > VoiceChat.GATE)
	var chat := VoiceChat.new()
	add_child(chat)
	_check("voice chat is idle outside an online match", not chat.active())
	friend.global_position = hero.global_position + Vector3(0, 0, 4)
	_check("a packet from someone in earshot is played", chat.hear(7, friend, 12000, packed) > 0.0
			and chat._voices.has(7))
	friend.global_position = hero.global_position + Vector3(0, 0, 200)
	_check("and one from out of earshot is dropped", chat.hear(7, friend, 12000, packed) == 0.0)
	chat.queue_free()

	stunned.queue_free()
	friend.queue_free()


func _shards() -> Array[Node]:
	var found: Array[Node] = []
	for node in get_tree().current_scene.get_children():
		if node is RockShards:
			found.append(node)
	return found


func _peak(stream: AudioStreamWAV) -> int:
	var peak := 0
	for index in range(0, stream.data.size() - 1, 2):
		peak = maxi(peak, absi(stream.data.decode_s16(index)))
	return peak


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

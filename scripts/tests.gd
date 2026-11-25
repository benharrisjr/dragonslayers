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
	_test_autotiles()
	_test_ledges()
	_test_boundary_and_voids()
	_test_culling()
	_test_camera_look()
	_test_combat_math()
	_test_reach()
	_test_gear()
	_test_hearts()
	_test_pid_packing()
	_test_seasons()
	_test_boomerang_and_pvp()
	_test_leaves()
	_test_armor()
	_test_dragon_flight()
	_test_charged_attacks()
	_test_river()
	_test_spill_and_bridges()
	_test_saved_worlds()
	_test_dungeons()
	_test_bombs_and_flippers()

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
	## id: [model, weapon item, attack, attack shape]
	var expected := {
		&"knight": ["Knight.glb", ItemDB.SWORD, &"sword_swing", AbilityData.Shape.MELEE_ARC],
		&"barbarian": ["Barbarian.glb", ItemDB.AXE, &"axe_cleave", AbilityData.Shape.MELEE_ARC],
		&"thief": ["Rogue_Hooded.glb", ItemDB.DAGGER, &"dagger_stab", AbilityData.Shape.MELEE_ARC],
		&"mage": ["Mage.glb", ItemDB.STAFF, &"magic_bolt", AbilityData.Shape.PROJECTILE],
		&"archer": ["Ranger.glb", ItemDB.BOW, &"bow_shot", AbilityData.Shape.PROJECTILE],
	}
	_check("five heroes, in character-select order", ArchetypeDB.ORDER == ([&"knight",
			&"barbarian", &"thief", &"mage", &"archer"] as Array[StringName]))
	for id: StringName in expected:
		var want: Array = expected[id]
		var archetype := ArchetypeDB.get_archetype(id)
		_check("%s exists" % id, archetype != null)
		if archetype == null:
			continue
		_check("%s uses %s" % [id, want[0]], archetype.model_path.ends_with(want[0]),
				archetype.model_path)
		_check("%s model on disk" % id, ResourceLoader.exists(archetype.model_path))
		_check("%s has a blurb for the character select" % id, not archetype.blurb.is_empty())
		_check("%s attacks with %s" % [id, want[2]], archetype.basic_attack != null
				and archetype.basic_attack.id == want[2] and archetype.basic_attack.shape == want[3])
		_check("%s starts with its own weapon" % id, archetype.starting_gear.has(want[1])
				and ItemDB.is_weapon(want[1]) and not ItemDB.is_droppable(want[1]))
		_check("%s's weapon has a name and a model" % id,
				not ItemDB.display_name(want[1]).is_empty()
				and ItemDB.build_model(want[1]).get_child_count() > 0)
		_check("%s has the shield only if it is the knight" % id,
				archetype.starting_gear.has(ItemDB.SHIELD) == (id == &"knight"))
		for bone: String in archetype.weapon_paths:
			_check("%s weapon %s on disk" % [id, bone],
					ResourceLoader.exists(archetype.weapon_paths[bone]),
					archetype.weapon_paths[bone])
		for clip in [archetype.idle_anim, archetype.run_anim, archetype.jump_anim,
				archetype.hit_anim, archetype.death_anim, archetype.basic_attack.animation]:
			_check("%s clip %s" % [id, clip], RigAnimations.has_clip(clip))
		_check("%s's attack is free" % id, archetype.basic_attack.magic_cost == 0.0)
	for clip in HeroPreview.PASTIMES:
		_check("character select clip %s" % clip, RigAnimations.has_clip(clip))
	_check("slot defaults start with the knight and differ per slot",
			ArchetypeDB.default_for_slot(0) == &"knight"
			and ArchetypeDB.default_for_slot(3) == &"mage")
	_check("stepping wraps round the heroes", ArchetypeDB.step(&"knight", -1) == &"archer"
			and ArchetypeDB.step(&"archer", 1) == &"knight"
			and ArchetypeDB.step(&"knight", 2) == &"thief")

	## A non-knight starts with its weapon on the first button and nothing on the second.
	var pid := PlayerRegistry.make_pid(1, 3)
	PlayerRegistry.add_entry(pid, &"archer")
	var archer := PlayerCharacter.new()
	add_child(archer)
	archer.configure(pid, ArchetypeDB.get_archetype(&"archer"))
	_check("the archer holds a bow and no shield",
			archer.gear == ([ItemDB.BOW] as Array[StringName]), str(archer.gear))
	_check("with the bow on the first button and the second empty",
			archer.hotkeys[0] == ItemDB.BOW and archer.hotkeys[1] == &"")
	_check("the bow is ready to fire", archer.item_ready(ItemDB.BOW))
	## Left alone, a hero exercises; anything at all stops it.
	archer.fidget_step(PlayerCharacter.FIDGET_AFTER - 0.5, false)
	_check("a hero standing still a moment is not exercising yet", archer.fidget == 0)
	archer.fidget_step(1.0, false)
	_check("left standing about, they start push-ups or sit-ups", archer.fidget in [1, 2]
			and PlayerCharacter.FIDGETS[archer.fidget] in ["sim/Push_Ups", "sim/Sit_Ups"])
	for clip in PlayerCharacter.FIDGETS:
		if clip != "":
			_check("exercise clip %s exists" % clip, RigAnimations.has_clip(clip))
	var first := archer.fidget
	archer.fidget_step(PlayerCharacter.FIDGET_SWITCH.y + 0.1, false)
	_check("and swap to the other after a while", archer.fidget != first and archer.fidget > 0)
	archer.fidget_step(0.016, true)
	_check("moving or pressing anything stops it at once", archer.fidget == 0)
	archer.fidget_step(PlayerCharacter.FIDGET_AFTER - 1.0, false)
	_check("and the wait starts over", archer.fidget == 0)
	PlayerRegistry.roster.erase(pid)
	PlayerRegistry.despawn(pid)
	archer.queue_free()


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
	_check("the dragon model exists", ResourceLoader.exists(Dragon.MODEL_PATH))
	if not ResourceLoader.exists(Dragon.MODEL_PATH):
		return
	_check("and its licence travels with it", FileAccess.file_exists(
			"res://art/models/dragon_mattbas_LICENSE.txt"))
	var instance := (load(Dragon.MODEL_PATH) as PackedScene).instantiate()
	var skeleton := _find_skeleton(instance)
	_check("has a skeleton", skeleton != null)
	if skeleton != null:
		## Every bone the attack poses turn must exist by name: they are the interface.
		for bone_name: String in DragonAnimator.DRIVEN_BONES:
			_check("bone %s" % bone_name, skeleton.find_bone(bone_name) >= 0)
	var player := _find_player(instance)
	_check("has its own animations", player != null)
	if player != null:
		var names := ", ".join(player.get_animation_list())
		for wanted: String in [Dragon.ANIM_IDLE, Dragon.ANIM_WALK, Dragon.ANIM_FLY]:
			var found := false
			for clip: StringName in player.get_animation_list():
				found = found or String(clip).begins_with(wanted)
			_check("a %s loop" % wanted, found, names)
	var aabb := _combined_aabb(instance)
	var tall := aabb.size.y * Dragon.MODEL_SCALE
	var span := aabb.size.x * Dragon.MODEL_SCALE
	_check("stands 4-6 m tall", tall > 4.0 and tall < 6.5, "%.2f m" % tall)
	_check("wings 18-26 m across", span > 18.0 and span < 26.0, "%.2f m" % span)
	_check("feet on the origin plane", absf(aabb.position.y) < 0.05, "%.3f" % aabb.position.y)
	instance.free()
	## Its scales follow the season: pink, green, red, and its own blue in winter. Checked on the
	## palette read straight out of the model file, since a headless run has no texture data.
	var texture := _dragon_palette()
	_check("the dragon has a palette to paint", texture != null and not texture.is_empty())
	if texture != null and not texture.is_empty():
		var wanted := {Season.Kind.SPRING: 0.93, Season.Kind.SUMMER: 0.33, Season.Kind.FALL: 0.0}
		var names := {Season.Kind.SPRING: "pink", Season.Kind.SUMMER: "green",
				Season.Kind.FALL: "red"}
		for kind: Season.Kind in wanted:
			var result := _repainted(texture, Dragon.season_image(texture, kind), wanted[kind])
			_check("in %s the dragon's scales are %s" % [Season.NAMES[kind], names[kind]],
					result["scales"] > 0 and result["wrong"] == 0, str(result))
			_check("and its belly, mouth and eyes are untouched", result["moved"] == 0, str(result))
		_check("in winter it keeps its blue",
				(Dragon.SEASON_SCALES[Season.Kind.WINTER] as Array).is_empty())
	for clip: String in ["breath", "air_breath", "claw", "tail_sweep", "wing_flap", "roar", "death"]:
		_check("pose clip %s" % clip, DragonAnimator.duration(clip) > 0.5)
	for id: String in Dragon.ATTACKS:
		var spec: Dictionary = Dragon.ATTACKS[id]
		_check("%s lands inside its pose" % id,
				float(spec["hit_at"]) < DragonAnimator.duration(spec["clip"]))


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


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
	var coil := 0.0
	for bone in DragonAnimator.TAIL:
		coil += (coiled.get(bone, Quaternion.IDENTITY) as Quaternion).get_angle()
	_check("the tail coils before the sweep", coil > 1.0, "%.2f rad along the tail" % coil)
	## Opposite signs on the yaw: the tail has to travel through the arc behind the dragon
	## rather than merely twitching to one side.
	_check("the tail whips through to the other side",
			whipped.has("Tail4")
			and signf((coiled["Tail4"] as Quaternion).y) != signf((whipped["Tail4"] as Quaternion).y))
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
	_test_terraces_and_shrines()

	## Slopes. A ramp tile rises exactly one level across its length, which at 1.5 m over 2 m
	## is about 37 degrees -- inside the 50 degree limit a body can walk.
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
	## A ramp up every terrace for the road, and more round the mountain: at least two per
	## terrace on top of the road's one.
	var terraces := WorldGenerator.SUMMIT_RISE / WorldGenerator.TERRACE_RISE
	var ramps := ramp_tiles / WorldGenerator.MOUNTAIN_RAMP
	_check("the mountain has a road up and more ramps between its terraces",
			ramps >= terraces * 3, "%d ramps for %d terraces" % [ramps, terraces])
	## More than one way up: with the long ascent left out entirely, the terrace ramps alone
	## still reach the summit, on any seed.
	var unreachable := 0
	for seed in 12:
		var no_ascent := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"mountain"), _rng(100 + seed), {
			"base": WorldGenerator.base_level(WorldGenerator.Tier.SUMMIT), "ascent_side": -1,
			"sides": PackedInt32Array([14, 14, 14, 14]),
		})
		if no_ascent.reach[half * tiles + half] != 1:
			unreachable += 1
	_check("the terrace ramps alone reach the summit, without the long ascent", unreachable == 0,
			"%d of 12 seeds cut off" % unreachable)
	_check("every ramp tile rises exactly one level", ramp_ok)
	var slope_degrees := rad_to_deg(atan(ChunkMesher.STEP_HEIGHT / ChunkMesher.TILE_SIZE))
	_check("ramps are shallow enough to walk", slope_degrees < 45.0, "%.0f degrees" % slope_degrees)

	## A chunk next to higher ground cuts a ramp up to it, its top flush with the border.
	var ground := WorldGenerator.base_level(WorldGenerator.Tier.GROUND)
	var high_ground := WorldGenerator.base_level(WorldGenerator.Tier.HIGHLANDS)
	var stepped := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"forest"), _rng(21), {
		"base": ground, "ascent_side": -1,
		"sides": PackedInt32Array([high_ground, ground, TerrainData.MAP_EDGE, ground]),
	})
	var top_reached := false
	for lane in tiles:
		var index := lane * tiles + tiles - 1
		if stepped.is_slope(tiles - 1, lane) and stepped.reach[index] == 1 \
				and is_equal_approx(stepped.edge(tiles - 1, lane, 0).x, high_ground):
			top_reached = true
	_check("a ramp runs up to a higher neighbour and can be walked", top_reached)

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
	_check_deep_water(beach, "sea")

	## The lake: deep in the middle, ringed by shallows a level below the shore that slope up to
	## it, so it can be waded out of.
	var lake := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"lake"), _rng(8))
	var middle := (tiles / 2) * tiles + tiles / 2
	_check("the lake's middle is deep water", lake.heights[middle] <= lake.base_level - 2
			and lake.deep[middle] == 1, "level %d against %d" % [lake.heights[middle], lake.base_level])
	var sloped := 0
	var shallows := 0
	for index in tiles * tiles:
		if lake.heights[index] == lake.base_level - 1 and lake.deep[index] == 0:
			shallows += 1
			if lake.slopes[index] == TerrainData.Slope.SMOOTH and lake.reach[index] == 1:
				sloped += 1
	_check("round it, shallows that slope up to the shore and are not deep", sloped > 40,
			"%d of %d shallow tiles" % [sloped, shallows])
	## Water over most of the chunk, islands in it, and a bridge out to each.
	var wet := 0
	for index in tiles * tiles:
		if lake.heights[index] < lake.base_level:
			wet += 1
	_check("the lake fills most of its chunk", wet > tiles * tiles * 0.4, "%d of %d tiles" % [wet, tiles * tiles])
	var islands_reached := lake.spans.size() > 0
	for span in lake.spans:
		islands_reached = islands_reached and lake.reach[span.y * tiles + span.x] == 1 \
				and lake.reach[span.w * tiles + span.z] == 1
	_check("islands in it, each reached over a bridge", lake.bridges.size() >= 2 and islands_reached,
			"%d bridges" % lake.bridges.size())
	## Across many maps: two chunks of it side by side, never touching the sea.
	var lake_problems := ""
	for world_seed in range(40):
		var plan := WorldGenerator.plan(world_seed)
		var cells: Array[int] = []
		for cell in 16:
			if plan["biomes"][cell] == &"lake":
				cells.append(cell)
				for other in 16:
					if plan["tiers"][other] == WorldGenerator.Tier.SEA and WorldGenerator._chebyshev(cell, other) <= 1:
						lake_problems += " seed %d: lake %d beside the sea;" % [world_seed, cell]
		if cells.size() != 2 or WorldGenerator._chebyshev(cells[0], cells[1]) != 1 \
				or WorldGenerator._side_towards(cells[0], cells[1]) < 0:
			lake_problems += " seed %d: lake in %s;" % [world_seed, str(cells)]
	_check("the lake fills two chunks side by side, with land between it and the sea (40 seeds)",
			lake_problems == "", lake_problems)
	_check_deep_water(lake, "lake")

	_test_walkable_world()


## Still water with a deep part: flagged deep where the bed is well under the surface, never
## walked into (it is a drop, not a slope), and with a hazard-free border round it.
func _check_deep_water(terrain: TerrainData, label: String) -> void:
	var deep := 0
	var walked_in := 0
	var too_shallow := 0
	for index in terrain.size * terrain.size:
		if terrain.deep[index] == 0:
			continue
		deep += 1
		if terrain.reach[index] == 1:
			walked_in += 1
		var x := index % terrain.size
		var z := index / terrain.size
		if terrain.surface_level(x, z) * ChunkMesher.STEP_HEIGHT > terrain.still_surface - 0.5:
			too_shallow += 1
	_check("the %s has deep water" % label, deep > 50, "%d tiles" % deep)
	_check("deep %s water is a step down, not walked into" % label, walked_in == 0,
			"%d deep tiles reachable on foot" % walked_in)
	_check("and too deep to stand in", too_shallow == 0, "%d" % too_shallow)


## The promise the whole terrain rework rests on: with no feather, no hookshot and no jump, a
## player can walk from the town to the dragon, to the beach, and into every chunk on the map.
func _test_walkable_world() -> void:
	var tiles := WorldGenerator.CHUNK_TILES
	var grid := WorldGenerator.GRID
	var failures := ""
	var seeds := [4242, 7, 99991, 31, 2026, 8, 1, 2, 3, 5, 11, 13, 17, 19, 23, 555, 808, 1234]
	for world_seed: int in seeds:
		var plan := WorldGenerator.plan(world_seed)
		var tiers: PackedInt32Array = plan["tiers"]
		var terrains: Array[TerrainData] = []
		for index in grid * grid:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(world_seed) ^ (index * 2654435761)
			terrains.append(WorldGenerator.heightmap(BiomeLibrary.get_biome(plan["biomes"][index]),
					rng, WorldGenerator.context(tiers, index, plan["river"], plan["entrances"],
							plan["shape_seed"])))

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
					## The river is deep; nobody wades across it from one chunk to the next.
					if terrain.is_water(x, z) or beyond.is_water(ox, oz):
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
	## Preferably on a side that meets a neighbour flush: that is where a chunk joins the map.
	var size := terrain.size
	for index in size * size:
		var x := index % size
		var z := index / size
		if terrain.heights[index] != terrain.base_level or terrain.reach[index] != 1 \
				or terrain.is_water(x, z):
			continue
		for side in 4:
			var on_side: bool = [x == size - 1, z == size - 1, x == 0, z == 0][side]
			if on_side and terrain.side_levels[side] == terrain.base_level:
				return index
	for index in terrain.size * terrain.size:
		if terrain.rim(index % terrain.size, index / terrain.size) == 0 \
				and terrain.heights[index] == terrain.base_level and terrain.reach[index] == 1:
			return index
	return 0


## The mountain's terraces, one per dungeon, and each dungeon's shrine on its own.
func _test_terraces_and_shrines() -> void:
	_check("the mountain has a terrace for every dungeon",
			WorldGenerator.TERRACES == Dungeon.IDS.size(),
			"%d terraces, %d dungeons" % [WorldGenerator.TERRACES, Dungeon.IDS.size()])
	var mountain := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"mountain"), _rng(5))
	var thin := ""
	for terrace in range(1, WorldGenerator.TERRACES + 1):
		var level := mountain.base_level + terrace * WorldGenerator.TERRACE_RISE
		var count := 0
		for index in mountain.heights.size():
			if mountain.heights[index] == level and mountain.slopes[index] == TerrainData.Slope.FLAT:
				count += 1
		## A ring two tiles deep round the mountain, give or take what the ramps take.
		if count < 150:
			thin += " %d: %d tiles;" % [terrace, count]
	_check("each terrace is its own ring round the mountain", thin == "", thin)

	var misplaced := ""
	for world_seed in [3, 17, 42]:
		var plan := WorldGenerator.plan(world_seed)
		var cell: int = (plan["biomes"] as Array).find(&"mountain")
		var chunk := Chunk.new()
		add_child(chunk)
		chunk.build(cell, &"mountain", _rng(world_seed * 100 + cell),
				WorldGenerator.context(plan["tiers"], cell, plan["river"], plan["entrances"],
						plan["shape_seed"]))
		if chunk.shrines.size() != Dungeon.IDS.size():
			misplaced += " seed %d: %d shrines;" % [world_seed, chunk.shrines.size()]
		for terrace in chunk.shrines.size():
			var shrine := chunk.shrines[terrace]
			var tile := Vector2i(floori(shrine.position.x / ChunkMesher.TILE_SIZE),
					floori(shrine.position.z / ChunkMesher.TILE_SIZE))
			var level := chunk.terrain.base_level + (terrace + 1) * WorldGenerator.TERRACE_RISE
			var at := tile.y * chunk.terrain.size + tile.x
			if shrine.dungeon_id != Dungeon.IDS[terrace] or chunk.terrain.heights[at] != level \
					or chunk.terrain.reserved[at] == 1 or chunk.terrain.reach[at] == 0:
				misplaced += " seed %d: %s at %s;" % [world_seed, shrine.dungeon_id, tile]
		chunk.free()
	_check("a shrine per dungeon, in order up the terraces, clear of the ramps", misplaced == "",
			misplaced)

	## Dark until its dungeon's guardian is beaten -- the big chest unlocked -- then lit.
	var dungeon := Dungeon.new()
	dungeon.dungeon_id = &"well"
	dungeon.add_to_group(Dungeon.GROUP)
	add_child(dungeon)
	dungeon.big_chest = TreasureChest.new()
	dungeon.add_child(dungeon.big_chest)
	dungeon.big_chest.lock()
	var shrine := MountainShrine.new()
	shrine.setup(&"well")
	add_child(shrine)
	var dark := not shrine.is_beaten()
	dungeon.big_chest.unlock_quietly()
	_check("a shrine lights once its dungeon's guardian is beaten", dark and shrine.is_beaten())
	shrine.free()
	dungeon.free()


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


## The smoothed cliffs: straight ones stay put, corners and staircases round off, and the drawn
## ground matches TerrainData.surface_at with no gaps in it.
func _test_autotiles() -> void:
	print("\n--- autotiled cliffs")
	const N := 16

	## A lone 3x3 plateau: its straight cliffs stay on their tile edges, its corners round off --
	## further in than the old one-quadrant arcs reached.
	var plateau := TerrainData.new(N, 0)
	for z in range(4, 7):
		for x in range(4, 7):
			plateau.heights[z * N + x] = 1
	plateau.bake()
	_check("a straight cliff stays on its tile edge",
			is_equal_approx(plateau.surface_at(5.5, 3.97), 0.0)
			and is_equal_approx(plateau.surface_at(5.5, 4.03), 1.0)
			and is_equal_approx(plateau.surface_at(6.97, 5.5), 1.0)
			and is_equal_approx(plateau.surface_at(7.03, 5.5), 0.0))
	_check("a plateau's corners are rounded off",
			is_equal_approx(plateau.surface_at(4.2, 4.2), 0.0)
			and is_equal_approx(plateau.surface_at(6.8, 6.8), 0.0)
			and is_equal_approx(plateau.surface_at(4.5, 4.5), 1.0)
			and is_equal_approx(plateau.surface_at(5.5, 5.5), 1.0))

	## A 3x3 pit: its inner corners are filled in.
	var pit := TerrainData.new(N, 1)
	for z in range(4, 7):
		for x in range(4, 7):
			pit.heights[z * N + x] = 0
	pit.bake()
	_check("a pit's corners are filled",
			is_equal_approx(pit.surface_at(4.2, 4.2), 1.0)
			and is_equal_approx(pit.surface_at(5.5, 5.5), 0.0)
			and is_equal_approx(pit.surface_at(5.5, 4.03), 0.0))

	## A diagonal staircase comes out as one sloping cliff, through the middle of its steps.
	var stairs := TerrainData.new(N, 0)
	for z in N:
		for x in N:
			if x + z <= N - 2:
				stairs.heights[z * N + x] = 1
	stairs.bake()
	var straight := true
	for i in range(4, N - 5):
		for along: float in [float(i), i + 0.5]:
			var line := N - 0.5 - along
			straight = straight and is_equal_approx(stairs.surface_at(along, line - 0.3), 1.0) \
					and is_equal_approx(stairs.surface_at(along, line + 0.3), 0.0)
	_check("a diagonal staircase is smoothed into one sloping cliff", straight)

	## Ramps, pits, the river and reserved tiles keep square corners.
	for kind in ["ramp", "hole", "river", "reserved"]:
		var spoiled := TerrainData.new(N, 0)
		for z in range(4, 7):
			for x in range(4, 7):
				spoiled.heights[z * N + x] = 1
		var at := 3 * N + 3
		match kind:
			"ramp":
				spoiled.slopes[at] = TerrainData.Slope.RISE_PX
			"hole":
				spoiled.heights[at] = ChunkMesher.HOLE
			"river":
				spoiled.water[at] = 1
			"reserved":
				spoiled.reserved[at] = 1
		spoiled.bake()
		_check("a corner touching a %s is left square" % kind,
				is_equal_approx(spoiled.surface_at(4.03, 4.03), 1.0)
				and is_equal_approx(spoiled.surface_at(6.8, 6.8), 0.0))

	## The drawn ground: everything at once, built into a mesh and probed from above.
	var mixed := TerrainData.new(N, 1)
	for z in N:
		for x in N:
			var level := 1
			if x + z <= 9:
				level = 2
			if x >= 10 and z >= 10 and x <= 13 and z <= 13:
				level = 0
			if x == 11 and z == 3:
				level = 3
			mixed.heights[z * N + x] = level
	mixed.slopes[6 * N + 12] = TerrainData.Slope.RISE_NX
	mixed.bake()
	var mesh := ChunkMesher.build(mixed, BiomeLibrary.get_biome(&"plains"), _rng(5))
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var buckets := {}
	var top_area := 0.0
	var wrong_facing := 0
	for i in range(0, vertices.size(), 3):
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		var face := (b - a).cross(c - a)
		## Godot draws clockwise faces: the geometric normal points away from the viewer.
		if face.length() > 0.0001 and face.normalized().dot(normals[i]) > -0.9:
			wrong_facing += 1
		if normals[i].y < 0.5:
			continue
		top_area += absf(face.y) * 0.5
		var lo := Vector2i(floori(minf(a.x, minf(b.x, c.x)) / 2.0), floori(minf(a.z, minf(b.z, c.z)) / 2.0))
		var hi := Vector2i(floori(maxf(a.x, maxf(b.x, c.x)) / 2.0 - 0.0001), floori(maxf(a.z, maxf(b.z, c.z)) / 2.0 - 0.0001))
		for bz in range(lo.y, hi.y + 1):
			for bx in range(lo.x, hi.x + 1):
				var key := Vector2i(bx, bz)
				if not buckets.has(key):
					buckets[key] = []
				(buckets[key] as Array).append(i)
	var full := float(N * N) * ChunkMesher.TILE_SIZE * ChunkMesher.TILE_SIZE
	_check("the ground covers the chunk exactly once", absf(top_area - full) < 0.5,
			"%.2f of %.2f m2" % [top_area, full])
	_check("every face is wound to face out", wrong_facing == 0, "%d faces" % wrong_facing)
	var misses := 0
	var off := 0
	var probe_rng := _rng(77)
	for _probe in 1500:
		var px := probe_rng.randf_range(0.01, N * 2.0 - 0.01)
		var pz := probe_rng.randf_range(0.01, N * 2.0 - 0.01)
		var expected := mixed.surface_at(px / 2.0, pz / 2.0) * ChunkMesher.STEP_HEIGHT
		var best := -INF
		for i: int in buckets.get(Vector2i(floori(px / 2.0), floori(pz / 2.0)), []):
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(px, 50.0, pz), Vector3.DOWN,
					vertices[i], vertices[i + 1], vertices[i + 2])
			if hit != null:
				best = maxf(best, (hit as Vector3).y)
		if best == -INF:
			misses += 1
		elif absf(best - expected) > 0.02:
			off += 1
	_check("no gaps in the drawn ground", misses == 0, "%d of 1500 probes fell through" % misses)
	_check("the drawn ground matches surface_at", off == 0, "%d of 1500 probes off" % off)
	_check("the reshaped ground still builds a collider", mesh.create_trimesh_shape() != null)

	## A real chunk, the busiest kind: how long it takes and how big it comes out.
	var mountain := BiomeLibrary.get_biome(&"mountain")
	var heights := WorldGenerator.heightmap(mountain, _rng(4))
	var started := Time.get_ticks_usec()
	var built := ChunkMesher.build(heights, mountain, _rng(4))
	var took := (Time.get_ticks_usec() - started) / 1000.0
	var triangles := built.surface_get_array_len(0) / 3
	print("        mountain chunk: %d triangles in %.0f ms" % [triangles, took])
	_check("a mountain chunk stays a manageable size", triangles < 60000, "%d triangles" % triangles)


## Ledges: stone lips along some cliff tops that nobody can walk, jump or be knocked off.
func _test_ledges() -> void:
	print("\n--- ledges")
	## Where the generator puts them, over a spread of real chunks.
	var ledged := 0
	var bad_footing := 0
	var trapped := 0
	for world_seed in [1, 2, 3, 5, 8]:
		for biome_id in [&"plains", &"fields", &"forest", &"temple", &"desert", &"mountain"]:
			var biome := BiomeLibrary.get_biome(biome_id)
			var terrain := WorldGenerator.heightmap(biome, _rng(world_seed * 31 + biome_id.length()))
			var size := terrain.size
			var half := (size - 1) * 0.5
			for index in size * size:
				if terrain.ledge[index] == 0:
					continue
				ledged += 1
				var x := index % size
				var z := index / size
				if terrain.water[index] == 1 or terrain.deep[index] == 1 or terrain.reserved[index] == 1 \
						or terrain.slopes[index] != 0 or terrain.is_hole(x, z) or terrain.rim(x, z) == 0 \
						or (biome_id == &"mountain" and Vector2(x - half, z - half).length() \
						<= WorldGenerator.ARENA_RADIUS_TILES):
					bad_footing += 1
			## High ground that can only be jumped up to keeps an open cliff top to jump up at.
			var seen := PackedByteArray()
			seen.resize(size * size)
			for start in size * size:
				if seen[start] == 1 or terrain.reach[start] == 1 or terrain.ledge[start] == 0:
					continue
				var queue: Array[int] = [start]
				seen[start] = 1
				var head := 0
				var open := false
				while head < queue.size():
					var at := queue[head]
					head += 1
					var x := at % size
					var z := at / size
					if terrain.ledge[at] == 0 and WorldGenerator._over_cliff(terrain, x, z):
						open = true
					for side in 4:
						if terrain.can_walk(x, z, side):
							var next := (z + ChunkMesher.NEIGHBOUR_DZ[side]) * size + x + ChunkMesher.NEIGHBOUR_DX[side]
							if seen[next] == 0:
								seen[next] = 1
								queue.append(next)
				if not open:
					trapped += 1
	_check("some cliffs carry ledges", ledged > 100, "%d ledged tiles" % ledged)
	_check("ledges keep off pits, water, ramps, the rim and the arena", bad_footing == 0,
			"%d misplaced" % bad_footing)
	_check("high ground keeps a gap to jump up at", trapped == 0, "%d sealed off" % trapped)

	## A ledge in use: a plateau with one side ledged, built for real.
	const N := 12
	var plateau := TerrainData.new(N, 0)
	plateau.reach.fill(1)
	for z in range(3, 9):
		for x in range(3, 9):
			plateau.heights[z * N + x] = 1
	for z in range(3, 9):
		plateau.ledge[z * N + 8] = 1
	plateau.bake()
	var segments: Array = []
	ChunkMesher.build(plateau, BiomeLibrary.get_biome(&"plains"), _rng(2), segments)
	var only_east := not segments.is_empty()
	for segment: Array in segments:
		## Every piece on the ledged column of tiles (x = 8, from 16 m), never the open sides.
		only_east = only_east and ((segment[0] as Vector2).x >= 15.99 or (segment[1] as Vector2).x >= 15.99)
	_check("only the ledged side gets a lip", only_east, "%d pieces" % segments.size())
	## The pieces join into one curve that bends gently round the plateau's rounded corners.
	var paths := ChunkMesher.ledge_paths(segments)
	var sharpest := 0.0
	for path: Array in paths:
		var points: PackedVector2Array = path[0]
		for i in range(1, points.size() - 1):
			sharpest = maxf(sharpest, absf((points[i] - points[i - 1]).angle_to(points[i + 1] - points[i])))
	_check("a ledge's pieces join into one smooth lip", paths.size() == 1 and rad_to_deg(sharpest) < 20.0,
			"%d paths, sharpest bend %.0f degrees" % [paths.size(), rad_to_deg(sharpest)])
	_check("the lips draw", ChunkMesher.build_ledges(paths, BiomeLibrary.get_biome(&"plains")) != null)
	var guard := StaticBody3D.new()
	guard.collision_layer = Combatant.LAYER_LEDGE
	guard.collision_mask = 0
	var guard_shape := CollisionShape3D.new()
	guard_shape.shape = ChunkMesher.ledge_shape(ChunkMesher.ledge_paths(segments))
	guard.add_child(guard_shape)
	add_child(guard)
	var body := CharacterBody3D.new()
	Combatant.setup_body(body, 0.4, 1.6)
	add_child(body)
	var top := ChunkMesher.STEP_HEIGHT
	## Walking east off the ledged side is stopped; west off the open side is not.
	body.global_position = Vector3(16.0, top + 0.9, 12.0)
	_check("a ledge stops anyone walking off it", body.test_move(body.global_transform, Vector3(3.0, 0.0, 0.0)))
	_check("a ledge stops a jump or knockback over it",
			body.test_move(body.global_transform, Vector3(3.0, 2.5, 0.0)))
	body.global_position = Vector3(8.0, top + 0.9, 12.0)
	_check("an open cliff top can still be stepped off",
			not body.test_move(body.global_transform, Vector3(-3.0, 0.0, 0.0)))
	var rock := PhysicsRayQueryParameters3D.create(Vector3(16.0, top + 1.0, 12.0), Vector3(20.0, top + 1.0, 12.0))
	rock.collision_mask = Combatant.LAYER_WORLD | Combatant.LAYER_SCENERY | Combatant.LAYER_COMBATANT
	_check("thrown things pass over a ledge", body.get_world_3d().direct_space_state.intersect_ray(rock).is_empty())
	body.queue_free()
	guard.queue_free()


# --- combat ----------------------------------------------------------------------------------

## The walls that stop players leaving the world, and the caps sealing the bottom of every pit.
func _test_boundary_and_voids() -> void:
	print("\n--- world edges")

	## The walls round the map: invisible, solid, and taller than anything that could carry a
	## body over them -- the summit and a knockback off it included.
	var summit := ChunkMesher.height_to_world(WorldGenerator.summit_level())
	_check("the boundary walls stand well over the mountain", WorldBoundary.top() > summit + 30.0,
			"walls %.0f m, summit %.0f m" % [WorldBoundary.top(), summit])
	var boundary := WorldBoundary.new()
	add_child(boundary)
	boundary.build()
	var walls := boundary.get_node_or_null("Walls") as StaticBody3D
	_check("the boundary is solid on all four sides", walls != null and walls.get_child_count() == 4)
	var drawn := 0
	for node in boundary.find_children("*", "MeshInstance3D", true, false):
		drawn += 1
	_check("the boundary draws nothing", drawn == 0)
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
	## Same direction as the Z/C keys, so the two controls do not fight each other.
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
	_check("a player's attack catches another player too", friendly.has(ally)
			and late.can_hit(ally) and not late.can_hit(late))
	_check("but auto-aim still only picks enemies", not late.is_hostile_to(ally))
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
					| Combatant.LAYER_SCENERY | Combatant.LAYER_LEDGE))
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
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).has(skeleton))
	skeleton.global_position = Vector3(0, 0, -8.0)
	_check("a swing does not reach across the chunk",
			not CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).has(skeleton))
	skeleton.global_position = Vector3(0, 0, 2.5)
	_check("a swing does not hit behind the attacker",
			not CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).has(skeleton))
	skeleton.global_position = Vector3(0, 0, -900.0)

	## The regression itself: standing outside a big target's capsule must still be in reach.
	dragon.global_position = Vector3(0, 0, -4.0)
	_check("a swing reaches a dragon from outside its collision capsule",
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).has(dragon),
			"melee range %.1f m, dragon radius %.1f m" % [swing.range, dragon.hit_radius])
	dragon.global_position = Vector3(0, 0, -9.0)
	_check("a dragon is not swingable from across the arena",
			not CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).has(dragon))

	## A tall target's mid-body sits metres above the attacker's; a fixed vertical gate rejected
	## it outright.
	dragon.global_position = Vector3(0, 0, -3.0)
	_check("a dragon's height does not put it out of the vertical gate",
			CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).has(dragon))
	dragon.global_position = Vector3(0, 12.0, -3.0)
	_check("something on the plateau above is still out of reach",
			not CombatResolver.arc_targets(get_tree(), attacker, Vector3.ZERO, forward, swing).has(dragon))
	dragon.global_position = Vector3(0, 0, -900.0)

	## Projectiles fly at mid-body height, so the sphere test has to be done there too --
	## measuring to the feet meant the test could never succeed for a flat shot.
	skeleton.global_position = Vector3(0, 0, -6.0)
	var in_flight := skeleton.hit_centre()
	_check("a projectile at the target's chest scores",
			CombatResolver.radius_targets(get_tree(), attacker, in_flight,
					Projectile.HIT_RADIUS).has(skeleton))
	_check("a projectile level with the target's feet does not",
			not CombatResolver.radius_targets(get_tree(), attacker,
					skeleton.global_position + Vector3(0, -1.6, 0),
					Projectile.HIT_RADIUS).has(skeleton))

	for body in [attacker, skeleton, dragon]:
		body.queue_free()


func _test_hearts() -> void:
	print("\n--- hearts")
	var hearts := HeartsDisplay.new()
	_check("a heart is two points", Combatant.POINTS_PER_HEART == 2)
	hearts.set_health(6, 6)
	_check("six points is three full hearts", hearts.max_hearts() == 3)
	hearts.set_health(5, 6)
	_check("five points is two and a half hearts", hearts.current == 5 and hearts.max_hearts() == 3)
	hearts.set_health(1, 6)
	_check("one point still shows three hearts", hearts.max_hearts() == 3)
	hearts.set_health(8, 10)
	_check("upgrading max hearts adds a heart", hearts.max_hearts() == 5)
	hearts.free()

	var body := Combatant.new()
	body.max_health = 6
	add_child(body)
	body.set_max_health(10)
	_check("raising max health keeps current health", body.health == 6)
	_check("hearts read from points", absf(body.hearts() - 3.0) < 0.001)
	body.queue_free()

	## The numbers themselves: a hero has six, a skeleton two, and every attack is one point.
	_check("a hero starts with six health", ArchetypeDB.get_archetype(&"knight").max_hearts
			* Combatant.POINTS_PER_HEART == 6)
	var skeletons_ok := true
	for id: StringName in [&"skeleton_minion", &"skeleton_warrior", &"skeleton_rogue",
			&"skeleton_mage"]:
		var monster := MonsterDB.get_monster(id)
		if monster.max_health != 2 or monster.damage != 1:
			skeletons_ok = false
	_check("every skeleton has two health and hits for one", skeletons_ok)
	var attacks_ok := true
	for id: StringName in ArchetypeDB.ORDER:
		if ArchetypeDB.get_archetype(id).basic_attack.damage != 1:
			attacks_ok = false
	_check("every hero's attack does one damage", attacks_ok and ThrownRock.DAMAGE == 1
			and Boomerang.DAMAGE == 1)
	_check("the dragon is still tougher than that", Dragon.MAX_HEALTH > 2)
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
	hero.take_damage(1, front, 9.0, 0.3)
	_check("a blocked hit does no damage", hero.health == before, "%d -> %d" % [before, hero.health])
	_check("a blocked hit shoves a third as hard",
			Vector2(hero.velocity.x, hero.velocity.z).length()
					< 9.0 * hero.knockback_resistance * 0.5,
			"%.1f m/s" % Vector2(hero.velocity.x, hero.velocity.z).length())
	hero.take_damage(1, behind, 9.0, 0.3)
	_check("a hit from behind gets past the shield", hero.health == before - 1)
	hero.blocking = false
	hero.take_damage(1, front, 9.0, 0.3)
	_check("a lowered shield blocks nothing", hero.health == before - 2)

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


func _test_seasons() -> void:
	print("\n--- seasons")
	var rolled := {}
	for world_seed in range(1, 200):
		rolled[Season.roll(world_seed)] = true
	_check("every season comes up across seeds", rolled.size() == 4, str(rolled.keys()))
	_check("a seed always gives the same season", Season.roll(4242) == Season.roll(4242))
	Season.forced = Season.from_name("winter")
	_check("--season forces one", Season.roll(4242) == Season.Kind.WINTER)
	Season.forced = -1
	_check("season names parse", Season.from_name("fall") == Season.Kind.FALL
			and Season.from_name("nonsense") == -1)

	var plains := BiomeLibrary.get_biome(&"plains")
	var beach := BiomeLibrary.get_biome(&"beach")
	var mountain := BiomeLibrary.get_biome(&"mountain")
	var desert := BiomeLibrary.get_biome(&"desert")
	var colours: Array[Color] = []
	for kind in 4:
		colours.append(Season.ground_color(&"plains", plains.ground_color, kind))
		_check("%s leaves the beach sand" % Season.NAMES[kind],
				Season.ground_color(&"beach", beach.ground_color, kind) == beach.ground_color)
		_check("%s leaves the mountain rock" % Season.NAMES[kind],
				Season.ground_color(&"mountain", mountain.ground_color, kind) == mountain.ground_color
				and not Season.snows_on(&"mountain", kind))
	_check("spring is greener than summer", colours[0].g - colours[0].r > colours[1].g - colours[1].r)
	_check("fall is orange", colours[2].r > colours[2].g and colours[2].g > colours[2].b)
	_check("winter is near white", colours[3].v > 0.75 and colours[3].s < 0.15)
	_check("the desert keeps its sand until it snows",
			Season.ground_color(&"desert", desert.ground_color, Season.Kind.SUMMER) == desert.ground_color
			and Season.snows_on(&"desert", Season.Kind.WINTER))
	var tree := "res://art/kenney_survival-kit/Models/GLB format/tree.glb"
	_check("trees turn in the fall", (Season.prop_swap(tree, Season.Kind.FALL)[0] as String)
			.ends_with("tree-autumn.glb"))
	_check("and are snowed on in winter", (Season.prop_swap(tree, Season.Kind.WINTER)[0] as String)
			.ends_with("tree-snow.glb"))
	_check("and are left alone in spring", Season.prop_swap(tree, Season.Kind.SPRING)[0] == tree)
	for kind in [Season.Kind.FALL, Season.Kind.WINTER]:
		for file: String in Season.TREE_SWAPS:
			var swap: Array = Season.TREE_SWAPS[file][0 if kind == Season.Kind.FALL else 1]
			_check("seasonal tree %s exists" % (swap[0] as String).get_file(),
					ResourceLoader.exists(swap[0]))
	_check("rocks never change", Season.prop_swap(
			"res://art/kenney_survival-kit/Models/GLB format/rock-a.glb", Season.Kind.WINTER)[1] == 1.0)

	## Summer: long grass on the plains, cut by a swing in front and not behind.
	var before := Season.current
	Season.current = Season.Kind.SUMMER
	var chunk := Chunk.new()
	add_child(chunk)
	chunk.build(5, &"plains", GameState.chunk_rng(5), {})
	var grass := chunk.ground_cover
	## Counted in tufts (each about ten blades): a few hundred tiles' worth.
	_check("summer grows long grass on grassland", grass != null and grass.blade_count() > 700,
			str(grass.blade_count() if grass != null else 0))
	if grass != null:
		var roots: PackedVector3Array = grass._blocks[0]["roots"]
		var at := grass.global_position + roots[0]
		## Standing a metre to its left: facing away, the blade is behind the swing.
		var behind := grass.cut(at - Vector3(1.0, 0.0, 0.0), 2.0, Vector3.LEFT, 60.0)
		_check("a swing leaves what is behind it", (grass._blocks[0]["cut"] as PackedByteArray)[0] == 0,
				"%d cut" % behind)
		var cut := grass.cut(at - Vector3(1.0, 0.0, 0.0), 2.0, Vector3.RIGHT, 90.0)
		_check("and cuts what is in front of it", cut > 0
				and (grass._blocks[0]["cut"] as PackedByteArray)[0] == 1)
		var standing := grass.blade_count() - grass.cut_count()
		_check("cut grass stays cut", grass.cut(at - Vector3(1.0, 0.0, 0.0), 2.0, Vector3.RIGHT,
				90.0) == 0 and grass.blade_count() - grass.cut_count() == standing)
		_check("fire flattens all round", grass.cut(at, 3.0) > 0)
		_check("no grass grows on a ramp, in the water or under a prop", _grass_on_open_ground(chunk))
	chunk.free()

	Season.current = Season.Kind.SPRING
	var meadow := Chunk.new()
	add_child(meadow)
	meadow.build(5, &"plains", GameState.chunk_rng(5), {})
	_check("spring scatters flowers", meadow.ground_cover != null
			and meadow.ground_cover.mode == GrassField.Mode.FLOWERS
			and meadow.ground_cover.get_child_count() > 0)
	_check("flowers cannot be cut", meadow.ground_cover == null
			or meadow.ground_cover.cut(meadow.global_position + Vector3(64, 0, 64), 200.0) == 0)
	meadow.free()

	Season.current = Season.Kind.FALL
	var shore := Chunk.new()
	add_child(shore)
	shore.build(5, &"beach", GameState.chunk_rng(5), {})
	_check("nothing grows on the beach", shore.ground_cover == null)
	shore.free()
	Season.current = before

	## Winter: a print goes into the snow, and fills back in.
	var snow := SnowTrails.new()
	var spot := Vector3(100.0, 5.0, 100.0)
	_check("fresh snow is untouched", snow.depth_at(spot) == 0.0)
	snow.stamp(spot, 0.5)
	_check("a step presses the snow down", snow.depth_at(spot) > 0.6, str(snow.depth_at(spot)))
	_check("only where it was trodden", snow.depth_at(spot + Vector3(3.0, 0.0, 0.0)) == 0.0)
	snow._refill(SnowTrails.REFILL_TIME * 0.5)
	var half := snow.depth_at(spot)
	_check("it fills back in over time", half < 0.6 and half > 0.1, str(half))
	snow._refill(SnowTrails.REFILL_TIME)
	_check("until it is gone", snow.depth_at(spot) == 0.0 and snow._trodden.is_empty())
	snow.stamp(Vector3(-50.0, 0.0, 9000.0), 1.0)
	_check("a print off the map is ignored", snow._trodden.is_empty())
	snow.free()


func _grass_on_open_ground(chunk: Chunk) -> bool:
	var tiles := WorldGenerator.CHUNK_TILES
	for block in chunk.ground_cover._blocks:
		for root: Vector3 in block["roots"]:
			var x := clampi(int(root.x / ChunkMesher.TILE_SIZE), 0, tiles - 1)
			var z := clampi(int(root.z / ChunkMesher.TILE_SIZE), 0, tiles - 1)
			if not chunk.is_open_ground(x, z):
				return false
	return true


func _test_boomerang_and_pvp() -> void:
	print("\n--- boomerang and friendly hits")
	var thrower_pid := PlayerRegistry.make_pid(1, 2)
	var friend_pid := PlayerRegistry.make_pid(1, 3)
	PlayerRegistry.add_entry(thrower_pid, &"archer")
	PlayerRegistry.add_entry(friend_pid, &"thief")
	var thrower := PlayerCharacter.new()
	Combatant.setup_body(thrower, 0.42, 1.6)
	add_child(thrower)
	thrower.configure(thrower_pid, ArchetypeDB.get_archetype(&"archer"))
	var friend := PlayerCharacter.new()
	Combatant.setup_body(friend, 0.42, 1.6)
	add_child(friend)
	friend.configure(friend_pid, ArchetypeDB.get_archetype(&"thief"))
	var spot := Vector3(-300.0, 50.0, -300.0)
	thrower.global_position = spot
	friend.global_position = spot + Vector3(0.0, 0.0, 4.0)

	_check("a hero has six health", thrower.max_health == 6 and thrower.health == 6)
	_check("one player's attack can land on another", thrower.can_hit(friend))
	friend.take_damage(1, thrower.global_position, 7.0, 0.3)
	_check("and costs them half a heart, and shoves them", friend.health == 5
			and Vector2(friend.velocity.x, friend.velocity.z).length() > 1.0)
	friend.global_position = spot + Vector3(0.0, 0.0, 4.0)
	friend.velocity = Vector3.ZERO
	friend.knockback_time = 0.0

	_check("no boomerang, no throw", not thrower.throw_boomerang())
	thrower.add_item(ItemDB.BOOMERANG)
	_check("the boomerang is a usable", ItemDB.is_usable(ItemDB.BOOMERANG)
			and thrower.equipped() == ItemDB.BOOMERANG)
	_check("it is in the chests and the shop", ItemDB.CHEST_CYCLE.has(ItemDB.BOOMERANG)
			and ItemDB.price(ItemDB.BOOMERANG) > 0)
	_check("it can be thrown", thrower.throw_boomerang() and thrower.boomerang != null)
	_check("one at a time", not thrower.throw_boomerang() and not thrower.item_ready(ItemDB.BOOMERANG))
	var flying := thrower.boomerang
	var before := friend.health
	for _step in 30:
		flying._physics_process(1.0 / 60.0)
		friend.global_position = spot + Vector3(0.0, 0.0, 4.0)
	_check("it hits for one point", friend.health == before - 1, "%d -> %d" % [before, friend.health])
	_check("and stuns", friend.is_stunned())
	for _step in 200:
		if thrower.boomerang == null:
			break
		flying._physics_process(1.0 / 60.0)
		friend.global_position = spot + Vector3(0.0, 0.0, 4.0)
	_check("each body is hit only once a throw", friend.health == before - 1)
	_check("and it comes back to hand", thrower.boomerang == null
			and thrower.item_ready(ItemDB.BOOMERANG))
	_check("it never hits the one who threw it", thrower.health == 6)

	## A stunned player cannot act.
	friend._stun_left = 1.0
	friend.add_item(ItemDB.BOOMERANG)
	_check("a stunned player cannot throw", not friend.throw_boomerang())
	friend._stun_left = 0.0

	for pid in [thrower_pid, friend_pid]:
		PlayerRegistry.roster.erase(pid)
		PlayerRegistry.despawn(pid)
	thrower.queue_free()
	friend.queue_free()


func _test_leaves() -> void:
	print("\n--- fall leaves")
	var before := Season.current
	Season.current = Season.Kind.FALL
	var chunk := Chunk.new()
	add_child(chunk)
	chunk.build(6, &"plains", GameState.chunk_rng(6), {})
	var leaves := chunk.leaves
	_check("the fall lays leaves on grassland", leaves != null and leaves.leaf_count() > 1000,
			str(leaves.leaf_count() if leaves != null else 0))
	_check("and no grass or flowers", chunk.ground_cover == null)
	if leaves != null:
		var first: Vector3 = (leaves._blocks[0]["positions"] as PackedVector3Array)[0]
		var floor_y: float = (leaves._blocks[0]["floor"] as PackedFloat32Array)[0]
		_check("some of them are heaped in piles", leaves.highest_leaf() > 0.0
				and _tallest_pile(leaves) > 0.3, "%.2f" % _tallest_pile(leaves))
		var at := leaves.global_position + first
		var kicked := leaves.kick(at, 0.8, Vector3.RIGHT, 4.0)
		_check("walking through them kicks them up", kicked > 0 and leaves.flying_count() == kicked)
		_check("a leaf already in the air is not kicked again", leaves.kick(at, 0.8, Vector3.RIGHT,
				4.0) == 0)
		for _step in 240:
			leaves._physics_process(1.0 / 60.0)
		_check("and they settle again", leaves.flying_count() == 0)
		var landed: Vector3 = (leaves._blocks[0]["positions"] as PackedVector3Array)[0]
		_check("somewhere new, lying on the ground", landed.distance_to(first) > 0.2
				and absf(landed.y - floor_y) < 0.1, "%s -> %s" % [first, landed])
		_check("fire burns them away", leaves.burn(at, 3.0) > 0 and leaves.burnt_count() > 0)
		_check("and burnt leaves cannot be kicked", leaves.kick(at, 0.5, Vector3.RIGHT, 4.0) == 0
				or leaves.burnt_count() > 0)
	chunk.free()
	Season.current = Season.Kind.SPRING
	var spring := Chunk.new()
	add_child(spring)
	spring.build(6, &"plains", GameState.chunk_rng(6), {})
	_check("no leaves outside the fall", spring.leaves == null)
	spring.free()
	Season.current = before


func _tallest_pile(leaves: LeafField) -> float:
	var tallest := 0.0
	for block in leaves._blocks:
		var positions: PackedVector3Array = block["positions"]
		var floors: PackedFloat32Array = block["floor"]
		for index in positions.size():
			tallest = maxf(tallest, positions[index].y - floors[index])
	return tallest


func _test_armor() -> void:
	print("\n--- armour")
	var pid := PlayerRegistry.make_pid(1, 1)
	PlayerRegistry.add_entry(pid, &"knight")
	var hero := PlayerCharacter.new()
	Combatant.setup_body(hero, 0.42, 1.6)
	add_child(hero)
	hero.configure(pid, ArchetypeDB.get_archetype(&"knight"))
	hero.global_position = Vector3(-400.0, 50.0, -400.0)
	var away := hero.global_position + Vector3(0.0, 0.0, -3.0)

	_check("everyone starts at armour 0", hero.armor_level == 0)
	_check("level 0 takes every point", hero.armored(1) == 1 and hero.armored(2) == 2)
	_check("armour is sold and found", ItemDB.price(ItemDB.ARMOR) > 0
			and ItemDB.CHEST_CYCLE.has(ItemDB.ARMOR) and ItemDB.is_consumable(ItemDB.ARMOR)
			and not ItemDB.is_droppable(ItemDB.ARMOR))
	_check("taking armour raises the level", hero.add_item(ItemDB.ARMOR) and hero.armor_level == 1
			and not hero.gear.has(ItemDB.ARMOR))
	var through := 0
	for _hit in 8:
		through += hero.armored(1)
	_check("level 1 takes half: four of eight one-point hits land", through == 4, str(through))
	var lands: Array[int] = []
	for _hit in 4:
		lands.append(hero.armored(1))
	_check("every second hit, not half a point each", lands == ([0, 1, 0, 1] as Array[int]),
			str(lands))
	_check("a two-point hit is one point", hero.armored(2) == 1)

	hero.add_item(ItemDB.ARMOR)
	_check("a second raises it to 2", hero.armor_level == 2)
	through = 0
	for _hit in 8:
		through += hero.armored(1)
	_check("level 2 takes a quarter: two of eight hits land", through == 2, str(through))
	_check("and that is the most there is", not hero.can_take(ItemDB.ARMOR)
			and not hero.add_item(ItemDB.ARMOR) and hero.armor_level == 2)

	var health := hero.health
	for _hit in 4:
		hero.take_damage(1, away, 0.0, 0.0)
	_check("real hits go through the armour", hero.health == health - 1,
			"%d -> %d" % [health, hero.health])
	hero.blocking = true
	health = hero.health
	for _hit in 4:
		hero.take_damage(1, hero.global_position + Vector3(0.0, 0.0, 3.0), 0.0, 0.0)
	_check("a raised shield still takes nothing", hero.health == health)
	hero.blocking = false

	## The clothes: dyed while armoured, their own colours without.
	var dyed := _dyed_surfaces(hero)
	_check("armour dyes the clothes", dyed > 0, "%d surfaces" % dyed)
	var hue: float = (_first_dye(hero).get_shader_parameter("dye_hue") as float)
	_check("level 2 is red", hue < 0.05 or hue > 0.95, str(hue))
	hero.set_armor_level(1)
	hue = _first_dye(hero).get_shader_parameter("dye_hue")
	_check("level 1 is blue", absf(hue - 0.6) < 0.05, str(hue))
	_check("the weapons in hand are not dyed", _weapons_dyed(hero) == 0)
	hero.set_armor_level(0)
	_check("level 0 is the hero's own colours", _dyed_surfaces(hero) == 0)

	PlayerRegistry.roster.erase(pid)
	PlayerRegistry.despawn(pid)
	hero.queue_free()


func _dyed_surfaces(hero: PlayerCharacter) -> int:
	var count := 0
	for mesh in hero.visual._body_meshes(hero.visual._model_root):
		for surface in mesh.get_surface_override_material_count():
			if mesh.get_surface_override_material(surface) is ShaderMaterial:
				count += 1
	return count


func _first_dye(hero: PlayerCharacter) -> ShaderMaterial:
	for mesh in hero.visual._body_meshes(hero.visual._model_root):
		for surface in mesh.get_surface_override_material_count():
			var material := mesh.get_surface_override_material(surface) as ShaderMaterial
			if material != null:
				return material
	return null


func _weapons_dyed(hero: PlayerCharacter) -> int:
	var count := 0
	for bone: String in ["handslot.r", "handslot.l"]:
		var held := hero.visual.attachment(bone)
		if held == null:
			continue
		for mesh in Culling.meshes_under(held):
			for surface in mesh.get_surface_override_material_count():
				if mesh.get_surface_override_material(surface) is ShaderMaterial:
					count += 1
	return count


func _test_dragon_flight() -> void:
	print("\n--- dragon flights and fire")
	var perch := Vector3(400.0, 23.4, 400.0)
	var one := DragonFlight.tour(77, perch, null)
	var again := DragonFlight.tour(77, perch, null)
	var other := DragonFlight.tour(78, perch, null)
	_check("a seed always flies the same route", one.length == again.length
			and one.position_at(150.0) == again.position_at(150.0))
	_check("a different seed flies another", one.position_at(150.0) != other.position_at(150.0))
	_check("it is a proper tour of the map", one.length > 600.0 and one.duration() > 30.0,
			"%.0f m" % one.length)
	_check("off the perch and back onto it", one.position_at(0.0).is_equal_approx(perch)
			and one.position_at(one.length).is_equal_approx(perch))
	var span := WorldGenerator.GRID * WorldGenerator.CHUNK_SIZE
	var inside := true
	var high := true
	var gentle := true
	var previous := one.position_at(0.0)
	var along := DragonFlight.STEP
	while along < one.length:
		var at := one.position_at(along)
		if at.x < 0.0 or at.z < 0.0 or at.x > span or at.z > span:
			inside = false
		if one.is_cruising(along) and at.y < perch.y + DragonFlight.CLEARANCE * 0.9:
			high = false
		if absf(at.y - previous.y) > DragonFlight.SLOPE * DragonFlight.STEP + 0.01:
			gentle = false
		previous = at
		along += DragonFlight.STEP
	_check("it stays over the map", inside)
	_check("it cruises well above the ground", high)
	_check("and climbs and dives no steeper than it can", gentle)
	var home := DragonFlight.home(Vector3(100.0, 40.0, 120.0), perch, null)
	_check("a flight home ends on the perch", home.position_at(home.length).is_equal_approx(perch)
			and home.position_at(0.0).is_equal_approx(Vector3(100.0, 40.0, 120.0)))

	## Fire melts snow and burns flowers.
	var snow := SnowTrails.new()
	var spot := Vector3(200.0, 5.0, 200.0)
	snow.melt(spot, 3.0)
	_check("fire melts the snow", snow.melt_at(spot) > 0.9 and snow.depth_at(spot) == 0.0)
	snow._refill(SnowTrails.REFILL_TIME)
	_check("and melted snow comes back more slowly than a footprint fills",
			snow.melt_at(spot) > 0.5, "%.2f" % snow.melt_at(spot))
	snow.free()
	var before := Season.current
	Season.current = Season.Kind.SPRING
	var meadow := Chunk.new()
	add_child(meadow)
	meadow.build(5, &"plains", GameState.chunk_rng(5), {})
	var flowers := meadow.ground_cover
	if flowers != null and flowers.flower_count() > 0:
		var first: Transform3D = flowers._beds[0]["transforms"][0]
		_check("a sword cannot cut flowers", flowers.cut(meadow.global_position + first.origin,
				3.0, Vector3.RIGHT, 360.0) == 0)
		_check("but fire burns them", flowers.burn(meadow.global_position + first.origin, 3.0) > 0
				and flowers.burnt_flowers() > 0)
	else:
		_check("spring has flowers to burn", false)
	meadow.free()
	Season.current = before

	_check("the dragon roars", GameSfx.RECIPES.has(&"roar") and GameSfx.RECIPES.has(&"wings"))
	_check("and is heard a long way off", GameSfx.loudness(60.0 / Dragon.ROAR_REACH) > 0.2
			and GameSfx.loudness(60.0) == 0.0)


func _test_charged_attacks() -> void:
	print("\n--- charged attacks")
	var shapes := {
		&"knight": AbilityData.Shape.MELEE_ARC, &"barbarian": AbilityData.Shape.MELEE_ARC,
		&"thief": AbilityData.Shape.PROJECTILE, &"archer": AbilityData.Shape.PROJECTILE,
		&"mage": AbilityData.Shape.NOVA,
	}
	for id: StringName in shapes:
		var charged := ArchetypeDB.get_archetype(id).charged_attack
		_check("%s has a charged attack" % id, charged != null and charged.shape == shapes[id])
		if charged == null:
			continue
		_check("%s's charged attack does one damage" % id, charged.damage == 1)
		_check("%s's charged animation exists" % id, RigAnimations.has_clip(charged.animation))
		match charged.shape:
			AbilityData.Shape.MELEE_ARC:
				_check("%s spins all the way round" % id, charged.arc_degrees >= 180.0)
			AbilityData.Shape.PROJECTILE:
				_check("%s throws a flurry all round" % id, charged.projectile_count >= 8)
			AbilityData.Shape.NOVA:
				_check("%s's ring reaches further than a sword" % id, charged.radius > 5.0)

	## A spin reaches what is behind, where an ordinary swing does not.
	var spinner := Combatant.new()
	spinner.faction = Combatant.Faction.PLAYER
	spinner.hit_radius = 0.42
	spinner.hit_height = 1.6
	add_child(spinner)
	spinner.global_position = Vector3(-500.0, 0.0, -500.0)
	var behind := Combatant.new()
	behind.hit_radius = 0.45
	behind.hit_height = 1.7
	add_child(behind)
	behind.global_position = spinner.global_position + Vector3(0.0, 0.0, 2.5)
	var forward := Vector3(0, 0, -1)
	_check("an ordinary swing misses what is behind", not CombatResolver.arc_targets(get_tree(),
			spinner, spinner.global_position, forward, AbilityDB.get_ability(&"sword_swing"))
			.has(behind))
	_check("a spin catches it", CombatResolver.arc_targets(get_tree(), spinner,
			spinner.global_position, forward, AbilityDB.get_ability(&"sword_spin")).has(behind))
	spinner.queue_free()
	behind.queue_free()

	## Holding and letting go.
	var pid := PlayerRegistry.make_pid(1, 0)
	PlayerRegistry.add_entry(pid, &"barbarian")
	var hero := PlayerCharacter.new()
	Combatant.setup_body(hero, 0.42, 1.6)
	add_child(hero)
	hero.configure(pid, ArchetypeDB.get_archetype(&"barbarian"))
	hero.global_position = Vector3(-520.0, 50.0, -520.0)
	_check("not charging until the attack button is held", not hero.charge_step(1.0, true)
			and hero.charge_level == 0.0)
	hero._charge_time = 0.0
	hero.charge_step(0.1, true)
	_check("a tap shows no charge", hero.charge_level == 0.0)
	_check("and letting go of a tap does nothing", not hero.charge_step(0.016, false))
	hero._charge_time = 0.0
	hero.charge_step(0.5, true)
	_check("holding builds the charge", hero.charge_level > 0.3 and hero.charge_level < 1.0,
			"%.2f" % hero.charge_level)
	_check("letting go early does nothing", not hero.charge_step(0.016, false)
			and hero.charge_level == 0.0)
	hero._charge_time = 0.0
	hero.charge_step(PlayerCharacter.CHARGE_TIME, true)
	_check("held long enough, it is full", hero.charge_level >= 1.0)
	_check("letting go unleashes the charged attack", hero.charge_step(0.016, false)
			and hero.cooldown_fraction(hero.archetype.charged_attack) > 0.0)
	_check("and the charge is spent", hero.charge_level == 0.0 and hero._charge_time < 0.0)
	hero._charge_time = 0.0
	hero.charge_step(PlayerCharacter.CHARGE_TIME, true)
	hero._on_damaged(1, hero.global_position + Vector3.FORWARD)
	_check("a hit knocks the charge out", hero.charge_level == 0.0)
	PlayerRegistry.roster.erase(pid)
	PlayerRegistry.despawn(pid)
	hero.queue_free()


## Compares a repainted palette with the original: every blue scale texel should now be `hue`,
## and every other texel exactly as it was.
func _repainted(before: Image, after: Image, hue: float) -> Dictionary:
	var result := {"scales": 0, "wrong": 0, "moved": 0}
	for y in before.get_height():
		for x in before.get_width():
			var was := before.get_pixel(x, y)
			var now := after.get_pixel(x, y)
			if was.h >= 0.5 and was.h <= 0.75 and was.s >= 0.25:
				result["scales"] += 1
				var off := absf(now.h - hue)
				if minf(off, 1.0 - off) > 0.02:
					result["wrong"] += 1
			elif not now.is_equal_approx(was):
				result["moved"] += 1
	return result


## The dragon's 16x16 palette, decoded from the PNG embedded in the .glb.
func _dragon_palette() -> Image:
	var bytes := FileAccess.get_file_as_bytes(Dragon.MODEL_PATH)
	if bytes.size() < 20:
		return null
	var json_length := bytes.decode_u32(12)
	var info: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	var binary := 20 + json_length + 8
	var view: Dictionary = info["bufferViews"][int(info["images"][0]["bufferView"])]
	var start := binary + int(view.get("byteOffset", 0))
	var image := Image.new()
	image.load_png_from_buffer(bytes.slice(start, start + int(view["byteLength"])))
	return image


## The mountain spilling into the chunks round it, the bluffs and their bridges, the river's land
## bridges and its deeper cut near the source -- built for whole maps, as the game builds them.
func _test_spill_and_bridges() -> void:
	print("\n--- the mountain's spill, bluffs and bridges")
	var tiles := WorldGenerator.CHUNK_TILES
	var seams := ""
	var spilled := 0
	var wavy := 0
	var sky := 0
	var sky_problems := ""
	var land := 0
	var land_problems := ""
	var sink_problems := ""
	for world_seed: int in [4242, 7, 31, 2026, 3, 17]:
		var plan := WorldGenerator.plan(world_seed)
		var tiers: PackedInt32Array = plan["tiers"]
		var mountain: int = (plan["biomes"] as Array).find(&"mountain")
		var terrains: Array[TerrainData] = []
		for index in 16:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(world_seed) ^ (index * 2654435761)
			terrains.append(WorldGenerator.heightmap(BiomeLibrary.get_biome(plan["biomes"][index]),
					rng, WorldGenerator.context(tiers, index, plan["river"], plan["entrances"],
					plan["shape_seed"])))
		for index in 16:
			var terrain := terrains[index]
			## What each chunk thinks lies across its border is what the next chunk built there.
			for side in 4:
				var other := WorldGenerator.neighbour_cell(index, side)
				if other < 0:
					continue
				for lane in tiles:
					var mine := WorldGenerator._from_side(tiles, side, 0, lane)
					var theirs := WorldGenerator._from_side(tiles, (side + 2) % 4, 0, lane)
					var beyond := terrains[other]
					if terrain.is_water(mine.x, mine.y) or beyond.is_water(theirs.x, theirs.y) \
							or beyond.is_slope(theirs.x, theirs.y):
						continue
					if terrain.edge_level(side, lane) != beyond.level(theirs.x, theirs.y):
						seams += " seed %d: %d->%d lane %d;" % [world_seed, index, other, lane]
						break
			## The mountain's terraces, over the border in the chunks beside it, with an edge that
			## wanders rather than following the border.
			if index != mountain and WorldGenerator._chebyshev(index, mountain) == 1:
				var reaches := {}
				for lane in tiles:
					var deepest := -1
					for depth in tiles / 2:
						var side := WorldGenerator._side_towards(index, mountain)
						if side < 0:
							break
						var tile := WorldGenerator._from_side(tiles, side, depth, lane)
						if terrain.level(tile.x, tile.y) >= terrain.base_level + WorldGenerator.TERRACE_RISE \
								and not terrain.is_water(tile.x, tile.y):
							deepest = depth
					if deepest >= 0:
						reaches[deepest] = true
				if not reaches.is_empty():
					spilled += 1
				if reaches.size() >= 4:
					wavy += 1
			for spec: Dictionary in terrain.bridges:
				var from: Vector2i = spec["from"]
				var to: Vector2i = spec["to"]
				var level: int = spec["level"]
				match spec.get("kind", &"plank"):
					&"sky":
						sky += 1
						## Resting on bluff tops at both ends, over lower ground, the far one
						## reached across it.
						var ends := [from, to]
						for end: Vector2i in ends:
							if terrain.level(end.x, end.y) != level or terrain.reach[end.y * tiles + end.x] == 0:
								sky_problems += " seed %d chunk %d end %s;" % [world_seed, index, end]
						var middle := (from + to) / 2
						if terrain.level(middle.x, middle.y) >= level:
							sky_problems += " seed %d chunk %d: nothing under it;" % [world_seed, index]
					&"land":
						land += 1
						## Over the river, flagged as a bridge, between banks at its deck.
						var over := 0
						for z in range(from.y, to.y + 1):
							for x in range(from.x, to.x + 1):
								if terrain.is_water(x, z):
									over += 1
									if not terrain.is_bridge(x, z):
										land_problems += " seed %d chunk %d (%d,%d) open;" % [world_seed, index, x, z]
								elif terrain.is_slope(x, z) or terrain.level(x, z) != level - int(spec["lift"]) + 1:
									## Its curves up are its own: the banks under them stay flat.
									land_problems += " seed %d chunk %d (%d,%d) bank;" % [world_seed, index, x, z]
						## High enough over the water to raft under: 2.5 m and more.
						var span: Vector2i = spec["span"]
						var wet := Vector2i(span.x, from.y + 1) if spec["along_x"] else Vector2i(from.x + 1, span.x)
						if level * ChunkMesher.STEP_HEIGHT - terrain.water_surface(wet.x, wet.y) < 2.5:
							land_problems += " seed %d chunk %d: too low to raft under;" % [world_seed, index]
						if over == 0:
							land_problems += " seed %d chunk %d: no river under it;" % [world_seed, index]
		## The cut: deeper on the mountain and the chunk below it, ordinary after.
		var cells: Array = (plan["river"] as Dictionary).get("cells", [])
		for step in cells.size():
			var want := WorldGenerator.RIVER_SINK if tiers[cells[step]] >= WorldGenerator.Tier.HIGHLANDS else 0.0
			var terrain := terrains[cells[step]]
			## The water only ever goes down: along the current, and out over each border.
			for index in tiles * tiles:
				if terrain.water[index] == 0:
					continue
				var x := index % tiles
				var z := index / tiles
				if want > 0.0 and terrain.sink_at(x, z) != want:
					sink_problems += " seed %d step %d not cut;" % [world_seed, step]
					break
				var ahead := Vector2i((Vector2(x + 0.5, z + 0.5) + terrain.flow[index] * 1.2).floor())
				if terrain.is_water(ahead.x, ahead.y) \
						and terrain.water_surface(ahead.x, ahead.y) > terrain.water_surface(x, z) + 0.01:
					sink_problems += " seed %d step %d rises at %d,%d;" % [world_seed, step, x, z]
					break
			if step + 1 < cells.size():
				var exit: Array = (plan["river"]["parts"][cells[step]] as Dictionary)["exit"]
				var below := terrains[cells[step + 1]]
				var out := WorldGenerator._from_side(tiles, exit[0], 0, exit[1])
				var into := WorldGenerator._from_side(tiles, (int(exit[0]) + 2) % 4, 0, exit[1])
				if below.water_surface(into.x, into.y) > terrain.water_surface(out.x, out.y) + 0.01:
					sink_problems += " seed %d step %d: up into the next chunk;" % [world_seed, step]
	_check("every chunk knows the level across its borders, lane by lane", seams == "", seams)
	_check("the mountain spills over into the chunks round it", spilled >= 12,
			"%d chunks over 6 seeds" % spilled)
	_check("and its edge there wanders rather than following the border", wavy >= 8,
			"%d chunks" % wavy)
	_check("bluffs with bridges between them, on bluff tops at both ends", sky >= 10 \
			and sky_problems == "", "%d bridges;%s" % [sky, sky_problems])
	## And a land bridge's own top: level with the banks at its ends, its deck over the water.
	var deck_ok := false
	for world_seed: int in [7, 17, 31]:
		var plan := WorldGenerator.plan(world_seed)
		for cell: int in (plan["river"] as Dictionary).get("cells", []):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(world_seed) ^ (cell * 2654435761)
			var terrain := WorldGenerator.heightmap(BiomeLibrary.get_biome(plan["biomes"][cell]),
					rng, WorldGenerator.context(plan["tiers"], cell, plan["river"], plan["entrances"],
					plan["shape_seed"]))
			for spec: Dictionary in terrain.bridges:
				if spec.get("kind", &"") != &"land" or deck_ok:
					continue
				var built := RiverBuilder.build_land_bridge(spec, terrain, BiomeLibrary.get_biome(plan["biomes"][cell]))
				var faces: PackedVector3Array = ((built.get_node("Deck") as StaticBody3D).get_child(0) as CollisionShape3D).shape.get_faces()
				var top := -INF
				var bottom := INF
				for point in faces:
					top = maxf(top, point.y)
					bottom = minf(bottom, point.y)
				var deck := int(spec["level"]) * ChunkMesher.STEP_HEIGHT
				var bank := deck - (int(spec["lift"]) - 1) * ChunkMesher.STEP_HEIGHT
				deck_ok = is_equal_approx(top, deck) and bottom < bank + 0.1
				built.free()
	_check("a land bridge curves up from its banks to its deck, solid all the way", deck_ok)
	_check("land bridges over the river, high enough to raft under, curving up from flat banks", land >= 4 \
			and land_problems == "", "%d land bridges;%s" % [land, land_problems])
	_check("the river runs a metre deeper near its source, its water only ever going down", sink_problems == "", sink_problems)

	_test_organic_edges()

	## A bluff's far end is walked to over the bridge: without the span, it is cut off.
	var forest := BiomeLibrary.get_biome(&"plains")
	var found := false
	for attempt in 30:
		var terrain := WorldGenerator.heightmap(forest, _rng(700 + attempt))
		if terrain.spans.is_empty():
			continue
		var span := terrain.spans[0]
		var far := span.w * tiles + span.z
		var crossed := terrain.reach[far] == 1
		terrain.spans.clear()
		terrain.flood_reach()
		_check("a bluff's far end is reached over its bridge, and only that way",
				crossed and terrain.reach[far] == 0)
		found = true
		break
	if not found:
		_check("a bluff's far end is reached over its bridge, and only that way", false, "no bluffs")


## Every step in a real chunk's drawn ground has a wall facing its low side: no slits to see
## through, above all where smoothed cliffs meet ground that keeps square edges.
## The sun is up exactly half of each day, and night is dim, not black.
func _test_day_and_night() -> void:
	var up := 0
	var unit := true
	for i in 1440:
		var direction := DayNight.sun_direction((i + 0.5) / DayNight.DAY)
		up += int(direction.y > 0.0)
		unit = unit and absf(direction.length() - 1.0) < 0.001
	_check("the sun is above the horizon twelve minutes of twenty-four", up == 720, "%d s" % up)
	_check("the sun goes round in a circle", unit
			and DayNight.sun_direction(0.25).is_equal_approx(-DayNight.sun_direction(0.75)))
	_check("it is light at noon and dark at midnight", DayNight.daylight(0.25) > 0.99
			and DayNight.daylight(0.75) < 0.01)


## Paths join every ramp, and torches stand along them, off the paths themselves.
func _test_paths() -> void:
	var problems := ""
	for world_seed: int in [17, 3, 42, 4242, 7, 31, 2026, 1, 8, 21]:
		var plan := WorldGenerator.plan(world_seed)
		var terrains: Array[TerrainData] = []
		for index in 16:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(world_seed) ^ (index * 2654435761)
			terrains.append(WorldGenerator.heightmap(BiomeLibrary.get_biome(plan["biomes"][index]),
					rng, WorldGenerator.context(plan["tiers"], index, plan["river"], plan["entrances"],
					plan["shape_seed"])))
		var network := PathNetwork.lay(terrains, plan["biomes"], plan["shape_seed"])
		var torches := network.torches()
		var count := 0
		for cell: int in torches:
			for tile: Vector2i in torches[cell]:
				count += 1
				var at := tile.y * 64 + tile.x
				if terrains[cell].path[at] != 0 or terrains[cell].is_water(tile.x, tile.y):
					problems += " seed %d: torch in the way;" % world_seed
		if not network.joined or count < 25:
			problems += " seed %d: joined %s, %d torches;" % [world_seed, network.joined, count]
	_check("paths join every slope, with torches beside them", problems == "", problems)


func _test_no_cracks() -> void:
	var plan := WorldGenerator.plan(17)
	var cell := 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(17) ^ (cell * 2654435761)
	var biome := BiomeLibrary.get_biome(plan["biomes"][cell])
	var terrain := WorldGenerator.heightmap(biome, rng, WorldGenerator.context(plan["tiers"], cell,
			plan["river"], plan["entrances"], plan["shape_seed"]))
	var vertices: PackedVector3Array = ChunkMesher.build(terrain, biome, rng) \
			.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var buckets := {}
	for i in range(0, vertices.size(), 3):
		var box := AABB(vertices[i], Vector3.ZERO).expand(vertices[i + 1]).expand(vertices[i + 2]).grow(0.01)
		for x in range(floori(box.position.x), floori(box.end.x) + 1):
			for z in range(floori(box.position.z), floori(box.end.z) + 1):
				var key := Vector2i(x, z)
				if not buckets.has(key):
					buckets[key] = []
				(buckets[key] as Array).append(i)
	var across := 63 * 8
	var heights := PackedFloat32Array()
	for z in across:
		for x in across:
			heights.append(terrain.surface_at((x + 0.37) / 8.0, (z + 0.41) / 8.0))
	var steps := 0
	var missing := 0
	for z in across - 1:
		for x in across - 1:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := heights[z * across + x]
				var b := heights[(z + d.y) * across + x + d.x]
				if absf(a - b) < 0.9 or minf(a, b) < -50.0:
					continue
				steps += 1
				var p := Vector3((x + 0.37) / 4.0, (a + b) * 0.5 * ChunkMesher.STEP_HEIGHT + 0.05, (z + 0.41) / 4.0)
				var q := p + Vector3(d.x, 0.0, d.y) * 0.25
				var from := p if a < b else q
				var to := q if a < b else p
				var walled := false
				for key: Vector2i in [Vector2i(floori(p.x), floori(p.z)), Vector2i(floori(q.x), floori(q.z))]:
					for i: int in buckets.get(key, []):
						var face := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
						if face.dot(to - from) > 0.0 and Geometry3D.segment_intersects_triangle(from, to,
								vertices[i], vertices[i + 1], vertices[i + 2]) != null:
							walled = true
							break
					if walled:
						break
				if not walled:
					missing += 1
	_check("every step in the ground has a wall facing its low side", steps > 1000 and missing == 0,
			"%d of %d without" % [missing, steps])


## Chunks meeting lower ones spill over the border in lobes, coloured as their own ground; the
## lake wanders; and the crates and gems.
func _test_organic_edges() -> void:
	_test_no_cracks()
	_test_day_and_night()
	_test_paths()
	var tiles := WorldGenerator.CHUNK_TILES
	var lobed := 0
	var depths := {}
	var owned := true
	for world_seed: int in [7, 31]:
		var plan := WorldGenerator.plan(world_seed)
		var tiers: PackedInt32Array = plan["tiers"]
		for index in 16:
			if tiers[index] != WorldGenerator.Tier.GROUND:
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(world_seed) ^ (index * 2654435761)
			var ctx := WorldGenerator.context(tiers, index, plan["river"], plan["entrances"],
					plan["shape_seed"])
			var terrain := WorldGenerator.heightmap(BiomeLibrary.get_biome(plan["biomes"][index]),
					rng, ctx)
			for side in 4:
				var other := WorldGenerator.neighbour_cell(index, side)
				if other < 0 or tiers[other] != WorldGenerator.Tier.HIGHLANDS:
					continue
				lobed += 1
				for lane in range(8, tiles - 8, 3):
					var depth := 0
					while depth < 16:
						var tile := WorldGenerator._from_side(tiles, side, depth, lane)
						if terrain.level(tile.x, tile.y) != WorldGenerator.base_level(tiers[other]) \
								or terrain.is_slope(tile.x, tile.y):
							break
						## Some higher chunk's -- where two meet at a corner, either.
						var owner := terrain.owner[tile.y * tiles + tile.x] - 1
						if owner < 0 or WorldGenerator.base_level(tiers[owner]) <= terrain.base_level:
							owned = false
						depth += 1
					depths[depth] = true
	_check("higher ground spills over the border in lobes of many depths", lobed > 0 \
			and depths.size() >= 5, "%d borders, depths %s" % [lobed, str(depths.keys())])
	_check("and is coloured as the chunk it came from", owned)

	## The lake's shore, measured out from its middle in every direction: not a circle.
	var lake := WorldGenerator.heightmap(BiomeLibrary.get_biome(&"lake"), _rng(12))
	var nearest := INF
	var furthest := 0.0
	var half := (tiles - 1) * 0.5
	for step in 32:
		var angle := TAU * step / 32
		var out := 0.0
		while out < half:
			var x := roundi(half + cos(angle) * out)
			var z := roundi(half + sin(angle) * out)
			if lake.level(x, z) == lake.base_level and lake.deep[z * tiles + x] == 0 and out > half * 0.3:
				break
			out += 0.5
		nearest = minf(nearest, out)
		furthest = maxf(furthest, out)
	_check("the lake's shore wanders rather than running round a circle", furthest > nearest * 1.25,
			"%.1f to %.1f tiles" % [nearest, furthest])

	## Gems: the right ones for a purse, each its own colour.
	_check("a purse is paid in the largest gems that fit", Gem.split(37) == [25, 10, 2] \
			and Gem.split(1) == [1] and Gem.split(8) == [5, 2, 1])
	var colours := {}
	for value in Gem.VALUES:
		colours[Gem.COLORS[value]] = true
		var model := Gem.build(value)
		model.free()
	_check("every gem has a colour of its own", colours.size() == Gem.VALUES.size())

	## Crates: in the chunks, liftable by anyone, and broken open by a blow.
	var chunk := Chunk.new()
	add_child(chunk)
	chunk.build(0, &"plains", _rng(33))
	var crates: Array[int] = []
	for index in chunk._props.size():
		if chunk.is_crate(index):
			crates.append(index)
	_check("a chunk has crates in it", crates.size() >= 2, "%d crates" % crates.size())
	if not crates.is_empty():
		var node := chunk._props[crates[0]]["node"] as Node3D
		var at := node.global_position
		var found := Chunk.nearest_liftable(get_tree(), at + Vector3(0.0, 0.0, -1.5), Vector3(0, 0, 1),
				3.0, true)
		_check("a crate can be picked up without a glove", not found.is_empty() \
				and chunk.is_crate(found["index"]))
		Chunk.struck(get_tree(), at + Vector3.UP * 0.5, 0.5)
		_check("a blow breaks a crate", not chunk.can_lift(crates[0]))
	chunk.free()


func _test_river() -> void:
	print("\n--- the river")
	var tiles := WorldGenerator.CHUNK_TILES
	var problems := ""
	var falls_seen := 0
	for world_seed: int in [4242, 7, 31, 2026, 8, 1, 2, 3, 5, 23]:
		var plan := WorldGenerator.plan(world_seed)
		var river: Dictionary = plan["river"]
		var cells: Array = river.get("cells", [])
		if cells.is_empty():
			problems += " seed %d has no river;" % world_seed
			continue
		var tiers: PackedInt32Array = plan["tiers"]
		if plan["biomes"][cells[0]] != &"mountain":
			problems += " seed %d: does not start on the mountain;" % world_seed
		if plan["biomes"][cells[-1]] != &"beach":
			problems += " seed %d: does not reach the sea;" % world_seed
		for step in range(1, cells.size()):
			if tiers[cells[step]] > tiers[cells[step - 1]]:
				problems += " seed %d: flows uphill into chunk %d;" % [world_seed, cells[step]]
			if plan["biomes"][cells[step]] == &"lake":
				problems += " seed %d: runs through the lake;" % world_seed
		for cell: int in cells:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(world_seed) ^ (cell * 2654435761)
			var terrain := WorldGenerator.heightmap(BiomeLibrary.get_biome(plan["biomes"][cell]),
					rng, WorldGenerator.context(tiers, cell, river))
			if not terrain.water.has(1):
				problems += " seed %d: chunk %d has no water;" % [world_seed, cell]
			if terrain.bridges.is_empty():
				problems += " seed %d: chunk %d has no bridge;" % [world_seed, cell]
			for z in tiles:
				for x in tiles:
					if not terrain.is_water(x, z):
						continue
					if RiverBuilder.is_below_fall(terrain, x, z):
						falls_seen += 1
					## Downstream, the bed is never higher: the river only ever falls.
					var flow := terrain.flow[z * tiles + x]
					if flow == Vector2.ZERO:
						continue
					var next := Vector2i((Vector2(x + 0.5, z + 0.5) + flow * 1.2).floor())
					if terrain.is_water(next.x, next.y) \
							and terrain.level(next.x, next.y) > terrain.level(x, z):
						problems += " seed %d: chunk %d (%s, tier %d) rises at (%d,%d) %d -> %d, %s;" % [world_seed, cell, plan["biomes"][cell], tiers[cell], x, z, terrain.level(x, z), terrain.level(next.x, next.y), str(river["parts"][cell])]
						break
	_check("the river runs from a mountain pond, downhill, to the sea, with a bridge in every chunk",
			problems == "", problems)
	_check("and falls over waterfalls on the way", falls_seen > 20, "%d tiles below falls" % falls_seen)

	## Its second arm: off the river part way down, through the chunks between, into the lake.
	var branch_problems := ""
	var branches := 0
	for world_seed: int in [4242, 7, 31, 2026, 8, 17]:
		var plan := WorldGenerator.plan(world_seed)
		var river: Dictionary = plan["river"]
		var arm: Array = river.get("branch", [])
		if arm.is_empty():
			continue
		branches += 1
		if not (river["cells"] as Array).has(arm[0]) or plan["biomes"][arm[-1]] != &"lake":
			branch_problems += " seed %d: %s;" % [world_seed, str(arm)]
			continue
		for step in range(1, arm.size()):
			if plan["tiers"][arm[step]] > plan["tiers"][arm[step - 1]]:
				branch_problems += " seed %d: uphill;" % world_seed
		for cell: int in arm:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(world_seed) ^ (cell * 2654435761)
			var terrain := WorldGenerator.heightmap(BiomeLibrary.get_biome(plan["biomes"][cell]),
					rng, WorldGenerator.context(plan["tiers"], cell, river, plan["entrances"],
					plan["shape_seed"]))
			var plank := 0
			for spec: Dictionary in terrain.bridges:
				if spec.get("kind", &"plank") == &"plank":
					plank += 1
			## The chunk it splits in has two to cross; the rest, one each.
			if not terrain.water.has(1) or plank < (2 if cell == arm[0] else 1):
				branch_problems += " seed %d chunk %d: %d bridges;" % [world_seed, cell, plank]
			if cell == arm[-1]:
				## It runs right into the lake: river water beside the lake's.
				var meets := false
				for index in tiles * tiles:
					var x := index % tiles
					var z := index / tiles
					if not terrain.is_water(x, z):
						continue
					for side in 4:
						var nx := x + ChunkMesher.NEIGHBOUR_DX[side]
						var nz := z + ChunkMesher.NEIGHBOUR_DZ[side]
						if terrain.in_bounds(nx, nz) and not terrain.is_water(nx, nz) \
								and terrain.level(nx, nz) < terrain.base_level:
							meets = true
				if not meets:
					branch_problems += " seed %d: never reaches the lake;" % world_seed
	_check("a second arm of the river runs downhill into the lake, bridged on the way",
			branches >= 4 and branch_problems == "", "%d arms;%s" % [branches, branch_problems])

	## Deep water and the raft.
	var pid := PlayerRegistry.make_pid(1, 0)
	PlayerRegistry.add_entry(pid, &"knight")
	var hero := PlayerCharacter.new()
	Combatant.setup_body(hero, 0.42, 1.6)
	add_child(hero)
	hero.configure(pid, ArchetypeDB.get_archetype(&"knight"))
	hero.global_position = Vector3(-600.0, 4.0, -600.0)
	hero._river = {"surface": 5.1, "bank": 5.4, "flow": Vector3.RIGHT, "bridge": false}
	_check("no raft: down in the river is swept away", hero.is_swept() and not hero.is_rafting())
	_check("and a raft-less body goes through the water", hero.collision_mask & Combatant.LAYER_WATER == 0)
	hero.add_item(ItemDB.RAFT)
	_check("a raft is static gear, in the chests and the shop", ItemDB.is_passive(ItemDB.RAFT)
			and ItemDB.CHEST_CYCLE.has(ItemDB.RAFT) and ItemDB.price(ItemDB.RAFT) > 0)
	_check("carrying one, the river's surface is something to stand on",
			hero.collision_mask & Combatant.LAYER_WATER != 0)
	hero.global_position.y = 5.4
	_check("and up at the banks it is riding, not swept", hero.is_rafting() and not hero.is_swept())
	hero._river["bridge"] = true
	_check("a bridge is walked, not rafted", not hero.is_rafting() and not hero.is_swept())
	hero.remove_item(ItemDB.RAFT)
	_check("dropping the raft takes the footing with it", hero.collision_mask & Combatant.LAYER_WATER == 0)
	## The lake's and the sea's deep water answer the same way, but are never rafted.
	hero._river = {"surface": 0.45, "bank": 0.45, "flow": Vector3.ZERO, "bridge": false, "still": true}
	hero.global_position.y = 0.2
	_check("at the surface of deep still water you are not yet in", not hero.is_swept())
	hero.global_position.y = -0.5
	_check("sunk into it, you have gone in", hero.is_swept())
	hero.add_item(ItemDB.RAFT)
	hero.global_position.y = 0.45
	_check("and a raft does not float on still water", not hero.is_rafting())
	hero.remove_item(ItemDB.RAFT)
	PlayerRegistry.roster.erase(pid)
	PlayerRegistry.despawn(pid)
	hero.queue_free()


# --- saved worlds ----------------------------------------------------------------------------

func _test_saved_worlds() -> void:
	print("\n--- saved worlds")
	## Files: written, listed, read back, deleted. Tests run in the dev sandbox (SaveManager).
	var world := SaveManager.new_world(98765)
	_check("a new world is written straight away", SaveManager.load_world(world.id) != null)
	_check("with the seed it was given", SaveManager.load_world(world.id).world_seed == 98765)
	var listed := false
	for each in SaveManager.list_worlds():
		listed = listed or each.id == world.id
	_check("and appears in the list of worlds", listed)
	world.gold = 321
	world.dragons_slain = 2
	world.opened_chests = PackedStringArray(["Chest_3_00", "Chest_5_01"])
	world.loose_gear = [{"item": "feather", "position": Vector3(10, 2, 30)}]
	world.characters = {"knight": {"gear": ["sword", "shield", "boots"], "max_health": 8}}
	world.revealed_entrances = PackedStringArray(["Entrance_fields"])
	world.unlocked_chests = PackedStringArray(["BigChest_Dwell"])
	SaveManager.save_world(world)
	var back := SaveManager.load_world(world.id)
	_check("progress survives a save and a load",
			back.gold == 321 and back.dragons_slain == 2
			and back.opened_chests == PackedStringArray(["Chest_3_00", "Chest_5_01"])
			and back.loose_gear.size() == 1
			and back.loose_gear[0]["position"] == Vector3(10, 2, 30)
			and (back.characters["knight"]["gear"] as Array).has("boots"))
	_check("and so do the dungeon entrances found and the big chests unlocked",
			back.revealed_entrances == PackedStringArray(["Entrance_fields"])
			and back.unlocked_chests == PackedStringArray(["BigChest_Dwell"]))
	var second := SaveManager.new_world()
	_check("each new world gets its own id and name",
			second.id != world.id and second.name != world.name, "%s / %s" % [world.name, second.name])
	SaveManager.delete_world(world.id)
	SaveManager.delete_world(second.id)
	_check("a deleted world is gone, backup and all",
			SaveManager.load_world(world.id) == null and SaveManager.load_world(second.id) == null)

	## A hero's kit: saved, then put back on a fresh hero.
	var pid := PlayerRegistry.make_pid(1, 2)
	PlayerRegistry.add_entry(pid, &"knight")
	var hero := PlayerCharacter.new()
	Combatant.setup_body(hero, 0.42, 1.6)
	add_child(hero)
	hero.configure(pid, ArchetypeDB.get_archetype(&"knight"))
	hero.add_item(ItemDB.HOOKSHOT)
	hero.add_item(ItemDB.FEATHER)
	hero.add_item(ItemDB.HEART)
	hero.add_item(ItemDB.ARMOR)
	hero.bugs = 7
	var state := hero.save_state()
	var hearts := hero.max_health
	hero.queue_free()
	PlayerRegistry.despawn(pid)

	var again := PlayerCharacter.new()
	Combatant.setup_body(again, 0.42, 1.6)
	add_child(again)
	again.configure(pid, ArchetypeDB.get_archetype(&"knight"))
	again.restore_state(state)
	_check("a restored hero has their gear back",
			again.has_item(ItemDB.HOOKSHOT) and again.has_item(ItemDB.FEATHER)
			and again.has_item(ItemDB.SWORD) and again.has_item(ItemDB.SHIELD), str(again.gear))
	_check("and their hotkeys", again.hotkeys == hero.hotkeys, str(again.hotkeys))
	_check("their heart containers count once, not twice",
			again.max_health == hearts and again.health == hearts, "%d vs %d" % [again.max_health, hearts])
	_check("and their armour and bugs", again.armor_level == 1 and again.bugs == 7)
	again.restore_state({"gear": ["sword", "no_such_item"], "hotkeys": ["no_such_item", "", ""]})
	_check("items the game no longer has are skipped, and starting gear is kept",
			again.gear == ([ItemDB.SWORD, ItemDB.SHIELD] as Array[StringName])
			and again.hotkeys[0] == &"", str(again.gear))
	again.queue_free()
	PlayerRegistry.despawn(pid)
	PlayerRegistry.roster.erase(pid)

	## A chest opened in an earlier session opens without spilling its loot again.
	var chest := TreasureChest.new()
	add_child(chest)
	chest.setup(true, 50)
	var spilled := [0]
	chest.opened.connect(func(_c: TreasureChest) -> void: spilled[0] += 1)
	chest.set_open_quietly()
	_check("a chest can be shown open without spilling loot", chest.is_open and spilled[0] == 0)
	chest.queue_free()

	## The character select: one seat per hero in a world, any heroes when joining someone.
	var lobby := LobbyScreen.new()
	add_child(lobby)
	lobby._choose_mode("offline")
	_check("a local game asks for a world first", lobby._step == LobbyScreen.Step.WORLD)
	lobby._choose_world(LobbyScreen.NEW_WORLD)
	for device in [PlayerBindings.KEYBOARD, 0, 1, 2]:
		lobby.claim_seat(device)
	var unique := true
	for turn in 12:
		lobby.step_hero(0, 1 if turn % 3 != 0 else -1)
		var seen := {}
		for hero_id in lobby.heroes():
			unique = unique and not seen.has(hero_id)
			seen[hero_id] = true
	_check("in a world no two seats can hold the same hero", unique, str(lobby.heroes()))
	lobby._choose_mode("join")
	_check("joining someone skips the world step", lobby._step == LobbyScreen.Step.SEATS
			and lobby.world_id() == LobbyScreen.NO_WORLD)
	lobby.queue_free()


# --- dungeons ---------------------------------------------------------------------------------

func _test_dungeons() -> void:
	print("\n--- dungeons")
	## Every map makes room for all eight ways in, each in the biome (and tier) it belongs in.
	var missing := ""
	for world_seed in range(1, 41):
		var plan := WorldGenerator.plan(world_seed)
		var entrances: Dictionary = plan["entrances"]
		for id: StringName in Dungeon.IDS:
			if not entrances.has(id):
				missing += " seed %d: no %s;" % [world_seed, id]
				continue
			var cell: int = entrances[id]
			var wanted: Array = WorldGenerator.DUNGEON_BIOMES[id]
			if plan["biomes"][cell] != wanted[0] or (wanted[1] >= 0 and plan["tiers"][cell] != wanted[1]):
				missing += " seed %d: %s in a %s;" % [world_seed, id, plan["biomes"][cell]]
	_check("every map has all eight dungeon entrances' biomes, temples in both tiers (40 seeds)",
			missing == "", missing)

	## And each one actually gets built in its chunk -- and the desert's stairwell can be walked
	## down to its door.
	var unbuilt := ""
	var stairs_ok := true
	for world_seed in [3, 8, 17, 23, 31, 42]:
		var plan := WorldGenerator.plan(world_seed)
		for id: StringName in plan["entrances"]:
			var cell: int = plan["entrances"][id]
			var chunk := Chunk.new()
			add_child(chunk)
			chunk.build(cell, plan["biomes"][cell], _rng(world_seed * 100 + cell),
					WorldGenerator.context(plan["tiers"], cell, plan["river"], plan["entrances"],
							plan["shape_seed"]))
			if chunk.entrance == null:
				unbuilt += " seed %d: %s;" % [world_seed, id]
			elif id == &"desert":
				var well := chunk.terrain.stairwell
				var bottom := Vector2i(well.position.x + 1, well.end.y - 1)
				stairs_ok = stairs_ok and chunk.terrain.reach[bottom.y * chunk.terrain.size + bottom.x] == 1 \
						and chunk.terrain.level(bottom.x, bottom.y) \
								== chunk.terrain.base_level - WorldGenerator.STAIRWELL_DEPTH \
						and chunk.can_lift(chunk.entrance._rock_index)
			chunk.free()
	_check("every entrance finds a place in its chunk (6 seeds)", unbuilt == "", unbuilt)
	_check("the desert's stairwell can be walked down to its door, under a rock the glove can lift",
			stairs_ok)

	## The scenes: each has somewhere to arrive, a way out, skeletons, chests, a guardian and a
	## big chest holding its reward, locked until the guardian falls.
	for index in Dungeon.IDS.size():
		var id := Dungeon.IDS[index]
		var packed := load(Dungeon.scene_path(id)) as PackedScene
		var dungeon := packed.instantiate() as Dungeon if packed != null else null
		_check("%s: the scene loads as a dungeon" % id, dungeon != null)
		if dungeon == null:
			continue
		add_child(dungeon)
		dungeon.dungeon_id = id
		dungeon.build(index)
		var entry := dungeon.entry_position()
		_check("%s: an entry, a way out and its own bounds" % id, dungeon.exit_door() != null
				and Dungeon.containing(get_tree(), entry) == dungeon
				and Dungeon.near_exit(get_tree(), dungeon.exit_door().door_position()) == dungeon
				and Dungeon.near_exit(get_tree(), entry) == null)
		_check("%s: skeletons and chests to find" % id, dungeon.monsters.size() >= 5
				and dungeon.chests.size() >= 3, "%d monsters, %d chests" % [dungeon.monsters.size(),
						dungeon.chests.size()])
		_check("%s: a champion guards a locked big chest holding %s" % [id, dungeon.reward_item],
				dungeon.boss != null and dungeon.boss.data.id == &"skeleton_champion"
				and dungeon.big_chest != null and dungeon.big_chest.locked
				and ItemDB.exists(dungeon.reward_item) and dungeon.big_chest.item_id == dungeon.reward_item)
		_check("%s: nobody stands outside the walls" % id, _all_inside(dungeon))
		if index == 0:
			var chest := dungeon.big_chest
			_check("a locked chest will not open", not chest.try_open(null) and not chest.is_open)
			dungeon.boss.take_damage(dungeon.boss.max_health * 3, dungeon.boss.global_position + Vector3.FORWARD, 0.0, 0.0)
			_check("beating the guardian unlocks it", not chest.locked)
		dungeon.free()
	_check("the well's chest holds bombs and the fields' holds flippers",
			(load(Dungeon.scene_path(&"well")) as PackedScene).instantiate().get("reward_item") == ItemDB.BOMB
			and (load(Dungeon.scene_path(&"fields")) as PackedScene).instantiate().get("reward_item") == ItemDB.FLIPPERS)
	_check("dungeons sit off the map, clear of one another and of what is drawn",
			Dungeon.ORIGIN.x - 300.0 > WorldGenerator.CHUNK_SIZE * WorldGenerator.GRID
			and Dungeon.SPACING > Culling.MONSTER_VISIBLE_RANGE * 2.0)


## Every monster and chest in a dungeon stands on its floor, inside its walls.
func _all_inside(dungeon: Dungeon) -> bool:
	var spots: Array[Vector3] = [dungeon.entry_position()]
	for monster in dungeon.monsters:
		spots.append(monster.global_position)
	for chest in dungeon.chests:
		spots.append(chest.global_position)
	for at in spots:
		if not dungeon.bounds.has_point(at):
			return false
	return true


func _test_bombs_and_flippers() -> void:
	print("\n--- bombs and flippers")
	_check("bombs are equipment, sold in town; flippers just work",
			ItemDB.is_usable(ItemDB.BOMB) and ItemDB.price(ItemDB.BOMB) > 0
			and ItemDB.is_passive(ItemDB.FLIPPERS) and ItemDB.STATIC.has(ItemDB.FLIPPERS)
			and ItemDB.ORDER.find(ItemDB.LANTERN) == 5)
	var pid := PlayerRegistry.make_pid(1, 0)
	PlayerRegistry.add_entry(pid, &"knight")
	var hero := PlayerCharacter.new()
	Combatant.setup_body(hero, 0.42, 1.6)
	add_child(hero)
	hero.configure(pid, ArchetypeDB.get_archetype(&"knight"))
	hero.global_position = Vector3(-900.0, 4.0, -900.0)
	var other := PlayerCharacter.new()
	var other_pid := PlayerRegistry.make_pid(1, 1)
	PlayerRegistry.add_entry(other_pid, &"barbarian")
	Combatant.setup_body(other, 0.42, 1.6)
	add_child(other)
	other.configure(other_pid, ArchetypeDB.get_archetype(&"barbarian"))
	other.global_position = Vector3(-898.0, 4.0, -900.0)
	var far := PlayerCharacter.new()
	var far_pid := PlayerRegistry.make_pid(1, 2)
	PlayerRegistry.add_entry(far_pid, &"archer")
	Combatant.setup_body(far, 0.42, 1.6)
	add_child(far)
	far.configure(far_pid, ArchetypeDB.get_archetype(&"archer"))
	far.global_position = Vector3(-880.0, 4.0, -900.0)

	## The blast: two points to everyone in it, the one who lit it included, and a hard shove.
	var bomb := Bomb.new()
	add_child(bomb)
	bomb.launch(hero, Vector3(-899.0, 4.0, -900.0), Vector3.ZERO)
	var before := [hero.health, other.health, far.health]
	bomb.explode()
	_check("a bomb hurts everyone in reach for two points, its owner too",
			hero.health == before[0] - Bomb.DAMAGE and other.health == before[1] - Bomb.DAMAGE,
			"%d -> %d, %d -> %d" % [before[0], hero.health, before[1], other.health])
	_check("and throws them back", Vector2(other.velocity.x, other.velocity.z).length() > 5.0)
	_check("but nobody out of reach", far.health == before[2])

	## Flippers: afloat in still deep water, never in the river.
	hero._river = {"surface": 0.45, "bank": 0.45, "flow": Vector3.ZERO, "bridge": false, "still": true}
	hero.global_position.y = -0.4
	_check("without flippers, deep still water takes you", hero.is_swept())
	hero.add_item(ItemDB.FLIPPERS)
	_check("with them, you swim", not hero.is_swept() and hero.is_swimming())
	hero.global_position.y = -1.8
	_check("and below the surface you are diving", hero.is_diving())
	hero._river = {"surface": 5.1, "bank": 5.4, "flow": Vector3.RIGHT, "bridge": false}
	hero.global_position.y = 4.0
	_check("the river's current is too strong even with flippers", hero.is_swept())
	hero._river = {}

	## Secrets: a blast opens the cracked wall; a blow opens the tree.
	for id: StringName in [&"plains", &"fields"]:
		var biome := BiomeLibrary.get_biome(id)
		var ctx := WorldGenerator.lone_context(biome)
		ctx["entrance"] = id
		var chunk := Chunk.new()
		add_child(chunk)
		chunk.build(6, id, _rng(77), ctx)
		var entrance := chunk.entrance
		_check("the %s chunk has its hidden entrance" % id, entrance != null and not entrance.revealed)
		if entrance == null:
			chunk.free()
			continue
		_check("hidden, it cannot be gone through",
				DungeonEntrance.near_door(get_tree(), entrance.door_position()) == null)
		if id == &"plains":
			DungeonEntrance.struck(get_tree(), entrance.to_global(Vector3(0, 1, DungeonEntrance.WALL_FACE)), 1.0)
			_check("a blow does not open the cracked wall", not entrance.revealed)
			DungeonEntrance.blasted(get_tree(), entrance.to_global(Vector3(0, 0.5, DungeonEntrance.WALL_FACE + 1.5)), Bomb.RADIUS)
			_check("a bomb beside it does", entrance.revealed)
		else:
			DungeonEntrance.blasted(get_tree(), entrance.global_position + Vector3(30, 0, 0), Bomb.RADIUS)
			DungeonEntrance.struck(get_tree(), entrance.global_position + Vector3(9, 1, 0), 1.0)
			_check("a blow well away from the tree does nothing", not entrance.revealed)
			DungeonEntrance.struck(get_tree(), entrance.to_global(Vector3(0, 1, 2.2)), 1.2)
			_check("a sword's reach from the trunk opens the door in it", entrance.revealed)
		_check("and then it can be gone through",
				DungeonEntrance.near_door(get_tree(), entrance.door_position()) == entrance)
		chunk.free()

	for body_pid in [pid, other_pid, far_pid]:
		PlayerRegistry.roster.erase(body_pid)
		PlayerRegistry.despawn(body_pid)
	for body in [hero, other, far]:
		if is_instance_valid(body):
			body.queue_free()

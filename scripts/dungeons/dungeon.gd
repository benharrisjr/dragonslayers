class_name Dungeon
extends LootArea

## One of the eight dungeons: a hand-built scene (scenes/dungeons/<id>.tscn), not generated.
##
## Each is laid out in the editor with plain nodes -- CSG boxes for floors and walls, lights and
## props for dressing -- plus markers for what lives there: MonsterSpots, ChestSpots, one of each
## marked as the guardian and the big chest, an Entry marker where you arrive and a DoorSpot that
## is the way out. GameWorld instances all eight on every machine, off the edge of the map, and
## build() swaps the markers for real monsters and chests, named by scene order so they are the
## same nodes everywhere and a saved world can remember which chests are open.
##
## The big chest holds `reward_item` and is locked until the guardian falls.

const GROUP := &"dungeons"
## Every dungeon, in the order they are laid out beside the map.
const IDS: Array[StringName] = [&"well", &"fields", &"desert", &"plains", &"forest",
		&"temple_low", &"temple_high", &"lake"]
const SCENE_DIR := "res://scenes/dungeons/"
## Off the edge of the map (which is 512 m across), well apart from one another: further than
## anything is drawn or anything is simulated, so a dungeon never sees another, or the map.
const ORIGIN := Vector3(1400.0, 0.0, 256.0)
const SPACING := 320.0
## How close to the way out a player has to be to use it.
const EXIT_RADIUS := 3.4
## Space round the floors still counted as inside, and how far above and below.
const BOUNDS_MARGIN := 6.0

@export var dungeon_id: StringName = &""
@export var display_name: String = ""
## What the big chest holds (an ItemDB id).
@export var reward_item: StringName = &"heart"

var boss: Monster
var big_chest: TreasureChest
var monsters: Array[Monster] = []
var chests: Array[TreasureChest] = []
## The space this dungeon takes up, in world coordinates.
var bounds := AABB()

var _entry: Node3D
var _exit: DoorSpot


static func scene_path(id: StringName) -> String:
	return SCENE_DIR + String(id) + ".tscn"


static func origin_for(index: int) -> Vector3:
	return ORIGIN + Vector3(SPACING * index, 0.0, 0.0)


## Places this dungeon at its spot beside the map and fills it in. Every peer, at world build.
func build(index: int) -> void:
	name = "Dungeon_%s" % dungeon_id
	position = origin_for(index)
	add_to_group(GROUP)
	_entry = find_child("Entry", true, false) as Node3D
	var monster_root := Node3D.new()
	monster_root.name = "Monsters"
	add_child(monster_root)
	var chest_root := Node3D.new()
	chest_root.name = "Chests"
	add_child(chest_root)
	var monster_count := 0
	var chest_count := 0
	for node in _walk(self):
		if node is MonsterSpot:
			var spot := node as MonsterSpot
			var monster := _spawn_monster(spot, monster_root,
					"Boss_D%s" % dungeon_id if spot.boss else "Monster_D%s_%02d" % [dungeon_id, monster_count])
			if monster == null:
				continue
			if spot.boss:
				boss = monster
				monster.loot_dropped.connect(_on_boss_down)
			else:
				monster_count += 1
		elif node is ChestSpot:
			var spot := node as ChestSpot
			var chest := TreasureChest.new()
			chest.name = "BigChest_D%s" % dungeon_id if spot.big else "Chest_D%s_%02d" % [dungeon_id, chest_count]
			chest_root.add_child(chest)
			chest.global_transform = Transform3D(Basis(Vector3.UP, spot.global_rotation.y), spot.global_position)
			chest.setup(spot.large or spot.big, spot.gold)
			chest.opened.connect(_on_chest_opened)
			if spot.big:
				chest.item_id = reward_item
				big_chest = chest
			else:
				chest_count += 1
			chests.append(chest)
		elif node is DoorSpot:
			_exit = node
	if big_chest != null and boss != null:
		big_chest.lock()
	bounds = _measure()


func _spawn_monster(spot: MonsterSpot, parent: Node3D, monster_name: String) -> Monster:
	var data := MonsterDB.get_monster(spot.monster_id)
	if data == null:
		push_warning("%s: no monster called %s" % [name, spot.monster_id])
		return null
	var monster := Monster.new()
	monster.name = monster_name
	Chunk._add_body_shape(monster, 0.45 * data.scale, 1.7 * data.scale)
	parent.add_child(monster)
	monster.global_position = spot.global_position + Vector3.UP * 0.4
	monster.reset_physics_interpolation()
	monster.configure(data)
	monster.loot_dropped.connect(_on_monster_died)
	monsters.append(monster)
	return monster


## Host: the guardian is down; the big chest opens up, on every peer.
func _on_boss_down(_monster: Monster) -> void:
	if big_chest != null and NetworkManager.is_host():
		big_chest.unlock()


## Every node under `root`, depth first, in scene order.
static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


## The floors and walls, plus a margin: what counts as being in here.
func _measure() -> AABB:
	var box := AABB()
	var first := true
	for node in _walk(self):
		if not node is CSGBox3D:
			continue
		var csg := node as CSGBox3D
		var size := csg.size * csg.global_basis.get_scale().abs()
		var piece := AABB(csg.global_position - size * 0.5, size)
		box = piece if first else box.merge(piece)
		first = false
	if first:
		box = AABB(global_position - Vector3(40, 10, 40), Vector3(80, 20, 80))
	return box.grow(BOUNDS_MARGIN)


func entry_position() -> Vector3:
	return _entry.global_position if _entry != null else global_position


func exit_door() -> DoorSpot:
	return _exit


# --- finding ---------------------------------------------------------------------------------

static func all(tree: SceneTree) -> Array[Dungeon]:
	var found: Array[Dungeon] = []
	for node in tree.get_nodes_in_group(GROUP):
		if node is Dungeon:
			found.append(node)
	return found


static func by_id(tree: SceneTree, id: StringName) -> Dungeon:
	for dungeon in all(tree):
		if dungeon.dungeon_id == id:
			return dungeon
	return null


## The dungeon `at` is inside, or null out on the map.
static func containing(tree: SceneTree, at: Vector3) -> Dungeon:
	## Everything on the map is well short of the first dungeon, so most calls stop here.
	if at.x < ORIGIN.x - SPACING * 0.5:
		return null
	for dungeon in all(tree):
		if dungeon.bounds.has_point(at):
			return dungeon
	return null


## The dungeon whose way out a player standing at `at` could use, or null.
static func near_exit(tree: SceneTree, at: Vector3) -> Dungeon:
	var dungeon := containing(tree, at)
	if dungeon != null and dungeon._exit != null \
			and dungeon._exit.door_position().distance_to(at) < EXIT_RADIUS:
		return dungeon
	return null


## The look of being underground, for a camera whose player is in a dungeon: a black void beyond
## the walls, fog that swallows the distance, and dim, warm light. A new one each call -- each
## camera keeps its own, and nothing static holds a rendering resource past shutdown.
static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.0, 0.0, 0.0)
	env.fog_density = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	return env

class_name WorldPersistence
extends RefCounted

## Copies progress between a live match and its WorldSave: `capture` writes the match into the
## save, `apply_world` lays a save over a world freshly built from its seed. Host only -- a
## client never holds a save; it is caught up by GameWorld's catch-up calls instead.
##
## What carries over is progress, not the moment: opened chests, the party's gold, gear left on
## the ground, and each hero's kit. Skeletons, scenery and loose coins come back fresh from the
## seed, and everyone starts the next session in town.


static func capture(world: GameWorld, save: WorldSave) -> void:
	if world == null or save == null:
		return
	var tree := world.get_tree()
	save.gold = GameState.gold
	if world.day_night != null:
		save.time_of_day = world.day_night.time
	var opened := PackedStringArray()
	for node in tree.get_nodes_in_group("chests"):
		var chest := node as TreasureChest
		if chest != null and chest.is_open:
			opened.append(String(chest.name))
	save.opened_chests = opened
	var loose: Array = []
	for node in tree.get_nodes_in_group("pickups"):
		var pickup := node as Pickup
		if pickup == null or pickup.kind != Pickup.Kind.ITEM or pickup.is_queued_for_deletion():
			continue
		var item := pickup.item_id()
		if item != &"":
			loose.append({"item": String(item), "position": pickup.global_position})
	save.loose_gear = loose
	save.revealed_entrances = DungeonEntrance.revealed_names(tree)
	save.unlocked_chests = world.unlocked_chests()
	## Heroes not in this session keep what they had; those here are brought up to date. A dead
	## hero's droppable gear is already on the ground, and is saved there.
	var characters := save.characters.duplicate(true)
	for pid: int in PlayerRegistry.bodies:
		var body := PlayerRegistry.body_of(pid) as PlayerCharacter
		if body == null or body.archetype == null:
			continue
		characters[String(body.archetype.id)] = body.save_state()
	save.characters = characters


## After GameWorld.build on the host: chests already opened stay open (with no loot spilling out
## a second time), the purse is refilled, and gear left lying about is put back down.
static func apply_world(world: GameWorld, save: WorldSave) -> void:
	if world == null or save == null:
		return
	open_chests(world.get_tree(), save.opened_chests)
	DungeonEntrance.reveal_named(world.get_tree(), save.revealed_entrances)
	unlock_chests(world.get_tree(), save.unlocked_chests)
	GameState.gold = save.gold
	for entry in save.loose_gear:
		if not entry is Dictionary:
			continue
		var item := StringName(str(entry.get("item", "")))
		var at: Variant = entry.get("position", null)
		if not ItemDB.exists(item) or not at is Vector3:
			continue
		var area := LootArea.at_point(world.get_tree(), at)
		if area != null:
			area.drop_item(item, at)


static func open_chests(tree: SceneTree, names: PackedStringArray) -> void:
	for node in tree.get_nodes_in_group("chests"):
		var chest := node as TreasureChest
		if chest != null and names.has(String(chest.name)):
			chest.set_open_quietly()


## Big chests whose guardian was beaten, unlocked without a fanfare.
static func unlock_chests(tree: SceneTree, names: PackedStringArray) -> void:
	for node in tree.get_nodes_in_group("chests"):
		var chest := node as TreasureChest
		if chest != null and names.has(String(chest.name)):
			chest.unlock_quietly()


## The saved kit for whoever plays `hero` in this world, or an empty Dictionary for a new hero.
static func character_for(save: WorldSave, hero: StringName) -> Dictionary:
	if save == null:
		return {}
	var state: Variant = save.characters.get(String(hero), {})
	return state if state is Dictionary else {}

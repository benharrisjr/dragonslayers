extends Node

## Headless smoke test for the template shell. Runs in the save sandbox
## (SaveManager._pick_save_root), so it never touches real saves.
##
##   godot --headless --path . res://tests/template_check.tscn
##
## Exit code 0 when every check passes. Add the game's own checks as it grows.

var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	_check_scripts_load()
	_check_save_round_trip()
	_check_backup_fallback()
	_check_achievements()
	await _check_windows_build()
	print("template_check: %s" % ("OK" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", what)


## Every script and scene in the project parses and loads.
func _check_scripts_load() -> void:
	var paths: Array[String] = []
	_collect("res://", paths)
	var bad: Array[String] = []
	for p in paths:
		if ResourceLoader.load(p) == null:
			bad.append(p)
	_expect(bad.is_empty(), "all %d scripts/scenes/resources load %s" % [paths.size(), bad])


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "addons" or sub == "builds" or sub == "node_modules":
			continue
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.get_extension() in ["gd", "tscn", "tres", "gdshader"]:
			out.append(dir_path.path_join(f))


func _check_save_round_trip() -> void:
	_expect(SaveManager.save_root == SaveManager.DEV_SANDBOX_DIR, "running in the save sandbox")
	SaveManager.new_game_at(0)
	SaveManager.add_stat(&"dragons_slain", 7)
	SaveManager.set_flag(&"seen_intro")
	SaveManager.save_game()
	SaveManager.save_data = null
	SaveManager.load_game(0)
	_expect(SaveManager.get_stat(&"dragons_slain") == 7.0, "stat survives save and load")
	_expect(SaveManager.has_flag(&"seen_intro"), "flag survives save and load")
	_expect(not SaveManager.get_slot_summary(0).is_empty(), "slot 0 has a summary")
	_expect(SaveManager.get_slot_summary(2).is_empty(), "an unused slot has no summary")


## A corrupted save falls back to its .bak rather than being lost.
func _check_backup_fallback() -> void:
	SaveManager.add_stat(&"dragons_slain", 1)   # 8
	SaveManager.save_game()                # the 7-click file becomes the backup
	var path := SaveManager.get_save_slot_path(0)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is not a resource")
	f.close()
	SaveManager.load_game(0)
	_expect(SaveManager.get_stat(&"dragons_slain") == 7.0, "corrupt save loads its backup")
	SaveManager.delete_save_slot(0)
	_expect(not SaveManager.has_save_at(0), "delete removes the file and its backup")
	SaveManager.new_game_at(0)


func _check_achievements() -> void:
	if not FeatureFlags.ACHIEVEMENTS:
		return
	Achievements.persist_enabled = false
	_expect(Achievements.get_all_defs().size() >= 1, "achievement roster loads")
	var cfg := SaveManager.global_config
	cfg.achievements_unlocked.erase(&"veteran_slayer")
	cfg.achievements_unlocked.erase(&"dragon_slain")
	Achievements.evaluate()
	_expect(not Achievements.is_unlocked(&"veteran_slayer"), "counter achievement locked below its target")
	SaveManager.add_stat(&"dragons_slain", 10)
	Achievements.evaluate()
	_expect(Achievements.is_unlocked(&"veteran_slayer"), "counter achievement unlocks at its target")
	Achievements.grant(&"dragon_slain")
	_expect(Achievements.is_unlocked(&"dragon_slain"), "manual achievement unlocks on grant")
	cfg.achievements_unlocked.erase(&"veteran_slayer")
	cfg.achievements_unlocked.erase(&"dragon_slain")


## Every window builds without errors when added to the tree.
func _check_windows_build() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var windows: Array = [OptionsScreen, KeybindsPanel, AchievementsPanel, CreditsScreen,
			LinksPanel, PatchNotesPanel, QuitConfirmPanel]
	for script: Script in windows:
		var w: Control = script.new()
		host.add_child(w)
		await get_tree().process_frame
		_expect(w.get_child_count() > 0, "%s builds" % script.get_global_name())
		w.queue_free()
		await get_tree().process_frame
	for scene_path: String in [ProjectConfig.MAIN_MENU_SCENE, ProjectConfig.GAME_SCENE]:
		var scene: Node = (load(scene_path) as PackedScene).instantiate()
		host.add_child(scene)
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(scene.get_child_count() > 0, "%s builds" % scene_path)
		scene.queue_free()
		await get_tree().process_frame
	host.queue_free()

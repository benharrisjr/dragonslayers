extends Node

## Save slots, the cross-slot config, and the single quit path.
##
##   SaveManager.save_data      the loaded slot (SaveData); never null after boot
##   SaveManager.global_config  settings / controls / achievements (GlobalConfig)
##   SaveManager.save_game()    write the current slot
##   SaveManager.request_quit() the only way the game should exit
##
## Registered first in the autoload list: later autoloads read global_config in
## their own _ready, and connect to save_loaded rather than being called here.

## Emitted whenever save_data is swapped in: boot, slot load, new game.
signal save_loaded
## A save file (slot or global config) was written to disk; SaveIndicator
## blinks on this.
signal save_written
## A keybinding changed, bindings were reset, the Key Hints toggle flipped, or
## the input device switched: every on-screen key icon re-resolves on this.
signal keybinds_changed
## Options "Readable Font" toggled: UIFont swapped the fonts; anything that
## measured text re-measures.
signal ui_font_changed

const SLOT_COUNT := ProjectConfig.SAVE_SLOT_COUNT
var current_slot: int = 0

## Where every save file (slots + global config) lives. The real game uses
## user:// itself; test scenes, tools and headless runs get DEV_SANDBOX_DIR so a
## harness can never write over (or re-point last_slot at) the player's saves.
## Picked once in _ready, before anything is loaded. See _pick_save_root.
const DEV_SANDBOX_DIR := "user://dev_sandbox/"
## Launch paths that run in the sandbox (the scene path is a command-line arg).
const _SANDBOXED_SCENE_DIRS: Array[String] = ["tests/", "tools/"]
## Set to "1" to let a sandboxed launch use the real saves.
const REAL_SAVES_ENV := "TEMPLATE_REAL_SAVES"
var save_root := "user://"

var save_data: SaveData
var global_config: GlobalConfig

## Content .tres files retired from the game, mapped to what stands in for them
## ("res://old.tres": "res://new.tres"). A save that references a retired path
## loads with the successor instead of losing the entry. See strip_missing_refs.
const RETIRED_PATHS := {}


func _ready() -> void:
	_pick_save_root()
	save_data = SaveData.new()
	_load_global_config()
	# Before any UI exists, so every Control builds with the chosen font.
	UIFont.apply()
	UiTheme.apply_to_project_theme()
	apply_pad_layout()
	Keybinds.apply_saved()
	# We own the window-close path. Steam Auto-Cloud uploads user:// *after* the
	# process exits, so a write that doesn't land before quit() never reaches the
	# cloud at all. Every quit route must go through request_quit().
	get_tree().set_auto_accept_quit(false)

	# Prefer the slot the player was last using, then any other existing save,
	# then a fresh save in slot 0 so a first launch has something loaded.
	var existing := get_existing_slots()
	if has_save_at(global_config.last_slot):
		load_game(global_config.last_slot)
	elif not existing.is_empty():
		load_game(existing[0])
	else:
		new_game_at(0)


func _process(delta: float) -> void:
	if save_data != null and not get_tree().paused:
		save_data.play_time_seconds += delta


# --- Slots -----------------------------------------------------------------------

func get_save_slot_path(slot: int) -> String:
	return save_root + "save_slot_%d.tres" % slot


## A slot counts as present if either its file or its backup is: a crash
## between the two renames in _write_save_file leaves only the backup.
func has_save_at(slot: int) -> bool:
	var path := get_save_slot_path(slot)
	return FileAccess.file_exists(path) or FileAccess.file_exists(_backup_path(path))


## Remove a slot for good (the slot picker's Delete): file and backup both, or
## the backup would bring it straight back.
func delete_save_slot(slot: int) -> void:
	var path := get_save_slot_path(slot)
	for p in [path, _backup_path(path)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func get_existing_slots() -> Array[int]:
	var result: Array[int] = []
	for i in SLOT_COUNT:
		if has_save_at(i):
			result.append(i)
	return result


## What the slot picker shows for a slot; empty when the slot has no save.
## Extend with whatever identifies a save in the game (chapter, level, ...).
func get_slot_summary(slot: int) -> Dictionary:
	if not has_save_at(slot):
		return {}
	var data := save_data if slot == current_slot else _read_save_file(get_save_slot_path(slot)) as SaveData
	if not data:
		return {}
	return {
		"play_time_seconds": data.play_time_seconds,
		"last_saved_unix": data.last_saved_unix,
	}


func new_game() -> void:
	save_data = SaveData.new()
	# Godot 4 @export Array/Dictionary defaults are shared across Resource
	# instances. Re-bind every container so a fresh save can't inherit a
	# previous slot's contents via the shared default. Add the game's own here.
	save_data.stats = {}
	save_data.flags = {}
	save_game()


func new_game_at(slot: int) -> void:
	current_slot = slot
	new_game()
	_remember_current_slot()
	save_loaded.emit()


func save_game() -> void:
	if save_data == null:
		return
	save_data.last_saved_unix = int(Time.get_unix_time_from_system())
	_write_save_file(save_data, get_save_slot_path(current_slot))


func load_game(slot: int = current_slot) -> void:
	current_slot = slot
	var path := get_save_slot_path(slot)
	save_data = _read_save_file(path) as SaveData
	if save_data == null:
		# Neither the save nor its backup could be read even with missing
		# content stripped (see _read_save_file). Keep both aside, never write
		# over them, and start this slot fresh so no screen sees a null save.
		if has_save_at(slot):
			_quarantine_save(path)
		new_game()
		_remember_current_slot()
		save_loaded.emit()
		return
	_migrate(save_data)
	_remember_current_slot()
	save_loaded.emit()


## Bring a save written by an older build up to SaveData.CURRENT_VERSION. Add one
## `if save.version < N:` block per version bump, oldest first.
func _migrate(save: SaveData) -> void:
	# if save.version < 2:
	#     save.new_field = convert(save.old_field)
	save.version = SaveData.CURRENT_VERSION


# --- Stats and flags ---------------------------------------------------------------
# Convenience over save_data.stats / save_data.flags. Neither writes to disk;
# call save_game() at the game's own checkpoints.

func add_stat(key: StringName, amount: float = 1.0) -> float:
	var value: float = float(save_data.stats.get(key, 0.0)) + amount
	save_data.stats[key] = value
	return value


func get_stat(key: StringName) -> float:
	return float(save_data.stats.get(key, 0.0))


func set_flag(key: StringName, on: bool = true) -> void:
	save_data.flags[key] = on


func has_flag(key: StringName) -> bool:
	return bool(save_data.flags.get(key, false))


# --- Global config -----------------------------------------------------------------

func _global_config_path() -> String:
	return save_root + "global_config.tres"


func _load_global_config() -> void:
	var path := _global_config_path()
	var existed := FileAccess.file_exists(path) or FileAccess.file_exists(_backup_path(path))
	if existed:
		global_config = _read_save_file(path) as GlobalConfig
		if global_config == null:
			_quarantine_save(path)
	if global_config == null:
		global_config = GlobalConfig.new()
	# Patch notes: a fresh install starts on this build and isn't shown its notes
	# unasked; a config from before the field gets every note since LEGACY_VERSION.
	if global_config.last_seen_version.is_empty():
		global_config.last_seen_version = PatchNotes.seed_version(existed)
	# @export Array/Dictionary defaults are shared between Resource instances (see
	# the same note in new_game). Re-bind so writes can't leak across instances.
	global_config.achievements_unlocked = global_config.achievements_unlocked.duplicate()
	global_config.achievement_unlock_times = global_config.achievement_unlock_times.duplicate()
	global_config.achievements_pending_steam = global_config.achievements_pending_steam.duplicate()
	global_config.keybinds = global_config.keybinds.duplicate()
	global_config.pad_binds = global_config.pad_binds.duplicate()
	# Deferred: the root is still adding autoloads while this runs.
	GraphicsQuality.apply_saved_window_mode.call_deferred()


func save_global_config() -> void:
	if global_config == null:
		global_config = GlobalConfig.new()
	_write_save_file(global_config, _global_config_path())


func _remember_current_slot() -> void:
	global_config.last_slot = current_slot
	save_global_config()


## Pad buttons never reach an action through the InputMap: PadCursor routes
## every press through Keybinds' pad bindings (rebindable, stored by the letter
## on the pad, with the Nintendo Layout applied there). So strip any joypad
## events project.godot carries on the bindable actions, otherwise a button
## would fire its old action as well as its new one.
func apply_pad_layout() -> void:
	for entry in Keybinds.REBINDABLE:
		var action: StringName = entry["action"]
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(action, ev)


# --- Quitting ----------------------------------------------------------------------

## Write everything dirty to user://. Two small .tres files, safe to repeat.
func flush_to_disk() -> void:
	if save_data != null:
		save_game()
	save_global_config()


## The single quit path: flush, close Steam down cleanly, then exit.
func request_quit() -> void:
	flush_to_disk()
	SteamManager.shutdown()
	get_tree().quit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			request_quit()
		NOTIFICATION_APPLICATION_PAUSED:
			# iOS/Android backgrounding: the OS may kill us with no further
			# notice, so this is the mobile equivalent of a close request.
			flush_to_disk()


# --- Save files: never lose one --------------------------------------------------
# Saves are text resources that can point at game content by res:// path.
# Godot refuses a whole file over one [ext_resource] it can't find, so content
# deleted or renamed in an update would otherwise make load_game start a new game
# and write it over the player's save. So:
#  - _read_save_file strips references to content that no longer exists (after
#    folding RETIRED_PATHS onto their successors) before loading, so the
#    save opens with just that entry missing. It works on a copy; the file on
#    disk is only replaced by the next normal save.
#  - _write_save_file writes to a temp file and renames it into place, keeping
#    the previous save as <name>.bak.tres, so a crash mid-write can't leave a
#    truncated save and a bad save has a fallback.
#  - A save that still can't be read is moved aside (<name>.unreadable-<time>.tres),
#    never overwritten.

func _backup_path(path: String) -> String:
	return path.get_basename() + ".bak.tres"


func _write_save_file(res: Resource, path: String) -> Error:
	var tmp := path.get_basename() + ".tmp.tres"
	var err := ResourceSaver.save(res, tmp)
	if err != OK:
		push_error("Could not write %s (error %d); the previous save is untouched." % [tmp, err])
		return err
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		var abs_bak := ProjectSettings.globalize_path(_backup_path(path))
		if FileAccess.file_exists(abs_bak):
			DirAccess.remove_absolute(abs_bak)
		DirAccess.rename_absolute(abs_path, abs_bak)
	err = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)
	if err != OK:
		push_error("Could not move %s into place (error %d)." % [tmp, err])
	else:
		save_written.emit()
	return err


## Load the save at `path`, falling back to its backup. Null only when neither
## can be read at all.
func _read_save_file(path: String) -> Resource:
	for candidate: String in [path, _backup_path(path)]:
		if not FileAccess.file_exists(candidate):
			continue
		var res := _load_repaired(candidate)
		if res != null:
			if candidate != path:
				push_warning("%s could not be read; loaded its backup instead." % path)
			return res
	return null


func _load_repaired(path: String) -> Resource:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var fixed := strip_missing_refs(text)
	var load_path := path
	if fixed != text:
		load_path = path.get_basename() + ".repair.tres"
		var w := FileAccess.open(load_path, FileAccess.WRITE)
		if w == null:
			return null
		w.store_string(fixed)
		w.close()
	var res := ResourceLoader.load(load_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		# Last resort: let the loader stand placeholders in for anything else it
		# can't find, rather than lose the file.
		ResourceLoader.set_abort_on_missing_resources(false)
		res = ResourceLoader.load(load_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		ResourceLoader.set_abort_on_missing_resources(true)
	if load_path != path:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(load_path))
	return res


## Text-level save repair: retired paths become their successors, and every
## reference to a Resource that no longer exists is dropped (array entries are
## removed, anything else becomes null). Unchanged text when nothing is stale.
## Godot writes arrays on one line ("[ExtResource("6"), ExtResource("7")]") and
## dictionary values after ": ", which is what the replacements rely on.
static func strip_missing_refs(text: String) -> String:
	var fixed := text
	for old_path: String in RETIRED_PATHS:
		fixed = fixed.replace('path="%s"' % old_path, 'path="%s"' % RETIRED_PATHS[old_path])
	var ext_re := RegEx.create_from_string('(?m)^\\[ext_resource ([^\\]]*)\\]\\n?')
	var attr_re := RegEx.create_from_string('(\\w+)="([^"]*)"')
	var dropped: Array[String] = []
	for m in ext_re.search_all(fixed):
		var attrs := {}
		for a in attr_re.search_all(m.get_string(1)):
			attrs[a.get_string(1)] = a.get_string(2)
		# Scripts stay: without one the whole save is meaningless anyway, and the
		# loader's own failure (then the backup) is the right outcome.
		if attrs.get("type", "") == "Script" or _ext_ref_exists(attrs):
			continue
		dropped.append(attrs.get("id", ""))
		fixed = fixed.replace(m.get_string(0), "")
	for id in dropped:
		var ref := 'ExtResource("%s")' % id
		fixed = fixed.replace("[%s, " % ref, "[")
		fixed = fixed.replace("[%s]" % ref, "[]")
		fixed = fixed.replace(", %s" % ref, "")
		fixed = fixed.replace(ref, "null")
	return fixed


static func _ext_ref_exists(attrs: Dictionary) -> bool:
	var uid_text: String = attrs.get("uid", "")
	if uid_text != "":
		var uid := ResourceUID.text_to_id(uid_text)
		if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid) \
				and ResourceLoader.exists(ResourceUID.get_id_path(uid)):
			return true
	var path: String = attrs.get("path", "")
	return path != "" and ResourceLoader.exists(path)


## Move an unreadable save (and its backup) out of the way so nothing overwrites
## it; a fix in a later build, or a person, can still recover it.
func _quarantine_save(path: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	for p: String in [path, _backup_path(path)]:
		if not FileAccess.file_exists(p):
			continue
		var dest := p.get_basename() + ".unreadable-%s.tres" % stamp
		DirAccess.rename_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(dest))
		push_error("Save %s could not be read; kept it as %s." % [p, dest])


## Test scenes and tools (by the scene path on the command line), and any
## headless boot, play in DEV_SANDBOX_DIR. TEMPLATE_REAL_SAVES=1 opts a launch
## back into the real saves.
func _pick_save_root() -> void:
	save_root = "user://"
	if OS.get_environment(REAL_SAVES_ENV) == "1":
		return
	var sandbox := DisplayServer.get_name() == "headless"
	for arg in OS.get_cmdline_args():
		if not arg.ends_with(".tscn"):
			continue
		var rel := arg.trim_prefix("res://")
		for dir in _SANDBOXED_SCENE_DIRS:
			if rel.begins_with(dir):
				sandbox = true
	if sandbox:
		save_root = DEV_SANDBOX_DIR
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_root))

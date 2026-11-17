extends Node
## Builds the Steamworks achievement bulk-upload bundle from the live roster
## (data/achievements/achievements.tres), so the partner site and the game can't
## drift apart:
##   steam_export/achievements/<app id>-achievements-definitions.csv
##   steam_export/achievements/<app id>-achievements-localization.csv  (English name + description)
##   steam_export/achievements/<API_NAME>_ACHIEVED.png   (256x256)
##
##   Godot --headless --path <project> tools/steam_achievements/export_steam_achievements.tscn
##
## Icons are the roster's textures, nearest-neighbour upscaled by the largest
## whole factor that fits ICON_CONTENT and centred on a dark square. An entry
## with no icon gets the plain dark square and a warning, so replace it before
## uploading. Fails (exit 1) on a missing or duplicate API name.

const OUT_DIR := "res://steam_export/achievements"
const CSV_NAME := "%d-achievements-definitions.csv"
const LOC_CSV_NAME := "%d-achievements-localization.csv"
const ICON_SIZE := 256
const ICON_CONTENT := 224
const ICON_BG := Color8(26, 22, 36)

## Steam's template header row, verbatim (the file Steam hands out starts with a BOM).
const LOC_CSV_HEADER := "api_name (required; must match an api_name from the definitions CSV),field (name or description),english"
const CSV_HEADER := "\"api_name (required, unique; the name your game passes to the API)\",setid (optional; the id of a set that already exists),\"permission (one of Client, GameServer, OfficialGameServer)\",spoiler (true or false),archived (true or false),\"progress_stat_name (optional; the name of a stat that already exists, blank for no progress bar)\",\"progress_stat_min (number, no lower than the stat's own min)\",\"progress_stat_max (number, above min and no higher than the stat's own max)\""


func _ready() -> void:
	var errors: Array[String] = []
	var defs := Achievements.get_all_defs()
	var seen_api: Dictionary = {}
	for ach in defs:
		if ach.steam_api_name.is_empty():
			errors.append("%s has no steam_api_name" % ach.id)
		elif seen_api.has(ach.steam_api_name):
			errors.append("duplicate API name %s" % ach.steam_api_name)
		seen_api[ach.steam_api_name] = true
		if ach.icon == null:
			push_warning("%s has no icon; exporting a blank placeholder" % ach.id)
	if not errors.is_empty():
		for e in errors:
			printerr("ERROR " + e)
		get_tree().quit(1)
		return

	var out_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Godot must never import the PNGs/CSV (they'd ship in the .pck).
	if not FileAccess.file_exists(out_dir.get_base_dir().path_join(".gdignore")):
		FileAccess.open(out_dir.get_base_dir().path_join(".gdignore"), FileAccess.WRITE).close()

	var rows := PackedStringArray([CSV_HEADER])
	var loc_rows := PackedStringArray([LOC_CSV_HEADER])
	for ach in defs:
		if ach.description.is_empty():
			errors.append("%s has no description" % ach.id)
		rows.append("%s,,Client,%s,false,,0,0" % [ach.steam_api_name, "true" if ach.hidden else "false"])
		loc_rows.append("%s,name,%s" % [ach.steam_api_name, _csv_field(ach.display_name)])
		loc_rows.append("%s,description,%s" % [ach.steam_api_name, _csv_field(ach.description)])
		var err := _icon_image(ach.icon).save_png(out_dir.path_join("%s_ACHIEVED.png" % ach.steam_api_name))
		if err != OK:
			errors.append("could not write icon for %s (%s)" % [ach.steam_api_name, error_string(err)])

	_write_csv(out_dir.path_join(CSV_NAME % SteamManager.APP_ID), rows)
	_write_csv(out_dir.path_join(LOC_CSV_NAME % SteamManager.APP_ID), loc_rows)

	print("Wrote %d achievements to %s" % [defs.size(), out_dir])
	for e in errors:
		printerr("ERROR " + e)
	get_tree().quit(1 if not errors.is_empty() else 0)


## Same shape as the templates Steam hands out: UTF-8 BOM, no trailing newline.
func _write_csv(path: String, rows: PackedStringArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	f.store_string("\n".join(rows))
	f.close()


## RFC 4180 quoting, only when the value needs it (a comma, quote or newline).
func _csv_field(value: String) -> String:
	if value.contains(",") or value.contains("\"") or value.contains("\n"):
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value


## Read the source PNG directly rather than the imported texture, so the pixels
## are exactly the authored ones whatever the import's compression settings.
func _icon_image(tex: Texture2D) -> Image:
	var blank := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	blank.fill(ICON_BG)
	if tex == null:
		return blank
	var src := Image.load_from_file(ProjectSettings.globalize_path(tex.resource_path))
	if src == null:
		# Not a file on disk (an atlas region, a generated texture): use its pixels.
		src = tex.get_image()
	if src == null:
		return blank
	src.convert(Image.FORMAT_RGBA8)
	var k := maxi(1, ICON_CONTENT / maxi(src.get_width(), src.get_height()))
	src.resize(src.get_width() * k, src.get_height() * k, Image.INTERPOLATE_NEAREST)
	var out := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	out.fill(ICON_BG)
	var at := (Vector2i(ICON_SIZE, ICON_SIZE) - src.get_size()) / 2
	out.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)
	return out

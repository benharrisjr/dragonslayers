class_name PatchNotes
extends RefCounted
## Release notes shown on the main menu (PatchNotesPanel). Newest first, one entry
## per release that has notes. Kept in a script const rather than a
## .txt so exports can't drop it (non-resource files aren't exported by default).
##
## Text format: a line starting with "# " is a sub-heading, "- " a bullet; any
## other line is a plain paragraph line, blank lines kept as spacing.
##
## GlobalConfig.last_seen_version remembers the newest build the player has
## launched. A build newer than that pops its unseen notes once on the main menu; a
## fresh install is seeded to the current version so it never auto-pops (the
## version button in the menu corner still opens them).

const NOTES: Array[Dictionary] = [
	{"version": "0.1.0", "text": """# New Features
- Full gamepad support: every menu and the whole match can be played on a controller
- Press-to-join lobby: any mix of keyboard and gamepads can claim a seat
- Main menu, options, pause menu and a way back out of a finished hunt
"""},
]

## The version a pre-patch-notes install is assumed to have been on.
const LEGACY_VERSION := "0.0.0"


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", LEGACY_VERSION))


## -1 / 0 / 1 for a < b / a == b / a > b, comparing dot-separated numbers ("1.10"
## beats "1.9"; missing parts count as 0, so "1.1" == "1.1.0").
static func compare(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


## Entries newer than `last_seen` and no newer than `current` (a notes entry
## written ahead of its release stays hidden), newest first.
static func unseen_since(last_seen: String, current: String = current_version()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in NOTES:
		var v: String = entry["version"]
		if compare(v, last_seen) > 0 and compare(v, current) <= 0:
			out.append(entry)
	return out


## Entries released as of `current`, newest first: what the browser pages through.
static func released(current: String = current_version()) -> Array[Dictionary]:
	return unseen_since("0", current)


## What GlobalConfig.last_seen_version starts as when unset: a config from before
## the field predates patch notes, so it gets every note;
## a fresh install starts on the current build and sees none automatically.
static func seed_version(config_existed: bool) -> String:
	return LEGACY_VERSION if config_existed else current_version()


## The notes text as BBCode for a RichTextLabel (see the format note above).
static func to_bbcode(text: String) -> String:
	var lines: PackedStringArray = []
	var bullets: PackedStringArray = []
	for raw in text.strip_edges().split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("- "):
			bullets.append(_escape(line.substr(2)))
			continue
		_flush_bullets(lines, bullets)
		if line.begins_with("# "):
			lines.append("[color=#ffe073]%s[/color]" % _escape(line.substr(2)))
		else:
			lines.append(_escape(line))
	_flush_bullets(lines, bullets)
	return "\n".join(lines)


## A run of "- " lines as one [ul] list, so wrapped lines hang under their text.
static func _flush_bullets(lines: PackedStringArray, bullets: PackedStringArray) -> void:
	if bullets.is_empty():
		return
	lines.append("[ul]%s[/ul]" % "\n".join(bullets))
	bullets.clear()


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")

#!/usr/bin/env python3
"""Find art/sound the game never uses and keep it out of exported builds.

Every export preset uses export_filter="all_resources", so every imported file
in the project ships in the .pck unless it's listed in exclude_filter. This
script works out which assets are unused and writes that exclude list. Files
are never deleted, only excluded from the export.

How it decides what's used:
  * Reachability starts at project.godot (main scene + autoloads) and also at
    every game-side .gd/.tscn/.tres, even unwired ones. That keeps the
    cave/ocean/tower environments and retired .tres working if they're wired
    up later.
  * Edges are res:// literals (comment lines in .gd/.gdshader are ignored),
    relative ext_resource paths, uid:// ids, class_name usage, and the
    external texture URIs inside .glb/.gltf models. A res:// literal ending in "/"
    (string-built paths like banner_label.gd's BASE_PATH) keeps that whole
    folder.
  * KEEP_PREFIXES / _is_kept() always win (format-string paths, the UISF frame
    palette, every SFX).
  * TOOLING_ROOTS are excluded wholesale: nothing in the game loads from them.

Usage (from the project root):
  python3 tools/asset_audit/find_unused_assets.py --report [--pck PCK]
  python3 tools/asset_audit/find_unused_assets.py --write
  python3 tools/asset_audit/find_unused_assets.py --verify PCK

--verify reads an exported .pck and checks that every dependency of every
exported scene/resource/script is also in it. Any miss means the exclude list
cut something that's in use.

Re-run --write after adding or removing assets.
"""

import argparse
import collections
import json
import os
import re
import struct
import sys
import urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

SKIP_DIRS = {".git", ".godot", ".claude"}

# Excluded wholesale. Editor/dev-only content; the game never loads from here.
TOOLING_ROOTS = (
	"tools/", "tests/", "docs/", "builds/", "export_promo/", "export_frames/",
	"free_fantasy_rpg_icons/",
)

# Always shipped, even when nothing references them literally.
KEEP_PREFIXES = (
	# keybinds.gd builds "tile_%04d.png" at runtime.
	"art/icons/input-prompts-pixel-16/Tiles/",
)


def _is_kept(path: str) -> bool:
	if path.startswith(KEEP_PREFIXES):
		return True
	# Keep every SFX. Only unused music/ambience tracks get trimmed.
	if path.startswith("sound/") and not path.startswith(("sound/music/", "sound/ambience/")):
		return True
	return False


TEXT_EXTS = (".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".godot", ".cfg")
# Non-imported files Godot still exports as resources.
RESOURCE_EXTS = (".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".res", ".scn")

# A quoted path runs to its own closing quote, so "res://…Don't…" keeps the
# apostrophe; unquoted mentions stop at whitespace or any quote.
_RES_RE = re.compile(r'"res://([^"\n]+)|\'res://([^\'\n]+)|res://([^"\'\s]+)')


def _res_paths(t: str) -> list[str]:
	return [a or b or c for a, b, c in _RES_RE.findall(t)]
# ext_resource paths can also be relative ("./foo.png"), as in downloaded material packs.
_EXT_PATH_RE = re.compile(r'^\[ext_resource[^\]]*\bpath="(?!res://)([^"]+)"', re.M)
_UID_RE = re.compile(r'uid://[a-z0-9]+')
_HEADER_UID_RE = re.compile(r'^\[gd_\w+[^\]]*uid="(uid://[a-z0-9]+)"')
_CLASS_RE = re.compile(r'^class_name\s+(\w+)', re.M)
_WORD_RE = re.compile(r'\b([A-Z]\w+)\b')


class Project:
	def __init__(self) -> None:
		self.files: list[str] = []        # every non-skipped file, project-relative
		self.lower: dict[str, str] = {}   # case-insensitive lookup (macOS FS)
		self.imported: set[str] = set()   # sources that have a .import sidecar
		self.uid2path: dict[str, str] = {}
		self.texts: dict[str, str] = {}
		self.classes: dict[str, str] = {}
		self._scan()

	def _scan(self) -> None:
		for root, dirs, names in os.walk(ROOT):
			rel_root = os.path.relpath(root, ROOT)
			rel_root = "" if rel_root == "." else rel_root + "/"
			if ".gdignore" in names:
				dirs[:] = []
				continue
			dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
			for name in names:
				p = rel_root + name
				self.files.append(p)
				self.lower[p.lower()] = p
				full = os.path.join(root, name)
				if name.endswith((".import", ".uid")):
					src = p.rsplit(".", 1)[0]
					if name.endswith(".import"):
						self.imported.add(src)
					t = _read(full)
					m = re.search(r'uid="?(uid://[a-z0-9]+)', t) or re.search(r'^(uid://[a-z0-9]+)', t)
					if m:
						self.uid2path[m.group(1)] = src
				elif name.endswith(TEXT_EXTS):
					t = _read(full)
					if name.endswith((".gd", ".gdshader", ".gdshaderinc")):
						t = "\n".join(l for l in t.split("\n") if not l.lstrip().startswith(("#", "//")))
					self.texts[p] = t
					m = _HEADER_UID_RE.search(t)
					if m:
						self.uid2path[m.group(1)] = p
					if name.endswith(".gd"):
						m = _CLASS_RE.search(t)
						if m:
							self.classes[m.group(1)] = p

	def deps(self, p: str) -> set[str]:
		if p in self.imported:
			return self._import_deps(p)
		t = self.texts.get(p)
		if t is None:
			return set()
		out: set[str] = set()
		for r in _res_paths(t):
			r = r.strip()
			if r.endswith("/"):
				out.update(f for f in self.files if f.startswith(r) and not f.endswith(".import"))
			out.add(self.lower.get(r.lower(), r))
		base = os.path.dirname(p)
		for r in _EXT_PATH_RE.findall(t):
			r = os.path.normpath(os.path.join(base, r))
			out.add(self.lower.get(r.lower(), r))
		for u in _UID_RE.findall(t):
			if u in self.uid2path:
				out.add(self.uid2path[u])
		if p.endswith(".gd"):
			for w in set(_WORD_RE.findall(t)):
				if w in self.classes:
					out.add(self.classes[w])
		return out

	def _import_deps(self, p: str) -> set[str]:
		"""Import settings can pull in resources too (external materials on a .glb)."""
		out: set[str] = set()
		for r in _res_paths(_read(os.path.join(ROOT, p + ".import"))):
			if not r.startswith(".godot/"):
				out.add(self.lower.get(r.lower(), r))
		out.discard(p)
		if p.lower().endswith((".glb", ".gltf")):
			out |= self._model_deps(p)
		return out

	def _model_deps(self, p: str) -> set[str]:
		"""External images a glTF model points at (e.g. Kenney's Textures/colormap.png)."""
		try:
			with open(os.path.join(ROOT, p), "rb") as f:
				data = f.read()
			if p.lower().endswith(".glb"):
				n, = struct.unpack("<I", data[12:16])
				doc = json.loads(data[20:20 + n])
			else:
				doc = json.loads(data)
		except (OSError, ValueError, struct.error):
			return set()
		out: set[str] = set()
		for key in ("images", "buffers"):
			for entry in doc.get(key, []):
				uri = entry.get("uri", "")
				if uri and not uri.startswith("data:"):
					r = os.path.normpath(os.path.join(os.path.dirname(p), urllib.parse.unquote(uri)))
					out.add(self.lower.get(r.lower(), r))
		return out

	def closure(self, roots) -> set[str]:
		seen: set[str] = set()
		stack = list(roots)
		while stack:
			p = stack.pop()
			if p in seen:
				continue
			seen.add(p)
			stack.extend(self.deps(p) - seen)
		return seen

	def exportable(self) -> list[str]:
		"""Files Godot would put in the .pck under all_resources."""
		return [f for f in self.files if f in self.imported or f.endswith(RESOURCE_EXTS) or f == "project.godot"]


def _read(path: str) -> str:
	with open(path, encoding="utf-8", errors="ignore") as f:
		return f.read()


def analyse(proj: Project):
	exportable = proj.exportable()
	# Unwired game content (scenes/, data/, ...) still counts as using its assets.
	# Stray .tres inside art/ (material packs etc.) don't: they're only kept
	# when something else in the game references them.
	game_texts = [p for p in proj.texts if not p.startswith(TOOLING_ROOTS + ("art/",))]
	used = proj.closure(["project.godot"] + game_texts)
	reachable = proj.closure(["project.godot"])
	excluded = set()
	for f in exportable:
		if f.startswith(TOOLING_ROOTS):
			excluded.add(f)
		elif f not in used and not _is_kept(f) and (f in proj.imported or f.startswith("art/")):
			excluded.add(f)
	orphan_only = {f for f in exportable if f in proj.imported and f in used and f not in reachable}
	return exportable, excluded, orphan_only


def build_filters(exportable: list[str], excluded: set[str]) -> list[str]:
	"""Collapse to the shallowest folder whose exportable files are all excluded."""
	by_dir = collections.defaultdict(list)
	for f in exportable:
		parts = f.split("/")
		for i in range(1, len(parts)):
			by_dir["/".join(parts[:i])].append(f)
	full_dirs = {d for d, fs in by_dir.items() if all(f in excluded for f in fs)}
	filters: list[str] = []
	covered: set[str] = set()
	for root in TOOLING_ROOTS:
		filters.append(root + "*")
		covered.update(f for f in excluded if f.startswith(root))
	for d in sorted(full_dirs, key=lambda d: (d.count("/"), d)):
		if any((d + "/").startswith(c[:-1]) for c in filters if c.endswith("/*")):
			continue
		filters.append(d + "/*")
		covered.update(f for f in excluded if f.startswith(d + "/"))
	filters.extend(sorted(f for f in excluded if f not in covered))
	for f in filters:
		if "," in f:
			sys.exit(f"Filename contains a comma; Godot's filter list can't express it: {f}")
	return filters


# ── PCK reading ──────────────────────────────────────────────────────────────

def read_pck(path: str) -> list[tuple[str, int]]:
	with open(path, "rb") as f:
		if f.read(4) != b"GDPC":
			sys.exit(f"{path} is not a Godot .pck")
		ver, _, _, _ = struct.unpack("<4I", f.read(16))
		f.read(4 + 8)  # flags, file_base
		if ver >= 3:
			dir_offset, = struct.unpack("<Q", f.read(8))
			f.seek(dir_offset)
		else:
			f.read(64)
		count, = struct.unpack("<I", f.read(4))
		out = []
		for _ in range(count):
			n, = struct.unpack("<I", f.read(4))
			p = f.read(n).rstrip(b"\0").decode()
			_, size = struct.unpack("<QQ", f.read(16))
			f.read(16 + 4)  # md5, flags
			out.append((p.removeprefix("res://"), size))
		return out


def pck_source_sizes(proj: Project, pck: str) -> dict[str, int]:
	dest2src = {}
	for src in proj.imported:
		for m in re.findall(r'"res://(\.godot/imported/[^"]+)"', _read(os.path.join(ROOT, src + ".import"))):
			dest2src[m] = src
	sizes: collections.Counter = collections.Counter()
	for p, size in read_pck(pck):
		sizes[dest2src.get(p, p)] += size
	return sizes


def verify(proj: Project, pck: str) -> int:
	present = set()
	for p, _ in read_pck(pck):
		for suffix in (".import", ".remap"):
			if p.endswith(suffix):
				p = p[: -len(suffix)]
		if p.endswith(".gdc"):
			p = p[:-1]
		present.add(p)
	exportable = set(proj.exportable())
	missing = collections.defaultdict(list)
	for src in sorted(p for p in list(proj.texts) + list(proj.imported) if p in present):
		for dep in proj.deps(src):
			if dep in exportable and dep not in present:
				missing[dep].append(src)
	if not missing:
		print(f"OK: every dependency of the {len(present)} exported entries is in {os.path.basename(pck)}")
		return 0
	print(f"MISSING {len(missing)} dependencies (over-excluded):")
	for dep, users in sorted(missing.items()):
		print(f"  {dep}  <- {', '.join(users[:3])}{' …' if len(users) > 3 else ''}")
	return 1


# ── export_presets.cfg ───────────────────────────────────────────────────────

def write_presets(filters: list[str]) -> int:
	path = os.path.join(ROOT, "export_presets.cfg")
	value = ", ".join(filters).replace("\\", "\\\\").replace('"', '\\"')
	lines = _read(path).split("\n")
	n = 0
	for i, line in enumerate(lines):
		if line.startswith("exclude_filter="):
			lines[i] = f'exclude_filter="{value}"'
			n += 1
	with open(path, "w", encoding="utf-8") as f:
		f.write("\n".join(lines))
	return n


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
	ap.add_argument("--report", action="store_true", help="print what would be excluded")
	ap.add_argument("--pck", help="exported .pck to size the report with (default: on-disk sizes)")
	ap.add_argument("--write", action="store_true", help="write exclude_filter into every preset")
	ap.add_argument("--verify", metavar="PCK", help="check an exported .pck for missing dependencies")
	args = ap.parse_args()
	if not (args.report or args.write or args.verify):
		args.report = True

	proj = Project()
	if args.verify:
		return verify(proj, args.verify)

	exportable, excluded, orphan_only = analyse(proj)
	filters = build_filters(exportable, excluded)

	if args.report:
		if args.pck:
			sizes = pck_source_sizes(proj, args.pck)
		else:
			sizes = {f: os.path.getsize(os.path.join(ROOT, f)) for f in exportable}
		def mb(fs):
			return sum(sizes.get(f, 0) for f in fs) / 1e6
		by_filter = []
		for flt in filters:
			fs = [f for f in excluded if (f.startswith(flt[:-1]) if flt.endswith("/*") else f == flt)]
			by_filter.append((mb(fs), len(fs), flt))
		by_filter.sort(reverse=True)
		print(f"Exportable total: {mb(exportable):.1f} MB")
		print(f"Excluded:         {mb(excluded):.1f} MB in {len(excluded)} files, {len(filters)} filter entries")
		print(f"Kept, only used by unwired scenes: {mb(orphan_only):.1f} MB\n")
		for size, count, flt in by_filter:
			if size >= 0.02:
				print(f"{size:8.2f} MB {count:5d}  {flt}")
		rest = [x for x in by_filter if x[0] < 0.02]
		print(f"{sum(x[0] for x in rest):8.2f} MB        (+{len(rest)} smaller entries)")

	if args.write:
		n = write_presets(filters)
		print(f"Wrote {len(filters)} exclude entries into {n} presets in export_presets.cfg")
	return 0


if __name__ == "__main__":
	sys.exit(main())

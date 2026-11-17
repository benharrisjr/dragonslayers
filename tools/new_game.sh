#!/usr/bin/env bash
# Rename the template for a new game. Rewrites the names that must agree across
# project.godot, project.env and export_presets.cfg.
#
#   tools/new_game.sh "My Game" my-game com.vgmrx.mygame
#
#   "My Game"          display name (window title, main menu title)
#   my-game            slug: binary file name and user-data folder (no spaces)
#   com.vgmrx.mygame   bundle / package identifier (macOS, iOS, Android)
#
# Everything else per-game lives in data/project_config.gd and
# steam/steam_ids.env; see README.md.

set -euo pipefail

if [[ $# -ne 3 ]]; then
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

NAME="$1"; SLUG="$2"; BUNDLE="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "ERROR: slug must be lowercase letters, digits and dashes." >&2; exit 1
fi

# shellcheck disable=SC1091
source project.env
OLD_SLUG="$GAME_NAME"

NAME="$NAME" SLUG="$SLUG" BUNDLE="$BUNDLE" OLD_SLUG="$OLD_SLUG" python3 - <<'PY'
import os, re
name, slug, bundle, old = (os.environ[k] for k in ("NAME", "SLUG", "BUNDLE", "OLD_SLUG"))

def rewrite(path, fn):
    with open(path) as f:
        text = f.read()
    with open(path, "w") as f:
        f.write(fn(text))

def project(t):
    t = re.sub(r'(?m)^config/name=".*"$', 'config/name="%s"' % name.replace('"', '\\"'), t)
    t = re.sub(r'(?m)^config/custom_user_dir_name=".*"$', 'config/custom_user_dir_name="%s"' % slug, t)
    return t

def env(t):
    t = re.sub(r'(?m)^GAME_NAME=".*"$', 'GAME_NAME="%s"' % slug, t)
    t = re.sub(r'(?m)^GDRIVE_FOLDER_DEFAULT=".*"$', 'GDRIVE_FOLDER_DEFAULT="%s-builds"' % slug, t)
    return t

def presets(t):
    t = re.sub(r'(?m)^(export_path="builds/[^"]*/)%s(\.[^"]*")$' % re.escape(old), r'\g<1>%s\g<2>' % slug, t)
    t = re.sub(r'(?m)^(application/bundle_identifier=)".*"$', r'\1"%s"' % bundle, t)
    t = re.sub(r'(?m)^(package/unique_name=)".*"$', r'\1"%s"' % bundle.replace("-", ""), t)
    return t

rewrite("project.godot", project)
rewrite("project.env", env)
rewrite("export_presets.cfg", presets)
PY

echo "Renamed to \"$NAME\" ($SLUG, $BUNDLE)."
echo "Next: fill in data/project_config.gd and steam/steam_ids.env (see README.md)."

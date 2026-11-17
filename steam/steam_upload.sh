#!/usr/bin/env bash
# Export the game's desktop builds and upload them to Steam via SteamPipe (steamcmd).
# Uploads never set a build live — do that by hand on the Steamworks partner site.
# One-time setup: see steam/README.md.
#
# USAGE:
#   steam/steam_upload.sh --app full|demo [options]
#
# OPTIONS:
#   --app full|demo   which Steam app to upload to (IDs in steam/steam_ids.env)
#   --desc TEXT       build description shown on the partner site
#                     (default: git describe + branch)
#   --preview         steamcmd dry run: builds manifests, uploads nothing
#   --skip-export     reuse the content already staged in builds/steam/<app>/
#
# ENV VARS:
#   STEAM_BUILDER_USER  Steam account steamcmd logs in as (required)
#   GODOT               path to Godot binary (auto-detected if not set)
#   STEAMCMD            path to steamcmd (default: steamcmd on PATH)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_DIR/project.env"

APP=""
DESC=""
PREVIEW=0
SKIP_EXPORT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --app)         APP="$2"; shift ;;
        --desc)        DESC="$2"; shift ;;
        --preview)     PREVIEW=1 ;;
        --skip-export) SKIP_EXPORT=true ;;
        -h|--help)
            sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "$APP" == "full" || "$APP" == "demo" ]] || die "--app full|demo is required."

# ── IDs ───────────────────────────────────────────────────────────────────────

# shellcheck disable=SC1091
source "$PROJECT_DIR/steam/steam_ids.env"

PREFIX=$(echo "$APP" | tr '[:lower:]' '[:upper:]')
id_for() { local var="${PREFIX}_$1"; echo "${!var:-}"; }

APP_ID=$(id_for APP_ID)
[[ -n "$APP_ID" ]] || die "${PREFIX}_APP_ID is blank in steam/steam_ids.env."

# depot key (= staging subdir) → "<steam_ids.env suffix>|<export preset>|<binary name>"
DEPOT_KEYS=(windows mac linux_x64 linux_arm64)
depot_spec() {
    case $1 in
        windows)     echo "DEPOT_WINDOWS|Windows Desktop|$GAME_NAME.exe" ;;
        mac)         echo "DEPOT_MAC|macOS|$GAME_NAME.app" ;;
        linux_x64)   echo "DEPOT_LINUX_X64|Linux x86_64|$GAME_NAME.x86_64" ;;
        linux_arm64) echo "DEPOT_LINUX_ARM64|Linux arm64|$GAME_NAME.arm64" ;;
    esac
}

ACTIVE_KEYS=()
for key in "${DEPOT_KEYS[@]}"; do
    IFS='|' read -r suffix _ _ <<< "$(depot_spec "$key")"
    if [[ -n "$(id_for "$suffix")" ]]; then
        ACTIVE_KEYS+=("$key")
    else
        echo "Skipping $key: ${PREFIX}_${suffix} is blank."
    fi
done
[[ ${#ACTIVE_KEYS[@]} -gt 0 ]] || die "no ${PREFIX}_DEPOT_* IDs set in steam/steam_ids.env."

# ── Tools ─────────────────────────────────────────────────────────────────────

[[ -n "${STEAM_BUILDER_USER:-}" ]] || die "set STEAM_BUILDER_USER to the steamcmd builder account."

STEAMCMD="${STEAMCMD:-steamcmd}"
command -v "$STEAMCMD" &>/dev/null || die "steamcmd not found (brew install --cask steamcmd, or set STEAMCMD)."

find_godot() {
    if [[ -n "${GODOT:-}" ]]; then
        echo "$GODOT"; return
    fi
    for bin in godot godot4 Godot godot-4; do
        if command -v "$bin" &>/dev/null; then
            echo "$bin"; return
        fi
    done
    local app
    for app in "/Applications/Godot.app/Contents/MacOS/Godot" "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
        if [[ -f "$app" ]]; then
            echo "$app"; return
        fi
    done
    die "Godot binary not found. Set the GODOT env var or add it to PATH."
}

if [[ -z "$DESC" ]]; then
    VERSION=$(git -C "$PROJECT_DIR" describe --tags --always --dirty 2>/dev/null || date +%Y%m%d-%H%M%S)
    BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    DESC="$APP $VERSION ($BRANCH)"
fi

STAGE_DIR="$PROJECT_DIR/builds/steam/$APP"
CONTENT_DIR="$STAGE_DIR/content"
SCRIPTS_DIR="$STAGE_DIR/scripts"
OUTPUT_DIR="$STAGE_DIR/output"

echo "App:   $APP ($APP_ID)"
echo "Desc:  $DESC"
echo "Depots: ${ACTIVE_KEYS[*]}"
[[ $PREVIEW -eq 1 ]] && echo "Mode:  PREVIEW (nothing will be uploaded)"
echo ""

# ── Export ────────────────────────────────────────────────────────────────────

if [[ "$SKIP_EXPORT" == false ]]; then
    GODOT=$(find_godot)
    echo "Godot: $GODOT"
    # The open editor can wipe the generated exclude list; regenerate it.
    python3 "$PROJECT_DIR/tools/asset_audit/find_unused_assets.py" --write
    for key in "${ACTIVE_KEYS[@]}"; do
        IFS='|' read -r _ preset binary <<< "$(depot_spec "$key")"
        local_dir="$CONTENT_DIR/$key"
        echo "==> Exporting $key ($preset)"
        # Wipe first so stale files (old zips, debug libs, renamed assets) never ship.
        rm -rf "$local_dir"
        mkdir -p "$local_dir"
        "$GODOT" --headless --path "$PROJECT_DIR" --export-release "$preset" "$local_dir/$binary"
        case $key in
            windows) rm -f "$local_dir"/*.console.exe ;;
            linux_*) chmod +x "$local_dir/$binary" "$local_dir"/*.sh 2>/dev/null || true ;;
        esac
    done
    echo ""
fi

for key in "${ACTIVE_KEYS[@]}"; do
    IFS='|' read -r _ _ binary <<< "$(depot_spec "$key")"
    [[ -e "$CONTENT_DIR/$key/$binary" ]] || die "missing $CONTENT_DIR/$key/$binary (export failed, or drop --skip-export)."
done

# ── VDFs ──────────────────────────────────────────────────────────────────────

rm -rf "$SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR" "$OUTPUT_DIR"

depot_lines=""
for key in "${ACTIVE_KEYS[@]}"; do
    IFS='|' read -r suffix _ _ <<< "$(depot_spec "$key")"
    depot_id=$(id_for "$suffix")
    cat > "$SCRIPTS_DIR/depot_build_$depot_id.vdf" <<VDF
"DepotBuildConfig"
{
	"DepotID" "$depot_id"
	"ContentRoot" "$CONTENT_DIR/$key"
	"FileMapping"
	{
		"LocalPath" "*"
		"DepotPath" "."
		"recursive" "1"
	}
	"FileExclusion" "steam_appid.txt"
	"FileExclusion" "*.pdb"
	"FileExclusion" ".DS_Store"
}
VDF
    depot_lines+=$'\t\t'"\"$depot_id\" \"depot_build_$depot_id.vdf\""$'\n'
done

APP_VDF="$SCRIPTS_DIR/app_build_$APP_ID.vdf"
VDF_DESC=$(printf '%s' "$DESC" | tr -d '"')
# SetLive stays empty on purpose: builds go live by hand on the partner site.
cat > "$APP_VDF" <<VDF
"AppBuild"
{
	"AppID" "$APP_ID"
	"Desc" "$VDF_DESC"
	"Preview" "$PREVIEW"
	"SetLive" ""
	"ContentRoot" "$CONTENT_DIR"
	"BuildOutput" "$OUTPUT_DIR"
	"Depots"
	{
${depot_lines}	}
}
VDF

echo "VDFs:  $SCRIPTS_DIR"
echo ""

# ── Upload ────────────────────────────────────────────────────────────────────

echo "==> steamcmd run_app_build (as $STEAM_BUILDER_USER)"
"$STEAMCMD" +login "$STEAM_BUILDER_USER" +run_app_build "$APP_VDF" +quit

echo ""
if [[ $PREVIEW -eq 1 ]]; then
    echo "Preview complete — nothing uploaded. Logs: $OUTPUT_DIR"
else
    echo "Upload complete. Set the build live by hand:"
    echo "  https://partner.steamgames.com/apps/builds/$APP_ID"
fi

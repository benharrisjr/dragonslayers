#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/project.env"
LOG_DIR="$ROOT_DIR/cron/logs"
LOCK_DIR="${TMPDIR:-/tmp}/${GAME_NAME}-nightly-build.lock"
ENV_FILE="${NIGHTLY_CRON_ENV:-$HOME/.config/$GAME_NAME/nightly-build.env}"

mkdir -p "$LOG_DIR"
exec >> "$LOG_DIR/nightly-build.log" 2>&1

printf '\n[%s] Nightly build started\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another nightly build is already running; exiting."
    exit 0
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: refusing to build because the worktree is not clean."
    git status --short
    exit 1
fi

git fetch origin main
git checkout main
git pull --ff-only origin main

read -r -a build_platforms <<< "${NIGHTLY_BUILD_PLATFORMS:-all}"

"$ROOT_DIR/build.sh" \
    --gdrive-remote "${GDRIVE_REMOTE:-gdrive}" \
    --gdrive-folder "${GDRIVE_FOLDER:-$GDRIVE_FOLDER_DEFAULT}" \
    "${build_platforms[@]}"

printf '[%s] Nightly build finished successfully\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
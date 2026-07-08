#!/bin/bash
# Single entry point: starts the host font-cache watcher and the FontyPython
# container together, and tears both down together on exit.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "run.sh: inotifywait not found — the host font-cache watcher can't run without it." >&2
  echo "Install it with: sudo apt install inotify-tools" >&2
  exit 1
fi

expand_home() {
  local path="$1"
  case "$path" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${path#~/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

quote_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\\$}"
  value="${value//\`/\\\`}"
  printf '"%s"' "$value"
}

prompt_path() {
  local prompt="$1" default="$2" value
  read -r -p "$prompt [$default]: " value
  value="${value:-$default}"
  expand_home "$value"
}

ensure_env_file() {
  [ -f .env ] && return 0

  echo "run.sh: .env not found; let's configure FontyPython host paths."

  local collection_dir active_dir settings_dir
  collection_dir="$(prompt_path "Where do you store your font collection" "$HOME/Resources/fonts")"
  active_dir="$(prompt_path "Where does your system store its active fonts" "$HOME/.fonts")"
  settings_dir="$(prompt_path "Where do you wish to save FontyPython settings" "$HOME/.fontypython")"

  {
    echo "# Created by run.sh. These are HOST paths used by docker-compose.yml."
    printf 'FONTYPYTHON_FONT_COLLECTION_DIR=%s\n' "$(quote_env_value "$collection_dir")"
    printf 'FONTYPYTHON_ACTIVE_FONT_DIR=%s\n' "$(quote_env_value "$active_dir")"
    printf 'FONTYPYTHON_SETTINGS_DIR=%s\n' "$(quote_env_value "$settings_dir")"
  } > .env

  echo "run.sh: wrote .env"
}

ensure_env_file
set -a
. ./.env
set +a

: "${FONTYPYTHON_FONT_COLLECTION_DIR:?Missing FONTYPYTHON_FONT_COLLECTION_DIR in .env}"
: "${FONTYPYTHON_ACTIVE_FONT_DIR:?Missing FONTYPYTHON_ACTIVE_FONT_DIR in .env}"
: "${FONTYPYTHON_SETTINGS_DIR:?Missing FONTYPYTHON_SETTINGS_DIR in .env}"

# The image is built to run AS you (matching uid/gid), not root — these
# get passed through as Docker build args (see docker-compose.yml).
export HOST_UID
export HOST_GID
export HOST_USER
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
HOST_USER="$(id -un)"

mkdir -p "$FONTYPYTHON_ACTIVE_FONT_DIR" "$FONTYPYTHON_FONT_COLLECTION_DIR" "$FONTYPYTHON_SETTINGS_DIR"

# Catch root-owned leftovers from any earlier root-based container run —
# the container now runs as you (see Dockerfile/docker-compose.yml), so
# it can't write to files it doesn't own, and FontyPython fails with a
# confusing PogWriteError instead of a clear permissions message.
check_ownership() {
  local dir="$1" bad
  [ -d "$dir" ] || return 0
  bad="$(find "$dir" ! -user "$HOST_USER" -print -quit 2>/dev/null)"
  if [ -n "$bad" ]; then
    echo "run.sh: found files not owned by $HOST_USER under $dir (e.g. $bad)." >&2
    echo "This is leftover from an earlier root-based run. Fix with:" >&2
    echo "  sudo chown -R \"$HOST_USER\":\"$HOST_USER\" \"$FONTYPYTHON_ACTIVE_FONT_DIR\" \"$FONTYPYTHON_FONT_COLLECTION_DIR\" \"$FONTYPYTHON_SETTINGS_DIR\"" >&2
    exit 1
  fi
}
check_ownership "$FONTYPYTHON_ACTIVE_FONT_DIR"
check_ownership "$FONTYPYTHON_FONT_COLLECTION_DIR"
check_ownership "$FONTYPYTHON_SETTINGS_DIR"

./fonts-host-watch.sh &
WATCH_PID=$!
trap 'kill "$WATCH_PID" 2>/dev/null || true' EXIT

docker compose up --build

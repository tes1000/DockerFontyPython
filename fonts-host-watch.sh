#!/bin/bash
# Runs on the HOST (not in the container). Watches the configured active
# fonts directory the container writes into, and rebuilds the HOST's fontconfig
# cache whenever it changes. This is the piece that makes `fc-list` on the
# host reflect activations/deactivations immediately — fc-cache run inside
# the container only ever touches the container's own cache, never the
# host's, no matter how the volumes are wired up.
set -euo pipefail

ACTIVE_FONT_DIR="${FONTYPYTHON_ACTIVE_FONT_DIR:-$HOME/.fonts}"
mkdir -p "$ACTIVE_FONT_DIR"

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "inotifywait not found. Install it with: sudo apt install inotify-tools" >&2
  exit 1
fi

echo "[host-watch] Priming fontconfig cache for $ACTIVE_FONT_DIR"
fc-cache -f "$ACTIVE_FONT_DIR"

echo "[host-watch] Watching $ACTIVE_FONT_DIR for changes..."
while inotifywait -r -e create,delete,modify,move,close_write "$ACTIVE_FONT_DIR" >/dev/null 2>&1; do
  echo "[host-watch] $(date '+%H:%M:%S') change detected — refreshing host fontconfig cache"
  fc-cache -f "$ACTIVE_FONT_DIR"
done

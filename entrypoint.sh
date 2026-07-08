#!/bin/bash
set -e

# $HOME is set (via docker-compose.yml) to the HOST's real home path, e.g.
# /home/aiko — not /root. Everything below operates under that path so it
# lines up exactly with what's bind-mounted from the host.
ACTIVE_FONT_DIR="$HOME/.fonts"
LIBRARY_DIR="$HOME/Resources/fonts"

mkdir -p \
    "$ACTIVE_FONT_DIR" \
    "$LIBRARY_DIR" \
    "$HOME/Desktop" \
    "$HOME/Documents" \
    "$HOME/Downloads" \
    "$HOME/.config" \
    "$HOME/.fontypython"

echo "Building initial container-side font cache..."
fc-cache -f "$ACTIVE_FONT_DIR" || true

# This only keeps FontyPython's OWN in-app previews/rendering in sync with
# what's on disk. It does NOT and CANNOT refresh the host's fontconfig
# cache — that runs in a different mount namespace with its own cache
# format. The host needs its own watcher (see fonts-host-watch.sh).
echo "Starting in-container font watcher..."
(
  while true; do
    inotifywait -r -e create,delete,modify,move,close_write "$ACTIVE_FONT_DIR" >/dev/null 2>&1
    fc-cache -f "$ACTIVE_FONT_DIR" >/dev/null 2>&1
  done
) &
WATCHER_PID=$!

fontypython

kill "$WATCHER_PID" 2>/dev/null || true

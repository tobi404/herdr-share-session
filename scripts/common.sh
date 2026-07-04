#!/usr/bin/env bash
# common.sh — shared config + tmux/ssh helpers. Sourced by the other scripts.
set -euo pipefail

# Resolve tmux: explicit override wins, then PATH, then Homebrew fallback.
TMUX_BIN="${TMUX_BIN:-$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)}"

# Optional isolated server socket (tests set this). Empty → tmux default server.
TMUX_SOCKET="${TMUX_SOCKET:-}"

# Load user config if herdr provided a config dir containing config.env.
if [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ] && [ -f "${HERDR_PLUGIN_CONFIG_DIR}/config.env" ]; then
  # shellcheck disable=SC1091
  . "${HERDR_PLUGIN_CONFIG_DIR}/config.env"
fi

SESSION="${SESSION_NAME:-mirror}"          # driver session (Mac 1 attaches here)
VIEW="${SESSION}-ro"                        # grouped read-only twin (Mac 2 viewer)
SHARE_HOST="${SHARE_HOST:-paysera-two}"     # join target (Mac 1 → Mac 2)
REMOTE_TMUX_BIN="${REMOTE_TMUX_BIN:-/opt/homebrew/bin/tmux}"  # tmux path on Mac 2
SSH_BIN="${SSH_BIN:-ssh}"                   # overridable for tests

# Run tmux, honoring the optional isolated socket.
tmux_cmd() {
  if [ -n "$TMUX_SOCKET" ]; then
    "$TMUX_BIN" -L "$TMUX_SOCKET" "$@"
  else
    "$TMUX_BIN" "$@"
  fi
}

# Exit early with a clear message if tmux is unavailable.
require_tmux() {
  if command -v "$TMUX_BIN" >/dev/null 2>&1 || [ -x "$TMUX_BIN" ]; then
    return 0
  fi
  echo "error: tmux not found at '$TMUX_BIN' (set TMUX_BIN or install tmux)" >&2
  exit 1
}

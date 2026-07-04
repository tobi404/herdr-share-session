#!/usr/bin/env bash
# start-share.sh — Mac 2: start + configure the detached shared session.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
require_tmux

if ! tmux_cmd has-session -t "$SESSION" 2>/dev/null; then
  tmux_cmd new-session -d -s "$SESSION"
fi

# Window size follows the active (driver) client so the read-only viewer never
# constrains it.
tmux_cmd set-option -g window-size latest

echo "Shared session '$SESSION' is running (detached)."
echo "Local read-only view: use this plugin's 'viewer' pane (attaches '$VIEW' read-only)."
echo "Drive it from the other Mac: click 'Join shared session' (host: $SHARE_HOST)."

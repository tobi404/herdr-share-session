#!/usr/bin/env bash
# start-share.sh — Mac 2: start + configure the detached shared session.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
require_tmux

if ! tmux_cmd has-session -t "$SESSION" 2>/dev/null; then
  tmux_cmd new-session -d -s "$SESSION"
fi

# Size the shared window to the largest attached client so the read-only viewer
# never shrinks the driver's screen (regardless of attach order or a viewer resize).
tmux_cmd set-option -g window-size largest

echo "Shared session '$SESSION' is running (detached)."
echo "Local read-only view: open this plugin's 'viewer' tab (attaches '$VIEW' read-only)."
echo "Drive it from the other Mac: open the 'Join shared session' tab (host: $SHARE_HOST)."

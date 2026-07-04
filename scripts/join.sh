#!/usr/bin/env bash
# join.sh — Mac 1: SSH to the sharing Mac and attach the shared session (drives).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

exec "$SSH_BIN" -t "$SHARE_HOST" "$REMOTE_TMUX_BIN" attach -t "$SESSION"

#!/usr/bin/env bash
# stop-share.sh — Mac 2: tear down the shared sessions.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
require_tmux

killed=0
if tmux_cmd has-session -t "$VIEW" 2>/dev/null; then
  tmux_cmd kill-session -t "$VIEW" 2>/dev/null || true
  killed=1
fi
if tmux_cmd has-session -t "$SESSION" 2>/dev/null; then
  tmux_cmd kill-session -t "$SESSION" 2>/dev/null || true
  killed=1
fi

if [ "$killed" -eq 1 ]; then
  echo "Stopped share ('$SESSION')."
else
  echo "No share running ('$SESSION')."
fi

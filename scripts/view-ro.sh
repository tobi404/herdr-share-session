#!/usr/bin/env bash
# view-ro.sh — Mac 2 pane: read-only view via a grouped twin session.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
require_tmux

# The driver session must exist first.
if ! tmux_cmd has-session -t "$SESSION" 2>/dev/null; then
  echo "error: shared session '$SESSION' is not running; click 'Start view-only share' first" >&2
  exit 1
fi

# Create the grouped read-only twin if needed. It shares '$SESSION' windows but
# sizes independently, so it never shrinks the driver's screen.
if ! tmux_cmd has-session -t "$VIEW" 2>/dev/null; then
  tmux_cmd new-session -d -s "$VIEW" -t "$SESSION"
fi

# Attach this screen read-only. Blocks until detached (in the herdr pane); in a
# headless test tmux exits non-zero here, after the twin above already exists.
tmux_cmd attach -r -t "$VIEW"

#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/lib.sh"

SOCK="herdr-share-test-$$"
export TMUX_SOCKET="$SOCK"
TMUX_BIN="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
cleanup() { "$TMUX_BIN" -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

# Without a driver session, view-ro errors out.
if bash "$DIR/scripts/view-ro.sh" >/dev/null 2>&1; then
  echo "FAIL: expected error without driver session"; FAILED=1
else
  echo "ok: errors without driver session"
fi

# Start the driver, then run view-ro headlessly. attach fails without a TTY, but
# the grouped twin must already be created before the attach line.
bash "$DIR/scripts/start-share.sh" >/dev/null
bash "$DIR/scripts/view-ro.sh" >/dev/null 2>&1 || true
if "$TMUX_BIN" -L "$SOCK" has-session -t mirror-ro 2>/dev/null; then
  echo "ok: grouped viewer session created"
else
  echo "FAIL: grouped viewer session not created"; FAILED=1
fi

finish

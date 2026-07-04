#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/lib.sh"

SOCK="herdr-share-test-$$"
export TMUX_SOCKET="$SOCK"
TMUX_BIN="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
cleanup() { "$TMUX_BIN" -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

out="$(bash "$DIR/scripts/start-share.sh")"
assert_contains "$out" "is running" "start prints status"

if "$TMUX_BIN" -L "$SOCK" has-session -t mirror 2>/dev/null; then
  echo "ok: session created"
else
  echo "FAIL: session not created"; FAILED=1
fi

ws="$("$TMUX_BIN" -L "$SOCK" show-options -g window-size 2>/dev/null)"
assert_contains "$ws" "largest" "window-size set to largest"

# Second run is idempotent: still exactly one 'mirror' session, exit 0.
bash "$DIR/scripts/start-share.sh" >/dev/null
count="$("$TMUX_BIN" -L "$SOCK" list-sessions 2>/dev/null | grep -c '^mirror:')"
assert_eq "1" "$count" "idempotent: single mirror session"

finish

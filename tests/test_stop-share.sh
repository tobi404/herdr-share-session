#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/lib.sh"

SOCK="herdr-share-test-$$"
export TMUX_SOCKET="$SOCK"
TMUX_BIN="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
cleanup() { "$TMUX_BIN" -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

# Nothing running → friendly no-op, exit 0.
out="$(bash "$DIR/scripts/stop-share.sh")"; rc=$?
assert_contains "$out" "No share running" "friendly no-op message"
assert_eq "0" "$rc" "no-op exits 0"

# Start driver + twin, then stop → both gone.
bash "$DIR/scripts/start-share.sh" >/dev/null
"$TMUX_BIN" -L "$SOCK" new-session -d -s mirror-ro -t mirror
out="$(bash "$DIR/scripts/stop-share.sh")"
assert_contains "$out" "Stopped share" "reports stopped"
if "$TMUX_BIN" -L "$SOCK" has-session -t mirror 2>/dev/null; then
  echo "FAIL: mirror still present"; FAILED=1
else
  echo "ok: mirror gone"
fi
if "$TMUX_BIN" -L "$SOCK" has-session -t mirror-ro 2>/dev/null; then
  echo "FAIL: mirror-ro still present"; FAILED=1
else
  echo "ok: mirror-ro gone"
fi

finish

#!/usr/bin/env bash
# Verifies config defaults and overrides resolved by common.sh.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/lib.sh"

out="$(bash -c '. "'"$DIR"'/scripts/common.sh"; echo "$SESSION|$VIEW|$SHARE_HOST|$REMOTE_TMUX_BIN"')"
assert_eq "mirror|mirror-ro|paysera-two|/opt/homebrew/bin/tmux" "$out" "common.sh defaults"

out="$(SESSION_NAME=demo bash -c '. "'"$DIR"'/scripts/common.sh"; echo "$SESSION|$VIEW"')"
assert_eq "demo|demo-ro" "$out" "SESSION_NAME flows into SESSION and VIEW"

out="$(SHARE_HOST=box2 bash -c '. "'"$DIR"'/scripts/common.sh"; echo "$SHARE_HOST"')"
assert_eq "box2" "$out" "SHARE_HOST override"

finish

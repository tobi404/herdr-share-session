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

# An empty TMUX_BIN coming from config.env must re-default to an auto-detected path.
cfg="$(mktemp -d)"
printf 'TMUX_BIN=\n' > "$cfg/config.env"
out="$(HERDR_PLUGIN_CONFIG_DIR="$cfg" bash -c '. "'"$DIR"'/scripts/common.sh"; echo "$TMUX_BIN"')"
[ -n "$out" ] && ne=yes || ne=no
assert_eq "yes" "$ne" "empty config TMUX_BIN re-defaults to non-empty"
rm -rf "$cfg"

# A real TMUX_BIN in config.env is honored.
cfg="$(mktemp -d)"
printf 'TMUX_BIN=/custom/tmux\n' > "$cfg/config.env"
out="$(HERDR_PLUGIN_CONFIG_DIR="$cfg" bash -c '. "'"$DIR"'/scripts/common.sh"; echo "$TMUX_BIN"')"
assert_eq "/custom/tmux" "$out" "config TMUX_BIN override honored"
rm -rf "$cfg"

finish

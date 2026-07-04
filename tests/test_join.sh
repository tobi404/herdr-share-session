#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/lib.sh"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# Fake ssh that records its argv instead of connecting.
cat > "$TMPD/fake-ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
chmod +x "$TMPD/fake-ssh"

out="$(SSH_BIN="$TMPD/fake-ssh" SHARE_HOST=paysera-two \
       REMOTE_TMUX_BIN=/opt/homebrew/bin/tmux SESSION_NAME=mirror \
       bash "$DIR/scripts/join.sh")"
expected="$(printf -- '-t\npaysera-two\n/opt/homebrew/bin/tmux\nattach\n-t\nmirror')"
assert_eq "$expected" "$out" "join builds correct ssh argv"

finish

#!/usr/bin/env bash
# Structural check of the manifest + that every referenced script exists.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/tests/lib.sh"

man="$DIR/herdr-plugin.toml"
if [ -f "$man" ]; then echo "ok: manifest exists"; else echo "FAIL: no manifest"; FAILED=1; fi

body="$(cat "$man" 2>/dev/null || echo "")"
assert_contains "$body" 'id = "share-session"'            "manifest id"
assert_contains "$body" 'min_herdr_version = "0.7.1"'     "min herdr version"
assert_contains "$body" 'command = ["bash", "scripts/start-share.sh"]' "start action wired"
assert_contains "$body" 'command = ["bash", "scripts/join.sh"]'        "join action wired"
assert_contains "$body" 'command = ["bash", "scripts/stop-share.sh"]'  "stop action wired"
assert_contains "$body" 'command = ["bash", "scripts/view-ro.sh"]'     "viewer pane wired"

# herdr 0.7.1 requires a `title` on every [[actions]] AND [[panes]] block — a
# missing pane title makes the whole manifest fail to load. Guard the count so a
# dropped title is caught here rather than only at `herdr plugin link` time.
titles="$(grep -c '^title = ' "$man")"
assert_eq "4" "$titles" "every action + pane declares a title (3 actions + 1 pane)"

# Declare platforms so herdr does not warn about unknown platform support.
assert_contains "$body" 'platforms = ["macos"]' "platforms declared"

for s in common start-share view-ro stop-share join; do
  if [ -f "$DIR/scripts/$s.sh" ]; then echo "ok: scripts/$s.sh present"; else echo "FAIL: scripts/$s.sh missing"; FAILED=1; fi
done

# Bonus: if this Python has tomllib (3.11+), assert the manifest parses.
if python3 -c 'import tomllib' 2>/dev/null; then
  if python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$man" 2>/dev/null; then
    echo "ok: manifest parses as TOML"
  else
    echo "FAIL: manifest is not valid TOML"; FAILED=1
  fi
else
  echo "skip: tomllib unavailable (py < 3.11), structural check only"
fi

finish

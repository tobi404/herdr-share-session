#!/usr/bin/env bash
# Runs every tests/test_*.sh and reports overall status.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$DIR"/test_*.sh; do
  echo "=== $t ==="
  bash "$t" || rc=1
done
if [ "$rc" -eq 0 ]; then echo "== ALL SUITES PASSED =="; else echo "== FAILURES =="; fi
exit "$rc"

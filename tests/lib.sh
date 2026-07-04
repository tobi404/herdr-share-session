# tests/lib.sh — minimal assertion helpers for the bash test suites.
FAILED=0
assert_eq() { # expected actual message
  if [ "$1" = "$2" ]; then echo "ok: $3"; else echo "FAIL: $3 (expected '$1', got '$2')"; FAILED=1; fi
}
assert_contains() { # haystack needle message
  case "$1" in *"$2"*) echo "ok: $3" ;; *) echo "FAIL: $3 (missing '$2' in '$1')"; FAILED=1 ;; esac
}
finish() {
  if [ "$FAILED" -eq 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; exit 1; fi
}

# share-session herdr plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a herdr plugin that lets Mac 2 one-click share a tmux session (view-only for itself) so Mac 1 can one-click join and drive it.

**Architecture:** herdr has no native sharing, so tmux is the engine and the plugin is a thin one-click wrapper. Mac 2 runs a detached `mirror` session and watches a grouped read-only twin `mirror-ro`; Mac 1 SSHes in and attaches `mirror` with full control. Plugin surface is three herdr actions (`start`, `join`, `stop`) plus one `viewer` pane, each shelling out to a small bash script. Shared config/helpers live in `scripts/common.sh`.

**Tech Stack:** bash, tmux (3.x), herdr 0.7.1 plugin manifest (TOML). Tests are plain bash exercising the scripts against an isolated tmux server socket (`tmux -L`).

## Global Constraints

- `min_herdr_version = "0.7.1"` in the manifest (installed version).
- tmux is invoked by **auto-detected full path** (`command -v tmux || /opt/homebrew/bin/tmux`); it is not on the non-interactive SSH `PATH`.
- Defaults: session `mirror`, read-only twin `mirror-ro`, join host `paysera-two`, remote tmux `/opt/homebrew/bin/tmux`. All overridable via `config.env` in `HERDR_PLUGIN_CONFIG_DIR`.
- Read-only is **cooperative** (`attach -r` per client), not enforced — do not claim otherwise in docs.
- Every script starts with `set -euo pipefail` and sources `scripts/common.sh`.
- Commit messages: plain, no AI/Claude attribution, no generated-by footer (user's global rule).

---

## Prerequisite (dev machine only)

tmux is not installed on this Mac. The tmux-backed test suites need it. Install it once (test/dev dependency only — the feature itself needs tmux only on Mac 2):

```bash
brew install tmux
tmux -V   # expect: tmux 3.x
```

If you prefer not to install tmux here, run Tasks 2–4's test suites on Mac 2 instead; Tasks 1, 5, 6 need no tmux.

---

## File structure

```
Bullet/
  herdr-plugin.toml         # Task 6 — plugin manifest (actions + pane)
  README.md                 # Task 6 — install + usage
  scripts/
    common.sh               # Task 1 — config resolution + tmux/ssh helpers
    start-share.sh          # Task 2 — Mac 2: create + configure `mirror`
    view-ro.sh              # Task 3 — Mac 2 pane: grouped read-only attach
    stop-share.sh           # Task 4 — Mac 2: kill twin then `mirror`
    join.sh                 # Task 5 — Mac 1: ssh + attach `mirror`
  tests/
    lib.sh                  # Task 1 — assertion helpers
    run.sh                  # Task 1 — run all test_*.sh
    test_common.sh          # Task 1
    test_start-share.sh     # Task 2
    test_view-ro.sh         # Task 3
    test_stop-share.sh      # Task 4
    test_join.sh            # Task 5
    test_manifest.sh        # Task 6
```

Each script resolves its own directory (`DIR="$(cd "$(dirname "$0")" && pwd)"`) and sources `common.sh`, so it works regardless of the caller's cwd.

---

### Task 1: Scaffold, shared helpers, and test harness

**Files:**
- Create: `scripts/common.sh`
- Create: `tests/lib.sh`
- Create: `tests/run.sh`
- Test: `tests/test_common.sh`

**Interfaces:**
- Produces (sourced by every script): variables `TMUX_BIN`, `TMUX_SOCKET`, `SESSION`, `VIEW`, `SHARE_HOST`, `REMOTE_TMUX_BIN`, `SSH_BIN`; functions `tmux_cmd()` (runs tmux honoring `TMUX_SOCKET`) and `require_tmux()` (exit 1 with message if tmux missing).
- Produces (for tests): `assert_eq expected actual msg`, `assert_contains haystack needle msg`, `finish` (exit 1 if any FAILED).

- [ ] **Step 0: Initialize the repo**

```bash
cd /Users/bekademuradze/Documents/AppDev/Bullet
git init
printf '%s\n' 'tests/.tmp/' > .gitignore
git add .gitignore docs
git commit -m "chore: init share-session plugin repo with spec + plan"
```

- [ ] **Step 1: Write the test harness helpers** (no test-of-tests; these support later steps)

Create `tests/lib.sh`:

```bash
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
```

Create `tests/run.sh`:

```bash
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
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_common.sh`:

```bash
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/test_common.sh`
Expected: FAIL — `scripts/common.sh` does not exist yet (source error / empty vars).

- [ ] **Step 4: Write `scripts/common.sh`**

```bash
#!/usr/bin/env bash
# common.sh — shared config + tmux/ssh helpers. Sourced by the other scripts.
set -euo pipefail

# Resolve tmux: explicit override wins, then PATH, then Homebrew fallback.
TMUX_BIN="${TMUX_BIN:-$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)}"

# Optional isolated server socket (tests set this). Empty → tmux default server.
TMUX_SOCKET="${TMUX_SOCKET:-}"

# Load user config if herdr provided a config dir containing config.env.
if [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ] && [ -f "${HERDR_PLUGIN_CONFIG_DIR}/config.env" ]; then
  # shellcheck disable=SC1091
  . "${HERDR_PLUGIN_CONFIG_DIR}/config.env"
fi

SESSION="${SESSION_NAME:-mirror}"          # driver session (Mac 1 attaches here)
VIEW="${SESSION}-ro"                        # grouped read-only twin (Mac 2 viewer)
SHARE_HOST="${SHARE_HOST:-paysera-two}"     # join target (Mac 1 → Mac 2)
REMOTE_TMUX_BIN="${REMOTE_TMUX_BIN:-/opt/homebrew/bin/tmux}"  # tmux path on Mac 2
SSH_BIN="${SSH_BIN:-ssh}"                   # overridable for tests

# Run tmux, honoring the optional isolated socket.
tmux_cmd() {
  if [ -n "$TMUX_SOCKET" ]; then
    "$TMUX_BIN" -L "$TMUX_SOCKET" "$@"
  else
    "$TMUX_BIN" "$@"
  fi
}

# Exit early with a clear message if tmux is unavailable.
require_tmux() {
  if command -v "$TMUX_BIN" >/dev/null 2>&1 || [ -x "$TMUX_BIN" ]; then
    return 0
  fi
  echo "error: tmux not found at '$TMUX_BIN' (set TMUX_BIN or install tmux)" >&2
  exit 1
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_common.sh`
Expected: three `ok:` lines then `ALL PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/common.sh tests/lib.sh tests/run.sh tests/test_common.sh
git commit -m "feat: add shared config helpers and bash test harness"
```

---

### Task 2: `start-share.sh` — create + configure the shared session

**Files:**
- Create: `scripts/start-share.sh`
- Test: `tests/test_start-share.sh`

**Interfaces:**
- Consumes: `common.sh` (`tmux_cmd`, `require_tmux`, `SESSION`, `VIEW`, `SHARE_HOST`, `TMUX_BIN`).
- Produces: a detached tmux session named `$SESSION` with global option `window-size latest`; idempotent on repeat runs. Prints a status line containing `is running`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_start-share.sh`:

```bash
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
assert_contains "$ws" "latest" "window-size set to latest"

# Second run is idempotent: still exactly one 'mirror' session, exit 0.
bash "$DIR/scripts/start-share.sh" >/dev/null
count="$("$TMUX_BIN" -L "$SOCK" list-sessions 2>/dev/null | grep -c '^mirror:')"
assert_eq "1" "$count" "idempotent: single mirror session"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_start-share.sh`
Expected: FAIL — `scripts/start-share.sh` does not exist.

- [ ] **Step 3: Write `scripts/start-share.sh`**

```bash
#!/usr/bin/env bash
# start-share.sh — Mac 2: start + configure the detached shared session.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
require_tmux

if ! tmux_cmd has-session -t "$SESSION" 2>/dev/null; then
  tmux_cmd new-session -d -s "$SESSION"
fi

# Window size follows the active (driver) client so the read-only viewer never
# constrains it.
tmux_cmd set-option -g window-size latest

echo "Shared session '$SESSION' is running (detached)."
echo "Local read-only view: use this plugin's 'viewer' pane (attaches '$VIEW' read-only)."
echo "Drive it from the other Mac: click 'Join shared session' (host: $SHARE_HOST)."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_start-share.sh`
Expected: `ok:` lines then `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/start-share.sh tests/test_start-share.sh
git commit -m "feat: add start-share script for the sharing Mac"
```

---

### Task 3: `view-ro.sh` — grouped read-only viewer

**Files:**
- Create: `scripts/view-ro.sh`
- Test: `tests/test_view-ro.sh`

**Interfaces:**
- Consumes: `common.sh` (`tmux_cmd`, `require_tmux`, `SESSION`, `VIEW`).
- Produces: creates `$VIEW` grouped to `$SESSION` (via `new-session -t`) if absent, then `attach -r` to it. Errors (exit 1) if `$SESSION` is not running.

- [ ] **Step 1: Write the failing test**

Create `tests/test_view-ro.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_view-ro.sh`
Expected: FAIL — `scripts/view-ro.sh` does not exist.

- [ ] **Step 3: Write `scripts/view-ro.sh`**

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_view-ro.sh`
Expected: `ok: errors without driver session`, `ok: grouped viewer session created`, `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/view-ro.sh tests/test_view-ro.sh
git commit -m "feat: add grouped read-only viewer script"
```

---

### Task 4: `stop-share.sh` — tear down

**Files:**
- Create: `scripts/stop-share.sh`
- Test: `tests/test_stop-share.sh`

**Interfaces:**
- Consumes: `common.sh` (`tmux_cmd`, `require_tmux`, `SESSION`, `VIEW`).
- Produces: kills `$VIEW` then `$SESSION` if present; prints `Stopped share` when it killed something, `No share running` otherwise; always exits 0 when tmux is available.

- [ ] **Step 1: Write the failing test**

Create `tests/test_stop-share.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_stop-share.sh`
Expected: FAIL — `scripts/stop-share.sh` does not exist.

- [ ] **Step 3: Write `scripts/stop-share.sh`**

```bash
#!/usr/bin/env bash
# stop-share.sh — Mac 2: tear down the shared sessions.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
require_tmux

killed=0
if tmux_cmd has-session -t "$VIEW" 2>/dev/null; then
  tmux_cmd kill-session -t "$VIEW" 2>/dev/null || true
  killed=1
fi
if tmux_cmd has-session -t "$SESSION" 2>/dev/null; then
  tmux_cmd kill-session -t "$SESSION" 2>/dev/null || true
  killed=1
fi

if [ "$killed" -eq 1 ]; then
  echo "Stopped share ('$SESSION')."
else
  echo "No share running ('$SESSION')."
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_stop-share.sh`
Expected: `ok:` lines then `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/stop-share.sh tests/test_stop-share.sh
git commit -m "feat: add stop-share teardown script"
```

---

### Task 5: `join.sh` — drive from Mac 1

**Files:**
- Create: `scripts/join.sh`
- Test: `tests/test_join.sh`

**Interfaces:**
- Consumes: `common.sh` (`SSH_BIN`, `SHARE_HOST`, `REMOTE_TMUX_BIN`, `SESSION`).
- Produces: execs `"$SSH_BIN" -t "$SHARE_HOST" "$REMOTE_TMUX_BIN" attach -t "$SESSION"`. Does not call `require_tmux` (tmux runs on the remote).

- [ ] **Step 1: Write the failing test**

Create `tests/test_join.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_join.sh`
Expected: FAIL — `scripts/join.sh` does not exist.

- [ ] **Step 3: Write `scripts/join.sh`**

```bash
#!/usr/bin/env bash
# join.sh — Mac 1: SSH to the sharing Mac and attach the shared session (drives).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

exec "$SSH_BIN" -t "$SHARE_HOST" "$REMOTE_TMUX_BIN" attach -t "$SESSION"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_join.sh`
Expected: `ok: join builds correct ssh argv`, `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/join.sh tests/test_join.sh
git commit -m "feat: add join script for the driver Mac"
```

---

### Task 6: Plugin manifest + README

**Files:**
- Create: `herdr-plugin.toml`
- Create: `README.md`
- Test: `tests/test_manifest.sh`

**Interfaces:**
- Consumes: the five `scripts/*.sh` from Tasks 1–5.
- Produces: a herdr manifest wiring actions `start`/`join`/`stop` and pane `viewer` to their scripts.

- [ ] **Step 1: Write the failing test**

Create `tests/test_manifest.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifest.sh`
Expected: FAIL — `herdr-plugin.toml` does not exist.

- [ ] **Step 3: Write `herdr-plugin.toml`**

```toml
id = "share-session"
name = "Share Session (view-only)"
version = "0.1.0"
min_herdr_version = "0.7.1"
platforms = ["macos"]

[[actions]]
id = "start"
title = "Start view-only share"
contexts = ["workspace"]
command = ["bash", "scripts/start-share.sh"]

[[actions]]
id = "join"
title = "Join shared session"
contexts = ["workspace"]
command = ["bash", "scripts/join.sh"]

[[actions]]
id = "stop"
title = "Stop share"
contexts = ["workspace"]
command = ["bash", "scripts/stop-share.sh"]

[[panes]]
id = "viewer"
title = "Shared session (read-only)"
placement = "overlay"
command = ["bash", "scripts/view-ro.sh"]
```

- [ ] **Step 4: Write `README.md`**

````markdown
# share-session (herdr plugin)

One-click view-only terminal sharing between two Macs, built on tmux.

- **Mac 2** (sharing) clicks **Start view-only share**, then opens the **viewer**
  pane to watch read-only.
- **Mac 1** (driver) clicks **Join shared session** to SSH in and drive.

herdr has no native sharing; this plugin wraps tmux. Read-only is cooperative
(`tmux attach -r`), not enforced. You work *inside* the shared session — a shell
already running outside tmux can't be adopted.

## Requirements

- herdr ≥ 0.7.1 on both Macs.
- tmux on the **sharing** Mac (Mac 2). The driver Mac does not need tmux.
- SSH key access from Mac 1 to Mac 2 (host alias configured in `~/.ssh/config`).

## Install

On each Mac:

```bash
herdr plugin install <owner>/<repo>      # from GitHub
# or, for local development:
herdr plugin link /path/to/this/repo
```

## Configure

Optional `config.env` in the plugin config dir (`herdr plugin config-dir share-session`):

```sh
SESSION_NAME=mirror                    # base session name
TMUX_BIN=                              # empty → auto-detect
SHARE_HOST=paysera-two                 # join target (set on the DRIVER Mac)
REMOTE_TMUX_BIN=/opt/homebrew/bin/tmux # tmux path on the sharing Mac
```

## Use

- Mac 2: **Start view-only share** → open **viewer** pane.
- Mac 1: **Join shared session**.
- Mac 2: **Stop share** when done.

## Test

```bash
brew install tmux   # dev-only dependency for the tmux-backed suites
bash tests/run.sh
```
````

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_manifest.sh`
Expected: `ok:` lines then `ALL PASS`.

- [ ] **Step 6: Run the full suite**

Run: `bash tests/run.sh`
Expected: every suite prints `ALL PASS`, final line `== ALL SUITES PASSED ==`.

- [ ] **Step 7: Commit**

```bash
git add herdr-plugin.toml README.md tests/test_manifest.sh
git commit -m "feat: add herdr plugin manifest and README"
```

---

## Manual verification (real two-Mac test)

After the suite passes, verify end-to-end (cannot be unit-tested — needs two machines and TTYs):

1. Deploy to both Macs (`herdr plugin link` or `install`). Set `SHARE_HOST` in Mac 1's config to the Mac 2 SSH alias.
2. Mac 2: click **Start view-only share**, then open the **viewer** pane — confirm a read-only shell appears (typing does nothing).
3. Mac 1: click **Join shared session** — confirm you attach and can type.
4. Confirm Mac 1's typing appears live in Mac 2's viewer, and resizing Mac 2's window does **not** shrink Mac 1's screen (grouped-twin sizing).
5. Mac 2: click **Stop share** — both sessions end; the viewer pane drops to a normal shell.

---

## Self-review

**Spec coverage:** purpose/flow → Tasks 2/3/5 + manifest; herdr-has-no-sharing constraint → wrapper design; tmux full-path gotcha → `common.sh` auto-detect + `REMOTE_TMUX_BIN`; control model / cooperative read-only → `view-ro.sh` `-r` + README caveat; grouped-session sizing → `view-ro.sh` `new-session -t` + `start-share.sh` `window-size latest`; components list → file structure; config → `common.sh` + README; error handling → `require_tmux`, idempotent start, friendly stop, unmasked ssh error; testing → Tasks 1–6 suites + manual section; deployment → README; out-of-scope items → none implemented. No gaps.

**Placeholder scan:** `<owner>/<repo>` and `/path/to/this/repo` in the README are genuine user-supplied values, not plan placeholders. No TBD/TODO/"handle edge cases" present.

**Type/name consistency:** `tmux_cmd`, `require_tmux`, `SESSION`, `VIEW`, `SHARE_HOST`, `REMOTE_TMUX_BIN`, `SSH_BIN` are defined in `common.sh` (Task 1) and used with identical names in Tasks 2–5. Session names `mirror`/`mirror-ro` consistent across scripts, tests, and manifest. Manifest `command` strings match the test's `assert_contains` exactly.

# Design: `share-session` herdr plugin

**Date:** 2026-07-04
**Status:** Approved (pending spec review)

## Purpose

A herdr plugin that turns a Mac into a view-only session host in one click, so
another Mac can attach and drive the same terminal session. Concretely:

- **Mac 2** (the sharing Mac) clicks **Start view-only share** → a shared tmux
  session starts and Mac 2 watches it read-only.
- **Mac 1** (the driver) clicks **Join shared session** → SSHes to Mac 2 and
  attaches with full control.

Both ends are one-click. The same plugin is installed on both Macs; which button
you press depends on the role you're playing at that moment.

## Background / constraint

herdr (v0.7.1) has **no native session-sharing, mirroring, or read-only
capability** — its plugin surface is actions, event hooks, panes, and link
handlers. So the mirroring engine is **tmux**; the plugin is a one-click wrapper
around tmux commands, not a new herdr capability.

Known environment gotcha (from prior setup): tmux is installed via Homebrew at
`/opt/homebrew/bin/tmux` and is **not** on the non-interactive SSH `PATH`, so the
full binary path must be used (or auto-detected).

## Control model

- Mac 2 shares its session and its **local** view is read-only (`tmux attach -r`).
- Mac 1 attaches **without** `-r`, so it drives.
- "Read-only" is **cooperative, not enforced**: `-r` is a per-attach flag, so a
  user physically at Mac 2 could re-attach without it and grab the keyboard. This
  prevents *accidental* double-typing, not a determined user. tmux has no
  force-read-only-for-all-clients switch.
- You work **inside** the shared tmux session. A shell already running outside
  tmux can't be retroactively adopted — start the share first, then do the work
  in it (from either Mac) and it mirrors.

## Sizing: grouped sessions

Two clients of different window sizes would normally force the shared window down
to the smaller one, squishing the driver. To avoid this, the read-only viewer on
Mac 2 attaches to a **grouped twin session** rather than the driver's session
directly:

- `mirror`    — the driver session (Mac 1 attaches here).
- `mirror-ro` — a session created grouped to `mirror` (`tmux new-session -t mirror`).
  It shares `mirror`'s windows but sizes independently, so Mac 2's viewer never
  constrains Mac 1's screen. `window-size latest` is set on the driver session.

Exact option tuning (`window-size`, `aggressive-resize`) is finalized during
implementation/testing; the intent is fixed: **the read-only viewer must not
constrain the driver's size.**

## Components

Developed in this repo (`Bullet/`), then deployed to both Macs.

```
Bullet/
  herdr-plugin.toml
  scripts/
    start-share.sh    # Mac 2: create + configure detached `mirror` (idempotent)
    view-ro.sh        # Mac 2: read-only attach to grouped `mirror-ro` (herdr pane)
    join.sh           # Mac 1: ssh to host + attach to `mirror` (drives)
    stop-share.sh     # Mac 2: kill `mirror-ro` then `mirror`
    common.sh         # shared: resolve TMUX_BIN + source config
  README.md
```

### `herdr-plugin.toml`

```toml
id = "share-session"
name = "Share Session (view-only)"
version = "0.1.0"
min_herdr_version = "0.7.1"

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
placement = "overlay"
command = ["bash", "scripts/view-ro.sh"]
```

### Script behavior

- **`common.sh`** — sourced by the others. Resolves
  `TMUX_BIN="${TMUX_BIN:-$(command -v tmux || echo /opt/homebrew/bin/tmux)}"` and
  sources the optional config file if present. Defines `SESSION` / `VIEW` /
  `SHARE_HOST` defaults.
- **`start-share.sh`** (Mac 2) — if `mirror` is absent, `new-session -d -s mirror`;
  set `window-size latest`; print the local read-only view command and the
  Mac-1 join command. Idempotent (safe to click twice).
- **`view-ro.sh`** (Mac 2 pane) — create `mirror-ro` grouped to `mirror` if
  absent (`new-session -d -s mirror-ro -t mirror`), then
  `exec tmux attach -r -t mirror-ro`.
- **`join.sh`** (Mac 1) — `exec ssh -t "$SHARE_HOST" "$REMOTE_TMUX_BIN" attach -t mirror`.
- **`stop-share.sh`** (Mac 2) — kill `mirror-ro` (ignore if absent) then
  `mirror`; friendly message if nothing was running.

### Config

Optional `config.env` in `HERDR_PLUGIN_CONFIG_DIR`, sourced by `common.sh`.
Everything has a working default so zero-config still runs:

```sh
SESSION_NAME=mirror              # base session name
TMUX_BIN=                        # empty → auto-detect
SHARE_HOST=paysera-two           # join.sh SSH target
REMOTE_TMUX_BIN=/opt/homebrew/bin/tmux   # tmux path on the sharing Mac
```

## Error handling

- **tmux missing** → scripts print a clear "tmux not found at <path>" message and
  exit non-zero.
- **Session already exists** → `start-share.sh` reuses it (idempotent).
- **Stop when nothing running** → friendly message, exit 0.
- **`join.sh` with unreachable host** → SSH's own error surfaces; script does not
  mask it.
- Scripts use `set -euo pipefail`.

## Testing

1. **Local (single Mac, available now):** run `start-share.sh`; in terminal A
   `attach -r` (read-only), terminal B `attach` (read-write). Confirm B's typing
   appears in A, A cannot type, and A resizing does not shrink B.
2. **Cross-Mac:** deploy to `paysera-two`, click Start there, click Join from
   this Mac, confirm drive-from-Mac-1 / watch-on-Mac-2 works and survives a
   viewer resize.
3. **Idempotency:** click Start twice → no error, same session.
4. **Stop:** click Stop → both sessions gone, viewer pane drops to a shell.

## Deployment

- Develop and version the plugin in this repo.
- On each Mac: `herdr plugin install <owner/repo>` (from GitHub) or
  `herdr plugin link <path>` for local development.
- Mac 2 uses Start/Stop + viewer pane; Mac 1 uses Join. `SHARE_HOST` in Mac 1's
  config points at Mac 2.

## Out of scope (YAGNI)

- Enforced/locked read-only (tmux can't do it; not worth a wrapper hack).
- Multi-viewer / >2 machines (works incidentally via extra SSH attaches, but not
  a designed feature).
- Auth/transport beyond existing SSH key setup.
- Adopting pre-existing non-tmux shells into the share.
```


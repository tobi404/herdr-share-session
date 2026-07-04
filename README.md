# share-session (herdr plugin)

One-click view-only terminal sharing between two Macs, built on tmux.

- **Mac 2** (sharing) clicks **Start view-only share**, then opens the **viewer**
  tab to watch read-only.
- **Mac 1** (driver) opens the **Join shared session** tab to SSH in and drive.

`start` and `stop` are actions (fire-and-forget). `viewer` and `join` are
**panes** (they open in their own tab): both run interactively — attaching a
tmux session over a PTY — so they need a real terminal, which a background
action does not have.

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
herdr plugin install tobi404/herdr-share-session   # from GitHub (private repo:
                                                   # the Mac must be authed to GitHub)
# or clone + link locally:
git clone git@github.com:tobi404/herdr-share-session.git
herdr plugin link ./herdr-share-session
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

- Mac 2: **Start view-only share** → open the **viewer** tab.
- Mac 1: open the **Join shared session** tab.
- Mac 2: **Stop share** when done.

## Hotkeys (optional)

Keybindings are not part of the plugin — they live in each Mac's
`~/.config/herdr/config.toml` and reference the plugin's actions/panes. Add this
block (prefix defaults to `ctrl+b`; run `herdr server reload-config` after):

```toml
[[keys.command]]
key = "prefix+shift+s"
type = "plugin_action"
command = "share-session.start"
description = "share: start view-only session"

[[keys.command]]
key = "prefix+shift+v"
type = "shell"
command = "bash -lc 'herdr plugin action invoke start --plugin share-session && herdr plugin pane open --plugin share-session --entrypoint viewer --placement tab'"
description = "share: start (if needed) + open viewer in new tab"

[[keys.command]]
key = "prefix+shift+e"
type = "plugin_action"
command = "share-session.stop"
description = "share: stop / tear down"

[[keys.command]]
key = "prefix+shift+j"
type = "shell"
command = "herdr plugin pane open --plugin share-session --entrypoint join --placement tab"
description = "share: join (driver)"
```

## Test

```bash
brew install tmux   # dev-only dependency for the tmux-backed suites
bash tests/run.sh
```

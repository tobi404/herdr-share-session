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

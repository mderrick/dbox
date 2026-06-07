# dbox

```
     _ _
  __| | |__   _____  __
 / _` | '_ \ / _ \ \/ /
| (_| | |_) | (_) >  <
 \__,_|_.__/ \___/_/\_\
```

**The problem:** you want to develop exactly as you normally would — full VS Code,
your shell, your tools — but be able to shut your laptop without killing your
Claude Code session.

**The solution:** dbox is a small dev container that runs on a remote box you
control, joined to your [Tailscale](https://tailscale.com) tailnet. It *feels*
local (SSH and VS Code Remote-SSH in over the tailnet) but it *persists*. Claude
runs inside it under tmux with [`--remote-control`](https://code.claude.com/docs/en/remote-control) —
a **stock Claude Code feature**, not something dbox invented — so a session
survives SSH drops and laptop sleep, and the same session is drivable from any
device, including the Claude mobile app.

Clone this repo and make it yours.

## Architecture

```
   your laptop
     │  ssh dev@dbox  ·  VS Code Remote-SSH
     ▼
  ┄┄┄┄┄┄┄┄┄┄ Tailscale tailnet ┄┄┄┄┄┄┄┄┄┄
     │
  ┌──▼──────────────────────────────────────────┐
  │ host: VPS / Mac mini  (needs Docker)        │
  │                                             │
  │ docker compose                              │
  │  ┌───────────┐      ┌────────────────┐      │
  │  │ tailscale │─────▶│ dev container  │      │
  │  │  sidecar  │      │                │      │
  │  └───────────┘      └────────────────┘      │
  └─────────────────────────────────────────────┘
```

The **Tailscale sidecar** gives the container its tailnet identity (`dbox`), so
it's reachable from anywhere on your tailnet. All persistent state lives in
`./data/` on the host using Docker bind mounts, so auth, repos, and the host key survive
rebuilds.

## Install

### On the host (the box)

This is the VPS / Mac mini that runs Docker. Bring up the stack:

```bash
git clone https://github.com/mderrick/dbox
cd dbox
cp .env.example .env
```

Fill in `.env` — `TS_AUTHKEY` (your [Tailscale auth key](https://login.tailscale.com/admin/settings/keys))
and `SSH_PUBKEY` (your laptop's SSH **public** key) are required; `GIT_USER_NAME` /
`GIT_USER_EMAIL` and `DBOX_HOSTNAME` (the tailnet name, defaults to `dbox`) are
optional. Then:

```bash
docker compose up -d --build   # the container joins your tailnet as "dbox"
```

### On your laptop (the client)

Authenticate your CLI tools inside the remote box (once):

```bash
ssh dev@dbox 
gh auth login   # a fine-grained token is advised
claude          # opens a URL — auth in your laptop browser
exit
```

Symlink the `dbox` helper onto your PATH so you don't have to type the raw
`ssh` / `code` incantations by hand:

```bash
ln -sf "$PWD/bin/dbox" /usr/local/bin/dbox
```

For `dbox code` you also need the [`code` CLI](https://code.visualstudio.com/docs/configure/command-line)
and the Remote-SSH extension in VS Code. The box defaults to the tailnet name
`dbox`; point the laptop elsewhere with `DBOX_HOST=<name>`.

## Quick use

Clone a repo onto the box and open a Claude session in it:

```bash
dbox                                              # shell into ~/workspace on the box
git clone https://github.com/octocat/Hello-World  # ...then clone, inside the box
dbox-terminal Hello-World                          # attach a tmux: shell + claude --remote-control
```

Or in one line from the laptop:

```bash
ssh dev@dbox git clone https://github.com/octocat/Hello-World ~/workspace/Hello-World
dbox terminal Hello-World
```

Or just ask Claude — the box ships with a `dbox` skill that does the clone +
session for you. You don't even need to start a session first: the box boots a
default home-base session (tmux `home-dev-workspace`, shown as **workspace** in
the Claude app), so just open that and ask:

```text
Clone https://github.com/octocat/Hello-World into the box and start a session for it.
```

The skill clones into `~/workspace/Hello-World`, spins up the per-project tmux
session (shell + `claude --remote-control`), and hands you back the attach
instructions — all from the always-on `workspace` session, including from the
mobile app.

Detach from the tmux with [`Ctrl-b` then `d`](https://research.it.iastate.edu/guides/pronto/interactive_computing/tmux/#detach-from-a-session) — this keeps Claude running, so you can close your laptop. Re-attach later from any
device on the tailnet by running the same commands, or pick the session up by name
from the Claude mobile app.

> The session survives SSH drops and your laptop sleeping. It does **not** survive
> a container restart (`docker compose down`, host reboot) — that kills tmux and
> the Claude process. Your files and logins persist; they're mounted on the host.

## Commands

Each laptop `dbox` command mostly just SSHes in and runs its in-box twin, so you
can drive dbox from either side. Prefer raw `ssh` / `tmux` / `code`? Everything
below is a thin wrapper — use the tools directly if you like.

| What it does                              | From your laptop          | Inside the box           |
| ----------------------------------------- | ------------------------- | ------------------------ |
| Open a shell in `~/workspace`             | `dbox`                    | *(you're already here)*  |
| Start / attach a Claude session for a dir | `dbox terminal <path>`    | `dbox-terminal <path>`   |
| Open a dir in VS Code (Remote-SSH)        | `dbox code <path>`        | —                        |
| List running tmux sessions                | `dbox ls`                 | `tmux ls`                |
| Rebuild + restart the container           | `dbox restart`            | `dbox-restart`           |
| Show help                                 | `dbox help`               | —                        |

`terminal` and `code` take a path, resolved relative to `~/workspace` (a leading
`/` or `~` is taken literally). A `dbox-terminal` session is starts tmux window 0 `shell`
(fish) + window 1 `claude`; reopening the same directory re-attaches the live
session, and `--continue` resumes its most recent conversation even after a
container restart.

`dbox restart` / `dbox-restart` is a small helper to pull latest and restart docker image on the remote host.

All Claude session on the box use [Remote Control](https://code.claude.com/docs/en/remote-control) which is a **stock
Claude Code feature**: a local session started with `claude --remote-control`
keeps running on the machine but dbox launches every session's claude window with
it automatically, labelled with the repo name, so your sessions show up under recognisable
names in the app's session list. This is the whole point of running in the box: remote-first by default.

## VS Code setup

`dbox code <path>` opens the remote folder over [Remote-SSH](https://code.visualstudio.com/docs/remote/ssh) —
the integrated terminal then runs *inside* the box. Add this terminal profile to
your **Remote [SSH] settings** (`Cmd-Shift-P` → "Preferences: Open Remote Settings
(JSON)") so new terminals open straight into a per-directory tmux session (shell +
`claude --remote-control` windows), auto-attaching to an existing one:

```json
"terminal.integrated.profiles.linux": {
  "dbox": {
    "path": "/bin/sh",
    "args": ["-lc", "exec dbox-terminal \"$PWD\""],
    "icon": "sparkle"
  }
},
"terminal.integrated.defaultProfile.linux": "dbox"
```

A dev server you start from a VS Code integrated terminal [auto-forwards](https://code.visualstudio.com/docs/remote/ssh#_forwarding-a-port) to your laptop's `localhost`; from a plain SSH / tmux terminal, forward it
yourself with `ssh -L 3000:localhost:3000 dev@dbox`.

## Where state lives

Everything persistent is under `./data/` on the host (git-ignored), one folder to
back up or wipe:

| `./data/…`      | mount                 | holds                                                |
| --------------- | --------------------- | ---------------------------------------------------- |
| `workspace`     | `~/workspace`         | your repos                                           |
| `claude`        | `~/.claude`           | Claude creds/settings/history                        |
| `gh`            | `~/.config/gh`        | GitHub OAuth                                         |
| `fish`          | `~/.local/share/fish` | shell history                                        |
| `vscode-server` | `~/.vscode-server`    | VS Code server + Remote settings (terminal profiles) |
| `agents`        | `~/.agents`           | installed skill bodies (`~/.claude/skills` symlinks here) |
| `sshkeys`       | `/etc/ssh/keys`       | SSH host keys                                        |
| `tailscale`     | `/var/lib/tailscale`  | tailnet identity                                     |
| `control`       | `~/.dbox-control`     | restart-request channel (`restarter` sidecar)        |


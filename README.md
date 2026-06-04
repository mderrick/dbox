# dbox

```
     _ _
  __| | |__   _____  __
 / _` | '_ \ / _ \ \/ /
| (_| | |_) | (_) >  <
 \__,_|_.__/ \___/_/\_\
```

An opinionated dev container that feels local but runs remote so you can persist your Claude
Code CLI sessions after you close the lid. SSH manually and/or VS Code in over Tailscale with tmux, fish, git,
gh, and Claude Code baked in. Access your claude CLI session from any device and the Claude mobile app.

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

- **Tailscale sidecar** gives the container its tailnet identity (`dbox`), so it's
  reachable from anywhere on your tailnet.
- **Dev container state in `./data/`** (bind mounts) → auth, repos, and host key survive
  rebuilds. tmux protects sessions across SSH drops (not container restarts).

## Quick install

On your host VPS/Mac Mini start up the dev container:

```bash
git clone https://github.com/mderrick/dbox
cd dbox
cp .env.example .env # Update .env with your credentials
docker compose up -d --build # The container joins your tailnet as "dbox".
```

On any device on the same tailnet you must authenticate your CLI tools on the dev container:

```bash
ssh dev@dbox
gh auth login # A fine-grained token is advised
claude        # Opens a URL — auth in your laptop browser
```

## Usage

```bash
# Clone a repo onto the dev container
ssh -t dev@dbox 'git clone https://github.com/octocat/Hello-World.git ~/workspace/Hello-World'

# Start (or re-attach) a REMOTE Claude session in a tmux named "claude-hello-world"
ssh -t dev@dbox 'tmux new -As claude-hello-world -c ~/workspace/Hello-World claude --remote-control'
```

Detach with the [`Ctrl-b` then `d`](https://research.it.iastate.edu/guides/pronto/interactive_computing/tmux/#detach-from-a-session) shortcut — this keeps Claude running, so you can close your laptop. Re-attach later by
running the same command again, from any device on the tailnet or from the Claude mobile app.

> The session survives SSH drops and your laptop sleeping. It does **not** survive
> a container restart (`docker compose down`, host reboot) — that kills tmux and
> the Claude process (so don't CTRL+C this tmux session either - just detach).
> Your files and logins persist (they're mounted on the host);

## VSCode Integration

You can also open the remote in VS Code, if you have the [`code` CLI](https://code.visualstudio.com/docs/configure/command-line) installed. VS Code has some nice feature built in to it's remote SSH development work flow. This is the best way to use this Docker image.

```bash
code --remote ssh-remote+dev@dbox /home/dev/workspace/Hello-World
```

The VS Code integrated terminal runs _inside_ dbox, so it can launch Claude directly inside it — You can create a terminal profile for VSCode by adding to the **Remote [SSH] settings** (`Cmd-Shift-P` → "Preferences: Open Remote Settings (JSON)"):

```json
"terminal.integrated.profiles.linux": {
  "dbox": {
    "path": "/bin/sh",
    "args": ["-lc", "exec dbox-session \"$PWD\""],
    "icon": "sparkle"
  }
},
"terminal.integrated.defaultProfile.linux": "dbox"
```

New terminals will now open directly into a per-project tmux session (shell + claude windows), auto-attaching if one already exists for that directory.

### Reaching a dev server

Your code's server binds _inside_ the container, so it isn't visible on your laptop by default however starting the server from a **VS Code integrated terminal** [auto-forwards it](https://code.visualstudio.com/docs/remote/ssh#_forwarding-a-port)
back to your laptop's `localhost`. Run it in any other terminal (tmux, plain SSH) and you'll need to forward the port yourself with `ssh -L 3000:localhost:3000 dev@dbox`.

## `dbox` CLI (optional helper)

The commands above are all you need. If you'd rather not type the `ssh`/`tmux`/`code`
incantations by hand, `bin/dbox` is a small bash wrapper that stands in for them —
nothing more. Symlink it onto your **laptop's** PATH:

```bash
ln -sf "$PWD/bin/dbox" /usr/local/bin/dbox
```

Then, each `dbox` command maps to a raw equivalent from above:

```bash
dbox                       # ssh -t dev@dbox  (interactive shell in ~/workspace)
dbox exec git clone …      # ssh -t dev@dbox 'git clone …'
dbox terminal Hello-World  # ssh -t dev@dbox dbox-session …   (tmux: shell + claude windows)
dbox code Hello-World      # code --remote ssh-remote+dev@dbox /home/dev/workspace/Hello-World
dbox ls                    # ssh dev@dbox tmux ls   (what's running, to reattach)
dbox restart               # ssh dev@dbox dbox-restart  (rebuild + recreate the stack)
dbox help                  # full usage
```

Paths are relative to `~/workspace` (a leading `/` or `~` is taken literally; no path
means `~/workspace`). The box defaults to the tailnet name `dbox` — point it elsewhere
with `DBOX_HOST=<name>`. `dbox code` additionally needs the [`code` CLI](https://code.visualstudio.com/docs/configure/command-line)
and the Remote-SSH extension on your laptop.

## Rebuilding / restarting from inside

The dev container can't reach the host's Docker daemon, so it can't restart
itself directly. A small **`restarter` sidecar** does it on the box's behalf —
it ships in `docker compose`, so there's nothing extra to install on the host:

```
  inside box:  dbox-restart            ─┐  writes ./data/control/restart-request
  laptop:      dbox restart            ─┘  (just ssh's the box to run dbox-restart)
                                          │
  restarter sidecar (config/dbox-watch) ◀─┘  git pull --ff-only
   (watches the control dir, holds the      docker compose up -d --build dev
    Docker socket — see docker-compose.yml)
```

`docker compose up -d` already starts the `restarter` service alongside
`tailscale` and `dev`, so once the stack is up, `dbox restart` (laptop) or
`dbox-restart` (inside the box) triggers a rebuild. Things to know:

- **The socket lives only in the sidecar.** `restarter` mounts
  `/var/run/docker.sock` (effectively root-on-host) — but `dev`, where Claude
  runs, never does. Don't run this on an untrusted host.
- **It rebuilds only `dev`** (`--build dev`), so the sidecar never recreates
  itself mid-command; `tailscale` keeps the shared netns and `dev` re-attaches.
- **It `git pull --ff-only`s the host clone first**, so push your changes before
  triggering — the copy you edit under `~/workspace` is a *different* clone from
  the one compose builds.
- **The triggering session drops** (tmux + Claude included) when `dev` is
  recreated. That's expected; reconnect once it's back up.
- Needs `$PWD` set when you run `docker compose up` (the normal case from a
  shell) so the sidecar can mount the clone at its own host path.

## Where state lives

Everything persistent is under `./data/` (git-ignored), one folder to back up or wipe:

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
| `control`       | `~/.dbox-control`     | restart-request channel (see Rebuilding / restarting) |

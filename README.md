# dbox

```
     _ _
  __| | |__   _____  __
 / _` | '_ \ / _ \ \/ /
| (_| | |_) | (_) >  <
 \__,_|_.__/ \___/_/\_\
```

An opinionated dev container that feels local but runs remote so you can persist your Claude
Code CLI sessions after you close the lid. SSH or VS Code in over Tailscale with tmux, fish, git,
gh, and Claude Code baked in. Clone it and make it yours.

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
  rebuilds. tmux protects sessions across SSH drops, not container restarts.

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

# Start (or re-attach) a Claude session in a tmux named "claude-hello-world"
ssh -t dev@dbox 'tmux new -As claude-hello-world -c ~/workspace/Hello-World claude'
```

Detach with the [`Ctrl-b` then `d`](https://research.it.iastate.edu/guides/pronto/interactive_computing/tmux/#detach-from-a-session)
shortcut — Claude keeps running, so you can close your laptop. Re-attach later by
running the same command again, from any device on the tailnet.

> The session survives SSH drops and your laptop sleeping. It does **not** survive
> a container restart (`docker compose down`, host reboot) — that kills tmux and
> the Claude process. Your files and logins persist (they're mounted on the host);
> the live session does not.

You can also open the remote in VS Code, if you have the [`code` CLI](https://code.visualstudio.com/docs/configure/command-line) installed:

```bash
code --remote ssh-remote+dev@dbox /home/dev/workspace/Hello-World
```

## Where state lives

Everything persistent is under `./data/` (git-ignored), one folder to back up or wipe:

| `./data/…`  | mount                 | holds                         |
| ----------- | --------------------- | ----------------------------- |
| `workspace` | `~/workspace`         | your repos                    |
| `claude`    | `~/.claude`           | Claude creds/settings/history |
| `gh`        | `~/.config/gh`        | GitHub OAuth                  |
| `fish`      | `~/.local/share/fish` | shell history                 |
| `sshkeys`   | `/etc/ssh/keys`       | SSH host keys                 |
| `tailscale` | `/var/lib/tailscale`  | tailnet identity              |

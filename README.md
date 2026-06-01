# dbox

A single Docker container that _is_ a dev box — SSH + tmux + fish + Claude Code —
reachable over Tailscale by a stable name (`dbox.<tailnet>.ts.net`), persisting
long-running Claude sessions with the laptop shut. Runs identically on a
DigitalOcean Droplet and a Mac mini. See [PLAN.md](./PLAN.md) for the full design.

## Architecture

```
   ┌──────────────┐          your laptop
   │    laptop    │   ssh dev@dbox  ·  VSCode Remote-SSH
   │  (tailnet)   │
   └──────┬───────┘
          │  WireGuard (Tailscale) · no public ports
          │  MagicDNS: dbox.<tailnet>.ts.net
══════════╪══════════════════ tailnet ══════════════════════
          │
   ┌──────▼──────────────────────────────────────────────┐
   │  host: DigitalOcean Droplet  ·  Mac mini  ·  laptop  │
   │  (only requirement: Docker)                          │
   │                                                      │
   │   docker compose                                     │
   │   ┌────────────────────┐   ┌──────────────────────┐ │
   │   │  tailscale sidecar │   │   dev container      │ │
   │   │  image: tailscale  │◀──┤  network_mode:       │ │
   │   │  · NET_ADMIN       │   │    service:tailscale │ │
   │   │  · /dev/net/tun    │   │  (shares netns →     │ │
   │   │  · owns tailnet    │   │   sshd on tailnet,   │ │
   │   │    identity "dbox" │   │   unprivileged)      │ │
   │   └─────────┬──────────┘   │                      │ │
   │             │              │  sshd (pubkey only)  │ │
   │             │              │  tmux · fish         │ │
   │             │              │  claude · gh · git   │ │
   │             │              │  user: dev (1000)    │ │
   │             │              └──────────┬───────────┘ │
   │             │                         │ bind mounts  │
   │             ▼                         ▼              │
   │   ./data/tailscale          ./data/{workspace,      │
   │   (node identity)            claude, gh, fish,       │
   │                              sshkeys}                │
   └──────────────────────────────────────────────────────┘
        persistent state on host  ·  survives rebuilds
```

- **One SSH endpoint** (`dbox`) for both tmux and VSCode — the container *is* the box.
- **Tailscale sidecar** owns the tailnet identity; the dev container shares its
  network namespace, so `sshd` is reachable on the tailnet without being privileged.
- **All state in `./data/`** (bind mounts) → auth, repos, and host key survive
  rebuilds. tmux protects sessions across SSH drops, not container restarts.

## Quick start (local)

1. **Configure secrets**

   ```bash
   cp .env.example .env
   # Set TS_AUTHKEY (Tailscale admin → keys) and SSH_PUBKEY (cat ~/.ssh/id_ed25519.pub)
   ```

2. **Bring it up**

   ```bash
   docker compose up -d --build
   ```

   The container joins your tailnet as **dbox**. Check the Tailscale admin console.

3. **Connect**

   ```bash
   ssh dev@dbox.<your-tailnet>.ts.net
   tmux attach -t main
   ```

   Or VSCode Remote-SSH to the same host, open `~/workspace`.

4. **One-time auth inside the box (persists in ./data)**

   ```bash
   ssh dev@dbox
   gh auth login   # GitHub.com → HTTPS → "Paste an authentication token"
   claude          # opens a URL — auth in your laptop browser, paste code back
   ```

   For `gh`, paste a **fine-grained PAT** (Settings → Developer settings →
   Fine-grained tokens) scoped to just the repos you'll use here, with
   **Contents: R/W**, **Pull requests: R/W** (Claude uses `gh pr create`),
   **Metadata: R**, and an expiry — least privilege for an unattended box.
   `gh auth login` also configures git, so plain `git` over HTTPS works too.
   (Web-browser OAuth is the convenient alternative, but account-wide with no
   expiry.) Don't set `GITHUB_TOKEN` in `.env` — a token in the env makes
   `gh auth login` refuse to run.

## Where state lives

Everything persistent is under `./data/` (git-ignored), one folder to back up or wipe:

| `./data/…`      | mount                 | holds                         |
| --------------- | --------------------- | ----------------------------- |
| `workspace`     | `~/workspace`         | your repos                    |
| `claude`        | `~/.claude`           | Claude creds/settings/history |
| `gh`            | `~/.config/gh`        | GitHub OAuth                  |
| `fish`          | `~/.local/share/fish` | shell history                 |
| `sshkeys`       | `/etc/ssh/keys`       | SSH host keys                 |
| `tailscale`     | `/var/lib/tailscale`  | tailnet identity              |

## Notes

- **tmux** survives SSH disconnects (laptop shut), **not** container restarts —
  volumes preserve files/auth, not live processes.
- **Break-glass** (no Tailscale yet): uncomment the loopback `ports:` on the
  `tailscale` service, then `ssh -p 2222 dev@localhost`. Local machines only.
- Rebuild to update tooling/fish config: `docker compose up -d --build`.
  Auth and work survive (they're in `./data/`).

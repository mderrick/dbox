# dbox — persistent remote dev container

A single Docker container that *is* a dev box: SSH + tmux + fish + Claude Code,
reachable over Tailscale by a stable name, persisting long-running Claude
sessions while the laptop is shut. Runs identically on a DigitalOcean Droplet
and a Mac mini.

## Goals

- SSH/tmux in and reattach a long-running Claude session with the laptop shut.
- VSCode Remote-SSH into the same endpoint, sharing one filesystem with Claude.
- **Identical** deploy on VPS and Mac mini; **idempotent** via `docker compose`.
- Start fresh — no dotfiles/plugins/config from the local machine.

## Resolved decisions (the grill)

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| 1 | Base image | **Debian (glibc)**, not `linuxserver/openssh-server` | VSCode server is glibc-only; Alpine/musl breaks Remote-SSH |
| 2 | Topology | **Option A — container *is* the dev box** (own `sshd`) | One SSH endpoint for tmux *and* VSCode; no Docker indirection |
| 3 | Filesystem | **Single shared `~/workspace`** | Claude edits + VSCode review must see the same working tree |
| 4 | User | **non-root `dev`, UID/GID 1000, passwordless sudo** | Closest to local; tidy home; stable volume ownership |
| 5 | Claude auth | **Subscription OAuth**, `~/.claude` on a volume | Matches Max plan; no per-token bills; login survives rebuilds |
| 6 | GitHub auth | **`gh auth login` (paste a fine-grained PAT)**, stored in `data/gh`; image bakes gh as git's credential helper | Interactive anyway (so is Claude), keeps token in-box (off host `.env`/container env); fine-grained PAT = scoped repos + expiry. Web OAuth is the account-wide convenience alt. Don't set `GITHUB_TOKEN` env — it makes `gh auth login` refuse |
| 7 | SSH-in | **pubkey-only**, passwords off, **host keys on a volume** | Avoids `HOST IDENTIFICATION CHANGED` after rebuilds |
| 8 | Network | **Tailscale in the deployment, sidecar pattern** | Container owns one MagicDNS name → identical endpoint everywhere |
| 9 | Persistence | **Granular state-volumes; config/dotfiles baked** | Work + auth immortal; dotfiles still updatable via rebuild |
| 10 | Orchestration | **Committed `docker-compose.yml` + registry image + git-ignored `.env`** | One source of truth; `compose pull && up -d` everywhere |
| 11 | tmux | **Auto-create empty `main` on boot**, don't auto-launch Claude | Always something to attach to; you drive Claude manually + per-project sessions |
| 12 | Scope | **Claude only for v1**; Codex is a fast-follow | Keep first deploy debuggable |

### Things explicitly rejected
- `linuxserver/openssh-server` (Alpine/musl vs VSCode glibc).
- "Clone Repository in Container Volume" (separate VSCode-managed container =
  split filesystem, breaks Claude+VSCode shared edits).
- Tailscale **on the host** (host-specific MagicDNS name breaks "identical";
  manual per-host `tailscale up` breaks idempotency — esp. macOS, no cloud-init).
- DigitalOcean **App Platform** / "just an image path" PaaS (no `NET_ADMIN` /
  `/dev/net/tun`, no SSH-in, no arbitrary persistent volumes). **Use a Droplet.**

## Architecture

```
        laptop (tailnet node)
              │  ssh dev@dbox.<tailnet>.ts.net   +   VSCode Remote-SSH
              ▼
   ┌─────────────────────────── docker compose ───────────────────────────┐
   │                                                                       │
   │   tailscale sidecar            dev container                          │
   │   (tailscale/tailscale)        (our Debian image)                     │
   │   - NET_ADMIN, /dev/net/tun    - network_mode: service:tailscale      │
   │   - joins tailnet as "dbox"    - sshd (pubkey only)                   │
   │   - owns the netns  ◀──────────  - tmux + fish + claude + git + gh     │
   │                                  - user: dev (1000:1000)              │
   └───────────────────────────────────────────────────────────────────────┘
        host = Droplet OR Mac mini — only requirement: Docker installed
```

The dev container shares the sidecar's network namespace, so its `sshd` is
reachable on the tailnet IP **without itself being privileged**. The privileged
caps live only in the tiny sidecar. Both are declared in one compose file.

### Persistent state — bind mounts under one host directory

All state lives under a single host directory `${DBOX_DATA}` (default `./data`,
git-ignored; set to e.g. `/opt/dbox/data` on the Droplet). One tidy folder to
see/back-up/wipe.

| Host path | Container mount | Holds |
|-----------|-----------------|-------|
| `${DBOX_DATA}/workspace` | `/home/dev/workspace` | repos (the actual work) |
| `${DBOX_DATA}/claude` | `/home/dev/.claude` | Claude OAuth creds, settings, history, memory |
| `${DBOX_DATA}/gh` | `/home/dev/.config/gh` | GitHub OAuth token |
| `${DBOX_DATA}/fish` | `/home/dev/.local/share/fish` | fish history |
| `${DBOX_DATA}/sshkeys` | `/etc/ssh/keys` | persistent SSH host keys |
| `${DBOX_DATA}/tailscale` | `/var/lib/tailscale` (on **sidecar**) | tailnet node identity |

Baked into the image (updated by rebuilds): fish config, `authorized_keys`
(laptop pubkey), git global config, installed tools. Don't persist all of
`/home/dev` — it would shadow baked dotfiles on rebuild.

**Ownership:** entrypoint (runs as root) `chown`s the dev-owned bind paths to
`1000:1000` on boot — idempotent. macOS Docker Desktop auto-maps, so it's a
no-op there.

**macOS perf caveat:** bind mounts cross the Docker Desktop VM boundary
(VirtioFS), slower than named volumes for heavy I/O. Fine for v1; **no penalty
on the Linux Droplet**. If `~/workspace` feels slow on the Mac, special-case
*just it* back to a true named volume and leave the rest under `${DBOX_DATA}`.

## Repo layout

```
dbox/
├── PLAN.md                  # this file
├── Dockerfile               # Debian + dev user + sshd + fish + node + claude + gh
├── docker-compose.yml       # dev + tailscale sidecar, volumes, caps, restart
├── .env.example             # TS_AUTHKEY=, DBOX_DATA=./data, (optional) GITHUB_TOKEN=
├── .gitignore               # .env, data/
├── data/                    # all persistent state (git-ignored), created on first run
├── config/
│   ├── sshd_config          # pubkey only, PasswordAuthentication no, HostKey /etc/ssh/keys/*
│   ├── config.fish          # minimal fresh fish config
│   └── entrypoint.sh         # chown bind paths, gen/persist host keys, ensure tmux `main`, exec sshd
└── README.md                # bring-up + auth runbook
```

## Build & deploy model

1. Build image, push to **GHCR** (`ghcr.io/mderrick/dbox:latest`) — locally or via Actions.
2. `docker-compose.yml` references `image: ghcr.io/mderrick/dbox:latest` (the "image path").
3. On any host: `git pull && docker compose pull && docker compose up -d`.
4. Secrets via git-ignored `.env` (`TS_AUTHKEY`, `SSH_PUBKEY`). GitHub auth is
   done in-box via `gh auth login` — no token in `.env`.

## First-run auth (once; persists via volumes)

1. `ssh dev@dbox.<tailnet>.ts.net`
2. `gh auth login` → GitHub.com → HTTPS → **Paste an authentication token** →
   use a **fine-grained PAT** (scoped repos, Contents R/W, Pull requests R/W,
   Metadata R, an expiry). Also configures git's credential helper →
   `~/.config/gh` populated. (Web OAuth is the account-wide convenience alt.)
3. `claude` → open printed URL on laptop, paste code back → `~/.claude` populated.
   Both persist across rebuilds via the volumes.

---

## Phase 1 — local deploy (do this first)

Run the whole thing on the laptop's Docker Desktop, reached over the tailnet —
**no localhost special case** (proves real parity from day one).

1. **Scaffold** the repo files above (Dockerfile, compose, config/, .env.example, .gitignore).
2. **Dockerfile**: `debian:bookworm-slim` → install `openssh-server git curl ca-certificates tmux fish sudo` → install Node LTS → `npm i -g @anthropic-ai/claude-code` → install `gh` → create `dev` (1000:1000, sudo) → bake fish config + `authorized_keys` → entrypoint.
3. **entrypoint.sh**: `chown 1000:1000` the dev-owned bind paths (`/home/dev/workspace`, `/home/dev/.claude`, `/home/dev/.config/gh`, `/home/dev/.local/share/fish`); if `/etc/ssh/keys` empty → `ssh-keygen -A` then move/point host keys there; ensure tmux `main` exists (`tmux has-session -t main || tmux new-session -d -s main`); `exec /usr/sbin/sshd -D`.
4. **compose**: `tailscale` sidecar (`NET_ADMIN`, `/dev/net/tun`, `TS_AUTHKEY`, `${DBOX_DATA}/tailscale` bind, `TS_HOSTNAME=dbox`); `dev` service `network_mode: service:tailscale`, the five `${DBOX_DATA}/*` binds, `restart: unless-stopped`. Optional break-glass `-p 127.0.0.1:2222:22` on the sidecar for the very first local boot only.
5. **Provision** `.env` with `TS_AUTHKEY`. `docker compose up -d --build`.
6. **Verify (evidence required):**
   - Container shows up in Tailscale admin as `dbox`.
   - `ssh dev@dbox.<tailnet>.ts.net` → fish prompt.
   - `tmux attach -t main` works.
   - Start `claude`, auth, run a trivial task.
   - `gh auth login`, `gh repo list`.
   - VSCode Remote-SSH to `dbox.<tailnet>.ts.net`, open `~/workspace`.
   - **Rebuild test:** `docker compose up -d --build`; reconnect with **no**
     host-key warning, Claude/gh **still logged in**, `~/workspace` intact.

## Phase 2 — remote parity

7. Push image to GHCR; switch compose to `image:` reference.
8. DO **Droplet** (Docker installed) → copy compose + `.env` → `docker compose up -d`.
9. Confirm the **same** `dbox.<tailnet>.ts.net` endpoint works from the laptop.

## Phase 3 — fast-follows (later)

- Codex: Dockerfile line + `~/.codex` volume + auth.
- Persist fish history volume if desired.
- `clone <repo>` fish function into `~/workspace`.
- GitHub Actions to build/push image on git push.

## Known sharp edges

- Container **restart** kills running Claude (tmux dies with PID 1); volumes keep
  files/auth, not live processes. Persistence covers SSH drops, not restarts.
- Don't persist all of `/home/dev` — it would shadow baked dotfiles on rebuild.
- **Claude stores config in TWO places**: `~/.claude/` (creds/sessions, persisted)
  AND `~/.claude.json` (loose in `$HOME`, NOT persisted → lost on recreate). Fix:
  `CLAUDE_CONFIG_DIR=/home/dev/.claude` (baked for fish/bash/PAM) relocates the
  `.claude.json` content into the persisted dir. Verified to survive `down`/`up`.
- macOS Docker Desktop supports `NET_ADMIN` + `/dev/net/tun` for the sidecar (works).
- **sshd doesn't inherit the container's env**: compose `environment:` vars are
  in PID 1's env but absent from interactive SSH sessions. (Why we auth GitHub
  in-box via `gh auth login` rather than passing a token through the env.)

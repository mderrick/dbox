---
name: dbox
description: Drive the dbox dev container from inside it — clone repos into ~/workspace, create or open per-project Claude sessions, and request a rebuild/restart. Use when the user wants to set up a new repo in the box, start or attach a project's claude session, or restart/rebuild dbox — e.g. "clone X into dbox", "start a session for repo Y", "set up <repo> in the box", "restart the box".
---

# dbox

Helpers baked into this container for managing dbox itself. **This skill runs
inside the box**, so it uses the `/usr/local/bin/dbox-*` commands directly. (The
`dbox` CLI in the README is the *laptop* wrapper around these — it is not on
PATH in here.)

Every per-project session uses one tmux layout: window `shell` + window `claude`
running `claude --remote-control`, so it's drivable from the Claude mobile app.
Claude's shell can't `tmux attach`, so **always create sessions detached** and
hand the user attach instructions (see below).

## Clone a repo and start its session — `dbox-clone`

```sh
dbox-clone --no-attach <url>
```

- `<url>` — a **fully-qualified git URL**: `https://`, `ssh://`, or scp-style
  `git@host:path`. Owner/name shorthand is **not** accepted — the host is part
  of the namespace, so it must be in the URL.

Clones into a namespaced dir `~/workspace/<host>/<path>` (e.g.
`github.com/octocat/Hello-World`, `gitlab.com/acme/backend/auth-api`) so
same-named repos from different owners, forges, or GitLab subgroups never
collide. Then creates the detached session and prints its tmux name. If it
reports the dir already exists, don't re-clone — open it with `dbox-terminal`.

Auth: GitHub HTTPS uses the baked `gh auth git-credential` helper, so private
GitHub repos just work. Private **GitLab** (or other hosts) have no HTTPS helper
— clone over SSH (`git@gitlab.com:…`, using a key the box holds) or add a PAT
credential helper first.

## Open/create a session for an existing checkout — `dbox-terminal`

```sh
dbox-terminal --no-attach <name|path>
```

Idempotently builds the per-project session for a dir already under
`~/workspace` (e.g. `github.com/octocat/Hello-World`). The arg resolves relative
to `~/workspace`, or a leading `/` / `~` is taken literally. The tmux session
name is the sanitized relative path (`github-com-octocat-Hello-World`); the
Claude-app label is `<repo> (<namespace>)` (`Hello-World (github.com/octocat)`).

## How to attach (after creating a session)

The session is already running detached. Tell the user to attach from:

- the **Claude mobile app** (the `claude` window is `--remote-control`), or
- a laptop on the tailnet: `dbox terminal <name>`, or
- inside the box: `tmux attach -t <name>`.

Never `tmux attach` yourself — it fails in Claude's non-interactive shell.

## Restart / rebuild the box — `dbox-restart`  ⚠️ destructive

```sh
dbox-restart
```

Signals the `restarter` sidecar to `git pull --ff-only && docker compose up -d
--build dev` on the host. This **recreates this very container** and **drops the
current session** — ssh, tmux, and this Claude process all die.

Before running it, REQUIRE both:

1. Work is committed **and pushed** — the sidecar rebuilds from `origin/main`, a
   different clone, so anything uncommitted is not picked up. Verify `git status`
   is clean and `git rev-list --count origin/main..main` is `0`.
2. Explicit user confirmation — it kills the session they're talking to you in.

After firing it, **stop** — don't run anything else. This Claude session is now
broken: the rebuild kills tmux and this `claude` process, and **nothing restarts
it automatically**. It won't exist again until someone manually recreates it
once the host is back up (`ssh dev@dbox`, then `dbox-terminal <name>` / the Claude
mobile app). Treat the command as the last thing you do in this session.

## Notes

- `gh auth login` must already be done in the box for shorthand / private clones.
- Sessions survive SSH drops, not container restarts — detach, don't Ctrl-C.
- List running sessions with `tmux ls`.

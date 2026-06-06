---
name: dbox
description: Drive the dbox dev container from inside it — set up repos in ~/workspace (git clone + session), create or open per-project Claude sessions, and request a rebuild/restart. Use when the user wants to set up a new repo in the box, start or attach a project's claude session, or restart/rebuild dbox — e.g. "clone X into dbox", "start a session for repo Y", "set up <repo> in the box", "restart the box".
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

## Set up a new repo — `git clone` then `dbox-terminal`

There's no dedicated clone command — just clone into `~/workspace` with a flat,
memorable dir name, then start its session. **Always pass an absolute path** —
`dbox-terminal` is cd-relative (a bare name resolves against your current dir,
which isn't reliably `~/workspace`):

```sh
git clone <url> ~/workspace/<name>
dbox-terminal --no-attach ~/workspace/<name>
```

Pick `<name>` from the repo (usually its basename, e.g. `hello-world`). The tmux
session name is derived from the absolute path, so distinct dirs never collide;
but reusing an existing dir reattaches its session. If the dir already exists,
don't re-clone — notify the user that this url is already cloned and then offer
to run `dbox-terminal` on the existing project, or to clone it into a new directory
with a new unique name.

Auth: GitHub HTTPS uses the baked `gh auth git-credential` helper, so private
GitHub repos just work. Private **GitLab** (or other hosts) have no HTTPS helper
— clone over SSH (`git@gitlab.com:…`, using a key the box holds) or add a PAT
credential helper first.

## Open/create a session for an existing checkout — `dbox-terminal`

```sh
dbox-terminal --no-attach ~/workspace/<name>
```

Idempotently builds the per-directory session. The arg is cd-relative (a bare
name resolves against the current dir; a leading `/` or `~` is literal), so pass
an absolute path. The **tmux session name** is the absolute path sanitized
(`/home/dev/workspace/api` -> `home-dev-workspace-api`) — unique per dir. The
**Claude-app label** is the git repo's top-level dir name (`api`) when the dir is
a repo, else its path relative to `~/workspace` (`acme/notes`).

## How to attach (after creating a session)

The session is already running detached. `dbox-terminal --no-attach` prints the
tmux session name (the sanitized absolute path, e.g. `home-dev-workspace-api`).
Tell the user to attach from:

- the **Claude mobile app** (the `claude` window is `--remote-control`), or
- a laptop on the tailnet: `dbox terminal <path>` (the workspace path, e.g.
  `api` or `acme/auth-api`), or
- inside the box: `tmux attach -t <session-name>` (the printed name).

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
once the host is back up (`ssh dev@dbox`, then `dbox-terminal ~/workspace/<name>`
/ the Claude mobile app). Treat the command as the last thing you do in this session.

## Notes

- `gh auth login` must already be done in the box for shorthand / private clones.
- Sessions survive SSH drops, not container restarts — detach, don't Ctrl-C.
- List running sessions with `tmux ls`.

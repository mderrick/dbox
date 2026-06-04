# dbox — a single Debian-based dev container: sshd + tmux + fish + Claude.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Base tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server git curl ca-certificates gnupg tmux fish sudo procps bash \
    && rm -rf /var/lib/apt/lists/*

# Node LTS (for Claude Code) via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI — pinned so rebuilds are deterministic and bumping the version
# busts Docker's layer cache (an unpinned `npm install -g` stays cached forever).
RUN npm install -g @anthropic-ai/claude-code@2.1.162

# Non-root dev user (UID/GID 1000), fish login shell, passwordless sudo
RUN groupadd -g 1000 dev \
    && useradd -m -u 1000 -g 1000 -s /usr/bin/fish dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && chmod 0440 /etc/sudoers.d/dev

# Use gh as git's credential helper for github.com, so after `gh auth login`
# plain `git` over HTTPS uses your stored gh credentials (no separate
# `gh auth setup-git` step needed).
RUN HOME=/home/dev git config --global credential."https://github.com".helper '!gh auth git-credential' \
    && chown dev:dev /home/dev/.gitconfig

# Relocate Claude's config dir into the volume-backed ~/.claude. Without this,
# ~/.claude.json lives loose in $HOME and is LOST on container recreate (only
# ~/.claude/ is persisted). Set for every shell: fish (login shell), bash
# (VSCode server), and /etc/environment (PAM/sshd sessions).
RUN mkdir -p /etc/fish/conf.d \
    && echo 'set -gx CLAUDE_CONFIG_DIR /home/dev/.claude' > /etc/fish/conf.d/dbox.fish \
    && echo 'export CLAUDE_CONFIG_DIR=/home/dev/.claude'   > /etc/profile.d/dbox.sh \
    && echo 'CLAUDE_CONFIG_DIR=/home/dev/.claude'         >> /etc/environment

# Baked fish config (NOT persisted, so rebuilds can update it)
COPY config/config.fish /home/dev/.config/fish/config.fish

# sshd config + entrypoint
COPY config/sshd_config /etc/ssh/sshd_config
COPY config/entrypoint.sh /usr/local/bin/entrypoint.sh

# Shared tmux-session launcher, called by both the `dbox` CLI and the VS Code
# terminal profile so they produce the identical session layout.
COPY config/dbox-session /usr/local/bin/dbox-session

# In-container helper that requests a rebuild+restart of the stack (the dev
# container can't reach the host Docker daemon, so it signals via the
# bind-mounted control dir; the `restarter` compose sidecar acts on it).
COPY config/dbox-restart /usr/local/bin/dbox-restart

COPY config/tmux.conf /home/dev/.tmux.conf

# Ownership + runtime dirs. ~/workspace and /etc/ssh/keys are bind-mount targets.
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/dbox-session /usr/local/bin/dbox-restart \
    && mkdir -p /run/sshd /etc/ssh/keys /home/dev/workspace /home/dev/.config/fish /home/dev/.dbox-control \
    && chown -R dev:dev /home/dev

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

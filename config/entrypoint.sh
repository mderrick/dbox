#!/usr/bin/env bash
# dbox entrypoint — runs as root on every container start, does one-time setup,
# then hands off to sshd. Everything here must be idempotent (it re-runs on each
# restart). Final `exec sshd` makes sshd PID 1 (the container's main process).
set -euo pipefail  # fail fast: -e any error, -u unset var, -o pipefail in pipes

# sshd refuses to start without its privilege-separation dir. /run is ephemeral,
# so recreate it each boot.
mkdir -p /run/sshd

# --- 1. Persistent SSH host keys -------------------------------------------
# /etc/ssh/keys is bind-mounted to ./data/sshkeys, so keys outlive rebuilds.
# First boot: dir is empty -> generate. Later boots: keys exist -> reuse them.
# Stable host keys are what stop the laptop's "HOST IDENTIFICATION CHANGED" wall
# after a rebuild. -N '' = no passphrase; </dev/null = never prompt.
if [ ! -f /etc/ssh/keys/ssh_host_ed25519_key ]; then
  ssh-keygen -t ed25519 -f /etc/ssh/keys/ssh_host_ed25519_key -N '' </dev/null
fi
if [ ! -f /etc/ssh/keys/ssh_host_rsa_key ]; then
  ssh-keygen -t rsa -b 4096 -f /etc/ssh/keys/ssh_host_rsa_key -N '' </dev/null
fi
chmod 600 /etc/ssh/keys/ssh_host_*_key      # sshd rejects world-readable privkeys
chmod 644 /etc/ssh/keys/ssh_host_*_key.pub

# --- 2. Fix ownership of bind-mounted paths --------------------------------
# Docker creates bind mountpoints root-owned, but we log in as dev (UID 1000),
# so dev couldn't write to them. Force ownership to dev each boot. Essential on
# the Linux Droplet; effectively a no-op on macOS (Docker Desktop maps owners).
# `|| true` so a stray permission hiccup doesn't abort startup.
mkdir -p /home/dev/workspace /home/dev/.claude /home/dev/.config/gh /home/dev/.local/share/fish
chown 1000:1000 /home/dev/.config /home/dev/.local /home/dev/.local/share 2>/dev/null || true
chown -R 1000:1000 /home/dev/workspace /home/dev/.claude /home/dev/.config/gh /home/dev/.local/share/fish 2>/dev/null || true

# --- 3. Install the laptop public key (this is how you SSH in) --------------
# Read at runtime from the SSH_PUBKEY env (set in .env), not baked into the
# image -> rotate the key with an .env edit + restart, no rebuild. ~/.ssh isn't
# persisted, so it's rewritten from the env every boot (always matches .env).
# chmod 700/600 is mandatory: sshd ignores authorized_keys with looser perms.
if [ -n "${SSH_PUBKEY:-}" ]; then
  mkdir -p /home/dev/.ssh
  printf '%s\n' "$SSH_PUBKEY" > /home/dev/.ssh/authorized_keys
  chmod 700 /home/dev/.ssh
  chmod 600 /home/dev/.ssh/authorized_keys
  chown -R 1000:1000 /home/dev/.ssh
else
  echo "WARNING: SSH_PUBKEY is empty — no authorized_keys installed; SSH login will fail." >&2
fi

# --- 4. Baseline tmux 'main' session ---------------------------------------
# Always leave a 'main' session to attach to. Run as dev (not root) so the
# session is yours. has-session || new-session = create only if absent
# (idempotent); -d = detached background server. You still make per-project
# sessions yourself. NB: this session dies on container restart (see header).
su dev -s /bin/bash -c 'tmux has-session -t main 2>/dev/null || tmux new-session -d -s main' || true

# --- 5. Hand off to sshd ----------------------------------------------------
# exec replaces this script with sshd, so sshd becomes PID 1 and keeps the
# container alive. -D = foreground (required in a container), -e = log to stderr
# so `docker logs` shows SSH activity.
exec /usr/sbin/sshd -D -e

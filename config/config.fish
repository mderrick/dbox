# Minimal fresh fish config for dbox (baked into the image).
set -g fish_greeting "🐟 dbox — `tmux attach -t main` to reattach, or `tmux new -s <project>`"

# npm global bin (Claude Code) is on PATH via /usr/bin; nothing extra needed.
# Add your own aliases/functions here over time — rebuild the image to update.

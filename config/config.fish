# Minimal fresh fish config for dbox (baked into the image).
set -g fish_greeting

function fish_greeting
    set_color cyan
    echo '     _ _'
    echo '  __| | |__   _____  __'
    echo ' / _` | \'_ \\ / _ \\ \\/ /'
    echo '| (_| | |_) | (_) >  <'
    echo ' \\__,_|_.__/ \\___/_/\\_\\'
    set_color normal
end

# npm global bin (Claude Code) is on PATH via /usr/bin; nothing extra needed.
# Add your own aliases/functions here over time — rebuild the image to update.

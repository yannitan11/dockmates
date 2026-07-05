#!/bin/zsh
# Builds Dockmates and installs a stable copy in /Applications, so the
# "launch at login" item survives moving or deleting this project folder.
# Run this instead of build.sh whenever you want the installed copy to
# pick up new changes.
set -e
cd "$(dirname "$0")"

./build.sh

DEST=/Applications/Dockmates.app

echo "Installing to $DEST"
pkill -x Dockmates 2>/dev/null || true
sleep 0.5

rm -rf "$DEST"
cp -R build/Dockmates.app "$DEST"
codesign --force --sign - "$DEST" 2>/dev/null || true

# Dockmates only auto-registers "Start at Login" on its very first run.
# Resetting that flag makes the freshly-installed /Applications copy treat
# this launch as first-run, so the login item points here instead of at
# wherever it ran from before.
defaults write com.yannitan.dockmates loginItemBootstrapped -bool false

echo "Installed $DEST"
open "$DEST"
echo "Launched. It will also start automatically at login from now on."

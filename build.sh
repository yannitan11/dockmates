#!/bin/zsh
# Builds Dockmates.app with the Swift command line tools (no Xcode needed).
set -e
cd "$(dirname "$0")"

APP=build/Dockmates.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/Dockmates"

codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP"
echo "Run it with: open \"$APP\""

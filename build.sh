#!/bin/zsh
# Builds Dockmates.app with the Swift command line tools (no Xcode needed).
set -e
cd "$(dirname "$0")"

APP=build/Dockmates.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/Dockmates"

# Build AppIcon.icns from the master 1024px PNG (Resources/icon_1024.png).
# Regenerate that master with: build/Dockmates.app/Contents/MacOS/Dockmates --icon Resources/icon_1024.png 1024
if [ -f Resources/icon_1024.png ]; then
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size Resources/icon_1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double Resources/icon_1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
fi

codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP"
echo "Run it with: open \"$APP\""

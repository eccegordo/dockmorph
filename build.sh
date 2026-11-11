#!/bin/bash
# Builds Dock Morph and packages it as "build/Dock Morph.app"
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Dock Morph.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$(swift build -c release --show-bin-path)/DockMorph" "$APP/Contents/MacOS/DockMorph"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"

#!/bin/sh
# Builds Lines.app into ./build. Usage: ./build.sh [debug|release]
set -e
cd "$(dirname "$0")"
CONFIG="${1:-release}"

# Prefer a full Xcode when one is installed, even if xcode-select still points
# at the Command Line Tools.
if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
APP="build/Lines.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Lines"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lines"
cp Support/Info.plist "$APP/Contents/Info.plist"
# SwiftPM resource bundles (the canvas page) go where Bundle.module looks first.
for bundle in "$BIN_DIR"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

if [ ! -f build/AppIcon.icns ] || [ Support/MakeIcon.swift -nt build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift Support/MakeIcon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

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

# The app icon is an Icon Composer document. actool compiles it into Assets.car
# (Liquid Glass, dark and clear variants) plus a fallback AppIcon.icns. If actool
# can't run (Xcode's first-launch setup not done), render a static .icns with
# Icon Composer's ictool instead.
ICON=Support/AppIcon.icon
ASSETS=Support/Assets.xcassets   # AccentColor, matching the icon's orange
if [ ! -f build/icon/AppIcon.icns ] || [ -n "$(find "$ICON" "$ASSETS" -newer build/icon/AppIcon.icns)" ]; then
  rm -rf build/icon
  mkdir -p build/icon
  if ! xcrun actool "$ICON" "$ASSETS" --compile build/icon --platform macosx \
      --minimum-deployment-target 27.0 --app-icon AppIcon --accent-color AccentColor \
      --output-partial-info-plist build/icon/partial.plist >/dev/null 2>build/icon/actool.log; then
    echo "actool failed (see build/icon/actool.log); rendering a static icon with ictool" >&2
    rm -f build/icon/Assets.car
    ICTOOL="${DEVELOPER_DIR:-$(xcode-select -p)}/../Applications/Icon Composer.app/Contents/Executables/ictool"
    mkdir -p build/icon/AppIcon.iconset
    for size in 16 32 128 256 512; do
      for scale in 1 2; do
        suffix=""
        [ "$scale" = 2 ] && suffix="@2x"
        "$ICTOOL" "$ICON" --export-image --platform macOS --rendition Default \
          --width "$size" --height "$size" --scale "$scale" \
          --output-file "build/icon/AppIcon.iconset/icon_${size}x${size}${suffix}.png" >/dev/null
      done
    done
    iconutil -c icns build/icon/AppIcon.iconset -o build/icon/AppIcon.icns
  fi
fi
cp build/icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f build/icon/Assets.car ] && cp build/icon/Assets.car "$APP/Contents/Resources/Assets.car"

# Translations: the String Catalog compiles to <language>.lproj folders in the
# app's own Resources, where SwiftUI looks them up. `just strings` refreshes it.
if [ -f Support/Localizable.xcstrings ]; then
  xcrun xcstringstool compile Support/Localizable.xcstrings --output-directory "$APP/Contents/Resources" >/dev/null
fi

codesign --force --sign - "$APP"
# Finder and the Dock cache icons by bundle; touching the bundle and
# re-registering it makes them pick up a changed icon.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

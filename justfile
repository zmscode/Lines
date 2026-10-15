# Lines — common tasks. `just` lists them.

app := "build/Lines.app"
bundle_id := "com.zms.Lines"
version := trim(read("VERSION"))
# Where releases are published, and the Homebrew tap that installs them.
github := "zmscode/Lines"
tap := "zmscode/homebrew-lines"
xcode := "/Applications/Xcode.app/Contents/Developer"

# Prefer a full Xcode when one is installed, even if xcode-select still points
# at the Command Line Tools.
export DEVELOPER_DIR := env("DEVELOPER_DIR", if path_exists(xcode) == "true" { xcode } else { `xcode-select -p` })

# Aliases

alias b := build
alias r := run
alias f := format
alias c := clean

# List the recipes
default:
    @just --list

# Skips the build when nothing that goes into the app has changed since the last one.
# Build build/Lines.app if anything changed (release by default; `just build debug` for debug)
build config="release":
    #!/usr/bin/env sh
    set -e
    stamp="build/.inputs-{{ config }}"
    current="$(just _inputs-hash {{ config }})"
    if [ -d "{{ app }}" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$current" ]; then
      echo "{{ app }} is up to date ({{ config }})"
      exit 0
    fi
    just _bundle {{ config }}
    rm -f build/.inputs-*  # one app bundle, so only the latest config is current
    echo "$current" > "$stamp"

# Build even if nothing has changed
rebuild config="release":
    rm -f build/.inputs-*
    @just build {{ config }}

# A hash of everything that goes into the app, plus the build configuration
[private]
_inputs-hash config:
    @{ echo "{{ config }}"; find Sources Support Vendor Package.swift Package.resolved justfile VERSION \
        -type f -not -path '*/.build/*' -not -name '.DS_Store' -print0 2>/dev/null \
        | LC_ALL=C sort -z | xargs -0 shasum; } | shasum | cut -d' ' -f1

# Build, quit any running copy, and open the fresh build
run config="release": (build config)
    #!/usr/bin/env sh
    # Quit politely so open documents autosave, then wait for it to exit,
    # so `open` launches this build rather than reactivating an old one.
    if pgrep -xq Lines; then
      osascript -e 'tell application id "{{ bundle_id }}" to quit' >/dev/null 2>&1 || true
      for _ in $(seq 1 50); do pgrep -xq Lines || break; sleep 0.1; done
    fi
    open "{{ app }}"

# Format the Swift sources with the project's .swift-format
format:
    xcrun swift-format format -i -r Sources/Lines

# Refresh Support/Localizable.xcstrings with every string the app shows
strings:
    #!/usr/bin/env sh
    set -e
    out="$(mktemp -d)"
    swift build -c debug -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$out"
    # Only Lines's own sources, not the vendored packages.
    mkdir "$out/lines"
    find Sources/Lines -name '*.swift' -exec basename {} .swift \; | while read -r name; do
      [ -f "$out/$name.stringsdata" ] && cp "$out/$name.stringsdata" "$out/lines/"
    done
    xcrun xcstringstool sync Support/Localizable.xcstrings --stringsdata "$out"/lines/*.stringsdata
    rm -rf "$out"
    echo "Updated Support/Localizable.xcstrings"

# Compile and assemble build/Lines.app, signed for this Mac
[private]
_bundle config: _icon
    #!/usr/bin/env sh
    set -e
    swift build -c {{ config }}
    bin_dir="$(swift build -c {{ config }} --show-bin-path)"
    rm -rf "{{ app }}"
    mkdir -p "{{ app }}/Contents/MacOS" "{{ app }}/Contents/Resources"
    cp "$bin_dir/Lines" "{{ app }}/Contents/MacOS/Lines"
    cp Support/Info.plist "{{ app }}/Contents/Info.plist"
    # SwiftPM resource bundles (the canvas page) go where Bundle.module looks first.
    for bundle in "$bin_dir"/*.bundle; do
      [ -e "$bundle" ] && cp -R "$bundle" "{{ app }}/Contents/Resources/"
    done
    cp build/icon/AppIcon.icns "{{ app }}/Contents/Resources/AppIcon.icns"
    [ -f build/icon/Assets.car ] && cp build/icon/Assets.car "{{ app }}/Contents/Resources/Assets.car"
    # Translations: the String Catalog compiles to <language>.lproj folders in
    # the app's own Resources, where SwiftUI looks them up. `just strings` refreshes it.
    if [ -f Support/Localizable.xcstrings ]; then
      xcrun xcstringstool compile Support/Localizable.xcstrings --output-directory "{{ app }}/Contents/Resources" >/dev/null
    fi
    # The version from VERSION; the build number counts commits.
    /usr/libexec/PlistBuddy \
      -c "Set :CFBundleShortVersionString {{ version }}" \
      -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" \
      "{{ app }}/Contents/Info.plist"
    # Extended attributes would travel in the zip as ._ files inside the
    # bundle, which Homebrew's unzip leaves there, breaking the signature.
    xattr -cr "{{ app }}"
    # Signed with a Developer ID (and the hardened runtime notarization needs)
    # when LINES_SIGN_IDENTITY names one; otherwise ad hoc, to run on this Mac.
    if [ -n "${LINES_SIGN_IDENTITY:-}" ]; then
      codesign --force --options runtime --timestamp --sign "$LINES_SIGN_IDENTITY" "{{ app }}"
    else
      codesign --force --sign - "{{ app }}"
    fi
    # Finder and the Dock cache icons by bundle; touching the bundle and
    # re-registering it makes them pick up a changed icon.
    touch "{{ app }}"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "{{ app }}" >/dev/null 2>&1 || true
    echo "Built {{ app }}"

# The app icon is an Icon Composer document. actool compiles it into Assets.car
# (Liquid Glass, dark and clear variants) plus a fallback AppIcon.icns. If actool
# can't run (Xcode's first-launch setup not done), ictool renders a static .icns.
# Compile the app icon into build/icon when it has changed
[private]
_icon:
    #!/usr/bin/env sh
    set -e
    icon=Support/AppIcon.icon
    assets=Support/Assets.xcassets  # AccentColor, matching the icon's orange
    if [ -f build/icon/AppIcon.icns ] && [ -z "$(find "$icon" "$assets" -newer build/icon/AppIcon.icns)" ]; then
      exit 0
    fi
    rm -rf build/icon
    mkdir -p build/icon
    if ! xcrun actool "$icon" "$assets" --compile build/icon --platform macosx \
        --minimum-deployment-target 27.0 --app-icon AppIcon --accent-color AccentColor \
        --output-partial-info-plist build/icon/partial.plist >/dev/null 2>build/icon/actool.log; then
      echo "actool failed (see build/icon/actool.log); rendering a static icon with ictool" >&2
      rm -f build/icon/Assets.car
      ictool="$DEVELOPER_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool"
      mkdir -p build/icon/AppIcon.iconset
      for size in 16 32 128 256 512; do
        for scale in 1 2; do
          suffix=""
          [ "$scale" = 2 ] && suffix="@2x"
          "$ictool" "$icon" --export-image --platform macOS --rendition Default \
            --width "$size" --height "$size" --scale "$scale" \
            --output-file "build/icon/AppIcon.iconset/icon_${size}x${size}${suffix}.png" >/dev/null
        done
      done
      iconutil -c icns build/icon/AppIcon.iconset -o build/icon/AppIcon.icns
    fi

# Build, sign, notarize and zip a release, and point the cask at it
release:
    #!/usr/bin/env sh
    set -e
    if [ -z "${LINES_SIGN_IDENTITY:-}" ] && [ -z "${LINES_ALLOW_UNSIGNED:-}" ]; then
      echo "Set LINES_SIGN_IDENTITY to a Developer ID Application identity (see RELEASING.md)." >&2
      echo "Homebrew disables casks that fail Gatekeeper; LINES_ALLOW_UNSIGNED=1 builds one anyway, for testing." >&2
      exit 1
    fi
    just rebuild release
    codesign --verify --strict --deep "{{ app }}"
    zip="build/Lines-{{ version }}.zip"
    rm -f "$zip"
    ditto -c -k --norsrc --noextattr --noacl --keepParent "{{ app }}" "$zip"
    if [ -n "${LINES_NOTARY_PROFILE:-}" ]; then
      xcrun notarytool submit "$zip" --keychain-profile "$LINES_NOTARY_PROFILE" --wait
      xcrun stapler staple "{{ app }}"
      spctl --assess --type execute --verbose "{{ app }}"
      # Zip again, so the download carries the stapled ticket.
      rm -f "$zip"
      ditto -c -k --norsrc --noextattr --noacl --keepParent "{{ app }}" "$zip"
    elif [ -n "${LINES_SIGN_IDENTITY:-}" ]; then
      echo "Not notarized: set LINES_NOTARY_PROFILE (see RELEASING.md)." >&2
    fi
    # Unpack as Homebrew does (unzip, not ditto) and check the signature survives.
    check="$(mktemp -d)"
    unzip -q "$zip" -d "$check"
    codesign --verify --strict "$check/Lines.app"
    rm -rf "$check"
    sha="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
    sed -i '' -E \
      -e "s/^  version \".*\"/  version \"{{ version }}\"/" \
      -e "s/^  sha256 .*/  sha256 \"$sha\"/" \
      Casks/lines.rb
    echo "Built $zip ($sha)"
    echo "Casks/lines.rb now points at {{ version }}. Next: just publish"

# Publish the release on GitHub and update the tap (run after `just release`)
publish:
    #!/usr/bin/env sh
    set -e
    zip="build/Lines-{{ version }}.zip"
    [ -f "$zip" ] || { echo "No $zip: run just release first." >&2; exit 1; }
    gh release create "v{{ version }}" "$zip" --repo "{{ github }}" --title "Lines {{ version }}" --generate-notes
    tapdir="$(mktemp -d)"
    gh repo clone "{{ tap }}" "$tapdir" -- --depth 1
    mkdir -p "$tapdir/Casks"
    cp Casks/lines.rb "$tapdir/Casks/lines.rb"
    git -C "$tapdir" add Casks/lines.rb
    git -C "$tapdir" commit -m "lines {{ version }}"
    git -C "$tapdir" push origin HEAD
    rm -rf "$tapdir"
    echo "Published. Install with: brew install --cask {{ replace(tap, "homebrew-", "") }}/lines"

# Check the cask's style and syntax with Homebrew's own rules
cask-check:
    brew style Casks/lines.rb

# Remove build products
clean:
    rm -rf build .build

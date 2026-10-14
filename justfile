# Lines — common tasks. `just` lists them.

app := "build/Lines.app"
bundle_id := "com.zms.Lines"

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
    ./build.sh {{ config }}
    rm -f build/.inputs-*  # one app bundle, so only the latest config is current
    echo "$current" > "$stamp"

# Build even if nothing has changed
rebuild config="release":
    rm -f build/.inputs-*
    @just build {{ config }}

# A hash of everything that goes into the app, plus the build configuration
[private]
_inputs-hash config:
    @{ echo "{{ config }}"; find Sources Support Vendor Package.swift Package.resolved build.sh \
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
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift-format format -i -r Sources/Lines

# Refresh Support/Localizable.xcstrings with every string the app shows
strings:
    #!/usr/bin/env sh
    set -e
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
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

# Remove build products
clean:
    rm -rf build .build

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

# Build build/Lines.app (release by default; `just build debug` for a debug build)
build config="release":
    @./build.sh {{ config }}

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

# Remove build products
clean:
    rm -rf build .build

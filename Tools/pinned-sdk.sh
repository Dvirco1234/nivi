#!/usr/bin/env bash
# Prints the macOS SDK to build against: the newest one the installed Swift toolchain
# can really compile SwiftUI with.
#
# The Command Line Tools ship several SDKs, and the newest is often ahead of the Swift
# toolchain next to it. When it is, every SwiftUI view fails with
# "plugin for module 'SwiftUIMacros' not found". Nothing in Nivi has changed when this
# happens. It hit on 16 September 2026, when an update repointed MacOSX.sdk at
# MacOSX27.0.sdk.
#
# The first fix picked the SDK matching the running macOS. That broke again on
# 26 October 2026: the Mac moved to macOS 27, so the rule chose MacOSX27.sdk, which the
# toolchain still could not use. So this no longer guesses from version numbers. It
# compiles a one-line SwiftUI view against each SDK, newest first, and keeps the first
# that works.
#
# The answer is cached in .build/pinned-sdk, keyed on the toolchain version and the list
# of SDKs, so the probe only runs again after a Command Line Tools update.
#
# The Makefile and every tool that runs swiftc itself read this, so the choice lives in
# one place. Set SDKROOT yourself to override.
set -euo pipefail
if [ -n "${SDKROOT:-}" ]; then echo "$SDKROOT"; exit 0; fi
cd "$(dirname "$0")/.."

sdk_dir=$(dirname "$(xcrun --show-sdk-path)")
# Real folders only, newest first. The short names (MacOSX.sdk, MacOSX27.sdk) are
# symlinks to these.
candidates=$(find "$sdk_dir" -maxdepth 1 -name 'MacOSX*.*.sdk' -type d | sort -V -r)

cache=.build/pinned-sdk
key="$(swiftc --version 2>&1 | head -1) | $(echo $candidates)"
if [ -f "$cache" ] && [ "$(head -1 "$cache")" = "$key" ]; then
    sed -n 2p "$cache"
    exit 0
fi

probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
printf 'import SwiftUI\nstruct Probe: View { @State var on = false\n var body: some View { Text("") } }\n' \
    > "$probe_dir/probe.swift"

for sdk in $candidates; do
    if swiftc -sdk "$sdk" -typecheck "$probe_dir/probe.swift" >/dev/null 2>&1; then
        mkdir -p .build
        printf '%s\n%s\n' "$key" "$sdk" > "$cache"
        echo "$sdk"
        exit 0
    fi
done

echo "pinned-sdk: no SDK in $sdk_dir can compile SwiftUI with this toolchain." >&2
xcrun --show-sdk-path

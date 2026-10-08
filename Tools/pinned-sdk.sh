#!/usr/bin/env bash
# Prints the macOS SDK to build against: the one matching the running system.
#
# The Command Line Tools ship SDKs for macOS versions this Mac is not running. An
# update on 16 September 2026 repointed the default MacOSX.sdk at MacOSX27.0.sdk, and
# the bundled Swift toolchain cannot use it: every SwiftUI view fails with
# "plugin for module 'SwiftUIMacros' not found". Nothing in Nivi had changed.
#
# The Makefile and every tool that runs swiftc itself read this, so the choice lives in
# one place. Set SDKROOT yourself to override.
set -euo pipefail
if [ -n "${SDKROOT:-}" ]; then echo "$SDKROOT"; exit 0; fi
major=$(sw_vers -productVersion | cut -d. -f1)
dir=$(dirname "$(xcrun --show-sdk-path)")
if [ -d "$dir/MacOSX$major.sdk" ]; then echo "$dir/MacOSX$major.sdk"; else xcrun --show-sdk-path; fi

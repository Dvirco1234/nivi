# The one place the version lives.
#
# VERSION is what people see: "0.1.0". CFBundleShortVersionString, the DMG file
# name, the git tag and the appcast entry all come from here.
#
# BUILD_NUMBER is a plain counter that only ever goes up. Sparkle compares builds
# with it, so it must never repeat and never go backwards, even if VERSION does.
# `make release` bumps it by one on every release. Do not edit it by hand.
#
# `make release VERSION=0.2.0` rewrites this file. You can also edit VERSION here
# and run `make release` with no argument.
VERSION := 0.1.0
BUILD_NUMBER := 1

#!/usr/bin/env bash
#
# Photographs Preferences tabs so a settings change can be checked by eye.
#
#   bash Tools/make-pref-shots.sh general speech
#   DEBUG_BUILD=1 bash Tools/make-pref-shots.sh sidebar   # as a `make dev` build looks
#
# The pictures land in .build/pref-shots/shots/<tab>.png. They are a developer aid, not
# something the app ships, so nothing is copied into Resources.
#
# It needs Screen Recording permission for the shell it runs from, and a logged-in
# desktop session. It never opens Dictato and never clicks anything.

set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR=.build/pref-shots
APP="$BUILD_DIR/PrefShots.app"
SHOT_DIR="$BUILD_DIR/shots"
TABS=("$@")
if [ ${#TABS[@]} -eq 0 ]; then TABS=(general speech); fi

# swiftc does not define DEBUG on its own, so by default this tool draws what the
# RELEASED app draws. Set DEBUG_BUILD=1 to see what `make dev` builds instead — that
# is the difference the developer-only tabs hang on.
CONFIG_FLAGS=(-O)
SUFFIX=""
if [ "${DEBUG_BUILD:-0}" = "1" ]; then
    CONFIG_FLAGS=(-Onone -D DEBUG)
    SUFFIX="-debug"
fi

# The app sources import Sparkle, so the tool has to link the same framework the bundle
# gets. `swift build` downloads and unpacks it.
SPARKLE_DIR=""
for candidate in .build/release .build/debug; do
    if [ -d "$candidate/Sparkle.framework" ]; then SPARKLE_DIR="$candidate"; break; fi
done
if [ -z "$SPARKLE_DIR" ]; then
    echo "Sparkle.framework not found. Run 'swift build' once first." >&2
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SHOT_DIR"

# Compiled with swiftc rather than added to Package.swift, the same way the overlay
# thumbnail tool is: only a developer ever runs it.
swiftc -O -emit-module -emit-library -static \
    -module-name DictatoCore \
    -emit-module-path "$BUILD_DIR/DictatoCore.swiftmodule" \
    -o "$BUILD_DIR/libDictatoCore.a" \
    Sources/DictatoCore/*.swift

# Every app source except main.swift, so the tool draws the real Preferences views. The
# whisper libraries come along because some of those files talk to the recognizer, even
# though this tool never asks one to run.
swiftc "${CONFIG_FLAGS[@]}" -I "$BUILD_DIR" -L "$BUILD_DIR" -lDictatoCore \
    -I Sources/CWhisper -Lvendor/lib -lwhisper -lggml -lc++ \
    -F "$SPARKLE_DIR" -framework Sparkle \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -framework Metal -framework MetalKit -framework Accelerate \
    -framework AVFoundation -framework AppKit \
    $(find Sources/Dictato -name '*.swift' ! -name 'main.swift') \
    Tools/pref-shots/main.swift \
    -o "$APP/Contents/MacOS/PrefShots" 2>&1 | grep -v "^ " | grep -v "warning:" || true

if [ ! -x "$APP/Contents/MacOS/PrefShots" ]; then
    echo "build failed" >&2
    exit 1
fi

# The views load images through Bundle.main, so the tool has to run from inside a bundle
# that carries them. A bare binary would draw fallback symbols instead.
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
cp Resources/MenuBarAleph.png Resources/MenuBarLatinA.png \
   Resources/DictatoLogo.png Resources/DictatoLogoEn.png \
   Resources/RecordingDisplayPanel.png Resources/RecordingDisplayNotch.png \
   "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>PrefShots</string>
    <key>CFBundleIdentifier</key><string>com.dvir.dictato.pref-shots</string>
    <key>CFBundleName</key><string>PrefShots</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

"$APP/Contents/MacOS/PrefShots" "$SHOT_DIR" "$SUFFIX" "${TABS[@]}"

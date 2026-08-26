#!/usr/bin/env bash
#
# Regenerates the two Recording display thumbnails in Preferences > General:
#   Resources/RecordingDisplayPanel.png
#   Resources/RecordingDisplayNotch.png
#
# Run it with:   bash Tools/make-recording-thumbnails.sh
#
# Re-run it whenever the recording overlays change how they look: OverlayView,
# NotchOverlayView, or any of the panel/notch numbers in UITuning.shipped. The
# thumbnails are photographs of the real overlays, so if you do not re-run this the
# picker keeps showing the old design and quietly lies to the user.
#
# How it works: Tools/overlay-thumbnails/main.swift puts the real overlay views on
# screen over a generated gradient, and `screencapture` photographs that patch of
# screen. It never records audio and never touches the desktop wallpaper.
#
# Two things it needs from the Mac it runs on:
#   * Screen Recording permission for whatever shell you run it from, otherwise
#     screencapture hands back a blank picture.
#   * A logged-in desktop session. It cannot run over ssh.
#
# Run it on a MacBook with a camera notch if you can. The notch thumbnail copies the
# real notch width from the display, and on a machine without one the bar collapses to
# a small tab.

set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR=.build/overlay-thumbnails
APP="$BUILD_DIR/OverlayThumbnails.app"
SHOT_DIR="$BUILD_DIR/shots"

rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SHOT_DIR"

# Compiled straight with swiftc, the same way Tools/run-core-tests.sh does, rather than
# adding a second product to Package.swift for something only a developer ever runs.
# NiviCore is built first as its own module because the overlay sources import it by
# name, exactly as they do inside the app.
swiftc -O -emit-module -emit-library -static \
    -module-name NiviCore \
    -emit-module-path "$BUILD_DIR/NiviCore.swiftmodule" \
    -o "$BUILD_DIR/libNiviCore.a" \
    Sources/NiviCore/*.swift

swiftc -O -I "$BUILD_DIR" -L "$BUILD_DIR" -lNiviCore \
    Sources/Nivi/UITuning.swift \
    Sources/Nivi/LanguageGlyph.swift \
    Sources/Nivi/Overlay/*.swift \
    Tools/overlay-thumbnails/main.swift \
    -o "$APP/Contents/MacOS/OverlayThumbnails"

# The overlays load the language glyph through Bundle.main, so the tool has to run from
# inside an app bundle that carries those PNGs. A bare binary would draw the fallback
# symbol instead and the thumbnail would not match the app.
cp Resources/MenuBarAleph.png Resources/MenuBarLatinA.png \
   Resources/NiviLogo.png Resources/NiviLogoEn.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OverlayThumbnails</string>
    <key>CFBundleIdentifier</key><string>com.dvir.nivi.overlay-thumbnails</string>
    <key>CFBundleName</key><string>OverlayThumbnails</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

"$APP/Contents/MacOS/OverlayThumbnails" "$SHOT_DIR"

# The stage is photographed three times the size the thumbnail is shown at, on a Retina
# screen, so shrinking to 264x164 leaves a clean 2x image for the 132x82 point picker.
for name in RecordingDisplayPanel RecordingDisplayNotch; do
    src="$SHOT_DIR/$name.png"
    if [ ! -f "$src" ]; then
        echo "Missing $src — did screencapture have permission?" >&2
        exit 1
    fi
    sips -z 164 264 "$src" --out "Resources/$name.png" >/dev/null
    echo "Wrote Resources/$name.png"
done

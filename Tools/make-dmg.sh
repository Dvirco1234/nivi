#!/usr/bin/env bash
# Packs the signed .app into one downloadable disk image.
#
# The image holds the app and a shortcut to /Applications, so installing is one
# drag. hdiutil ships with macOS, so this needs no Xcode.
#
# Deliberately does NOT script Finder to place icons or set a background. Doing
# that means opening a Finder window on whoever is building, which hijacks the
# machine. The window still opens at a sensible size because the image is small
# and holds exactly two items, and the volume gets its own icon.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${APP_NAME:?}" "${VERSION:?}" "${APP_BUNDLE:?}" "${OUT:?}" "${SIGN_ID:?}"

STAGING="build/dmg-staging"
rm -rf "$STAGING" "$OUT"
mkdir -p "$STAGING" "$(dirname "$OUT")"

cp -R "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# Gives the mounted disk its own icon instead of the plain grey drive.
cp "Resources/Dictato.icns" "$STAGING/.VolumeIcon.icns"
SetFile -a C "$STAGING" 2>/dev/null || echo "  (could not set the custom volume icon flag; the image still works)"

hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING" \
    -ov -quiet \
    -format UDZO \
    -fs HFS+ \
    "$OUT"

rm -rf "$STAGING"

# Signing the image itself is what lets it be notarized later, and it means a
# tampered download fails before it is ever opened.
codesign --force --sign "$SIGN_ID" "$OUT"

SIZE=$(du -h "$OUT" | cut -f1 | tr -d ' ')
echo "Packed $OUT ($SIZE)"

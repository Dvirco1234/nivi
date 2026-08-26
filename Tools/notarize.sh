#!/usr/bin/env bash
# Asks Apple to check the app, so it opens on any Mac without a warning.
#
# This needs a paid Apple Developer account and a "Developer ID Application"
# certificate. Until then the release is self-signed, which works but shows a
# warning on first launch (see INSTALL.md). This script therefore SKIPS itself
# when the credentials are absent, rather than failing the release.
#
# To switch notarizing on, export these three and re-run `make release`:
#   APPLE_ID           the Apple account email
#   APPLE_TEAM_ID      the 10-character team id from developer.apple.com
#   APPLE_APP_PASSWORD an app-specific password from appleid.apple.com
# and set SIGN_ID to your "Developer ID Application: ..." identity, because Apple
# will not notarize anything signed with a self-signed certificate.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${APP_BUNDLE:?}" "${DMG:?}" "${SIGN_ID:?}"

if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ] || [ -z "${APPLE_APP_PASSWORD:-}" ]; then
    echo "Notarizing: skipped. APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD are not all set."
    echo "            The release is self-signed, so first launch shows a warning. See INSTALL.md."
    exit 0
fi

case "$SIGN_ID" in
    "Developer ID Application"*) ;;
    *)
        echo "Notarizing: skipped. SIGN_ID is '$SIGN_ID'."
        echo "            Apple only notarizes builds signed with a Developer ID Application certificate."
        exit 0
        ;;
esac

# Apple requires the hardened runtime and a trusted timestamp. The app is signed
# again here so the everyday `make dev` build keeps its simpler signature and
# nothing about local development changes.
echo "Notarizing: re-signing with the hardened runtime…"
codesign --force --deep --options runtime --timestamp \
    --entitlements Resources/Dictato.entitlements \
    --sign "$SIGN_ID" "$APP_BUNDLE"
codesign --force --sign "$SIGN_ID" "$DMG"

echo "Notarizing: uploading $DMG to Apple. This usually takes a few minutes."
xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

# Stapling writes Apple's approval into the file, so it opens even offline.
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Notarizing: done. This build opens with no warning."

#!/usr/bin/env bash
# Builds the update feed Sparkle reads.
#
# The feed ("appcast") is one XML file listing every version, where to download
# it, how big it is, and a signature proving it came from us. Sparkle refuses an
# update whose signature does not match the public key in Info.plist.
#
# The signing key is the EdDSA private key in the login keychain. Sparkle's
# generate_appcast finds it there by itself. That key is NOT in this repo and
# must never be. Losing it means existing installs can no longer verify updates.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${APP_NAME:?}" "${VERSION:?}" "${DMG:?}" "${APPCAST_DIR:?}" "${APPCAST_URL:?}" \
  "${DOWNLOAD_PREFIX:?}" "${SPARKLE_BIN:?}"

if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "Sparkle's tools are missing. Run 'swift build' once to download them." >&2
    exit 1
fi

mkdir -p "$APPCAST_DIR"

# Start from the feed that is actually live, so an entry is never lost because
# this Mac had a stale copy.
if curl -fsSL --max-time 20 "$APPCAST_URL" -o "$APPCAST_DIR/appcast.xml.live" 2>/dev/null; then
    mv "$APPCAST_DIR/appcast.xml.live" "$APPCAST_DIR/appcast.xml"
    echo "Feed: started from the live one at $APPCAST_URL"
else
    rm -f "$APPCAST_DIR/appcast.xml.live"
    echo "Feed: could not read $APPCAST_URL, using the local copy (or starting a new feed)"
fi

# generate_appcast reads whatever archives sit in this directory. Only the new
# one should be here: older entries are carried over from the existing feed, and
# leaving old DMGs around would make it re-download and re-hash all of them.
find "$APPCAST_DIR" -maxdepth 1 -name '*.dmg' -delete
cp "$DMG" "$APPCAST_DIR/"
DMG_NAME=$(basename "$DMG")
NOTES_NAME="${DMG_NAME%.dmg}.md"

# Release notes: a file per version, written by hand. Sparkle shows these in the
# update window. Without one the user sees an empty update dialog.
if [ -f "release-notes/$VERSION.md" ]; then
    cp "release-notes/$VERSION.md" "$APPCAST_DIR/$NOTES_NAME"
else
    echo "Notes: release-notes/$VERSION.md is missing, writing a placeholder."
    mkdir -p release-notes
    printf '## %s %s\n\nSee the commit history for what changed.\n' "$APP_NAME" "$VERSION" \
        > "release-notes/$VERSION.md"
    cp "release-notes/$VERSION.md" "$APPCAST_DIR/$NOTES_NAME"
fi

"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --embed-release-notes \
    "$APPCAST_DIR"

# The DMG is served from GitHub Releases, not from the feed's own folder, so it
# does not need to be kept or published here.
rm -f "$APPCAST_DIR/$DMG_NAME"

xmllint --noout "$APPCAST_DIR/appcast.xml"
echo "Feed: $APPCAST_DIR/appcast.xml now lists $VERSION"

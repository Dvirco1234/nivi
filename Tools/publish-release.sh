#!/usr/bin/env bash
# Puts the release somewhere a stranger's Mac can reach it.
#
# Why a second repo: the source repo is private. Sparkle asks for the feed and
# the DMG over plain HTTPS with no login, and a private repo answers 404. So a
# separate PUBLIC repo carries only the released files. No source goes into it.
#
#   appcast.xml + index.html  -> GitHub Pages  (the feed and the download page)
#   the .dmg                  -> GitHub Releases (the actual download)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${APP_NAME:?}" "${VERSION:?}" "${DMG:?}" "${RELEASES_SLUG:?}" "${APPCAST_DIR:?}" "${PAGES_URL:?}"

TAG="v$VERSION"
CHECKOUT="build/releases-repo"

if ! gh repo view "$RELEASES_SLUG" >/dev/null 2>&1; then
    ACTIVE=$(gh api user --jq .login 2>/dev/null || echo "unknown")
    cat <<EOF

The public releases repo $RELEASES_SLUG does not exist yet (or the logged-in
GitHub account cannot see it). gh is currently signed in as: $ACTIVE

Create it once, from the account that owns the private repo:

  gh repo create $RELEASES_SLUG --public --description "Downloads and update feed for $APP_NAME" --add-readme

Then turn on GitHub Pages for it:

  gh api -X POST repos/$RELEASES_SLUG/pages -f 'source[branch]=main' -f 'source[path]=/'

Then run 'make release' again.
EOF
    exit 1
fi

if [ ! -d "$CHECKOUT/.git" ]; then
    rm -rf "$CHECKOUT"
    gh repo clone "$RELEASES_SLUG" "$CHECKOUT" -- --quiet
else
    git -C "$CHECKOUT" fetch --quiet origin
    git -C "$CHECKOUT" reset --quiet --hard origin/HEAD
fi

cp "$APPCAST_DIR/appcast.xml" "$CHECKOUT/appcast.xml"
mkdir -p "$CHECKOUT/release-notes"
cp "release-notes/$VERSION.md" "$CHECKOUT/release-notes/$VERSION.md"
cp INSTALL.md "$CHECKOUT/INSTALL.md"
APP_NAME="$APP_NAME" VERSION="$VERSION" RELEASES_SLUG="$RELEASES_SLUG" TAG="$TAG" \
    bash Tools/make-download-page.sh > "$CHECKOUT/index.html"

# The feed has to be live before the release notes link out to it, but the DMG has
# to exist before the feed points at it. Upload the DMG first.
gh release create "$TAG" "$DMG" \
    --repo "$RELEASES_SLUG" \
    --title "$APP_NAME $VERSION" \
    --notes-file "release-notes/$VERSION.md"

git -C "$CHECKOUT" add -A
git -C "$CHECKOUT" commit -m "$APP_NAME $VERSION" --quiet
git -C "$CHECKOUT" push --quiet

echo "Published $APP_NAME $VERSION"
echo "  download page: $PAGES_URL"
echo "  update feed:   $PAGES_URL/appcast.xml"

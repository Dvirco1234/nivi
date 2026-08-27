#!/usr/bin/env bash
# Puts the release somewhere a stranger's Mac can reach it.
#
# Everything goes into this one public repo:
#
#   docs/appcast.xml + docs/index.html  -> GitHub Pages (the feed and the download page)
#   the .dmg                            -> GitHub Releases (the actual download)
#
# This script only uploads and writes files. `make release` does the committing, so a
# failed upload leaves no commit and no tag to unpick before trying again.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${APP_NAME:?}" "${VERSION:?}" "${DMG:?}" "${REPO_SLUG:?}" "${APPCAST_DIR:?}" \
  "${PAGES_DIR:?}" "${PAGES_URL:?}"

TAG="v$VERSION"

# The GitHub API token.
#
# `gh` may well be logged in as a work account that has nothing to do with this repo,
# and it would then upload to the wrong place or just fail. So a token stored in the
# login keychain wins over whatever `gh` is logged in as. Store it once with:
#
#   security add-generic-password -a nivi-release -s nivi-gh-token -w <token>
#
# The token needs the `repo` scope. Without one, `gh`'s own login is used, which is
# fine if that login owns the repo.
if [ -z "${GH_TOKEN:-}" ]; then
    KEYCHAIN_TOKEN=$(security find-generic-password -a nivi-release -s nivi-gh-token -w 2>/dev/null || true)
    if [ -n "$KEYCHAIN_TOKEN" ]; then
        export GH_TOKEN="$KEYCHAIN_TOKEN"
        echo "Auth: using the nivi-gh-token from the login keychain."
    else
        echo "Auth: no nivi-gh-token in the keychain, using whatever gh is logged in as."
    fi
fi

if ! gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
    ACTIVE=$(gh api user --jq .login 2>/dev/null || echo "unknown")
    cat <<EOF

Cannot see $REPO_SLUG. The account in use is: $ACTIVE

Either the repo has not been renamed and made public yet, or this account cannot
reach it. See docs/release-pipeline.md for the one-time setup.
EOF
    exit 1
fi

# The download page and the feed are plain files in the repo. GitHub Pages serves the
# docs folder as the site root, so writing them here is the whole of "publishing" them.
mkdir -p "$PAGES_DIR"
cp "$APPCAST_DIR/appcast.xml" "$PAGES_DIR/appcast.xml"
APP_NAME="$APP_NAME" VERSION="$VERSION" REPO_SLUG="$REPO_SLUG" TAG="$TAG" \
    bash Tools/make-download-page.sh > "$PAGES_DIR/index.html"

# The DMG lives in Releases rather than in the repo, because a disk image committed to
# git history is dead weight that can never be removed.
#
# If the release already exists, this is a retry after something failed further on, so
# replace the asset instead of stopping.
if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
    echo "Release $TAG already exists, replacing the DMG."
    gh release upload "$TAG" "$DMG" --repo "$REPO_SLUG" --clobber
else
    gh release create "$TAG" "$DMG" \
        --repo "$REPO_SLUG" \
        --title "$APP_NAME $VERSION" \
        --notes-file "release-notes/$VERSION.md"
fi

echo "Uploaded $APP_NAME $VERSION"
echo "  download page: $PAGES_URL"
echo "  update feed:   $PAGES_URL/appcast.xml"

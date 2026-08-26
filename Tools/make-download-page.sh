#!/usr/bin/env bash
# Writes the one-page website people are sent to in order to download the app.
set -euo pipefail
: "${APP_NAME:?}" "${VERSION:?}" "${RELEASES_SLUG:?}" "${TAG:?}"
cat <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$APP_NAME $VERSION</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 16px/1.6 -apple-system, system-ui, sans-serif; max-width: 40rem;
         margin: 4rem auto; padding: 0 1.5rem; }
  h1 { font-size: 2rem; margin-bottom: 0; }
  .version { color: #888; margin-top: .25rem; }
  a.download { display: inline-block; margin: 2rem 0; padding: .8rem 1.6rem;
               background: #0a84ff; color: #fff; border-radius: .6rem;
               text-decoration: none; font-weight: 600; }
  .note { background: rgba(128,128,128,.12); padding: 1rem 1.25rem; border-radius: .6rem; }
</style>
</head>
<body>
  <h1>$APP_NAME</h1>
  <p class="version">Version $VERSION &middot; macOS 14 or newer &middot; Apple Silicon</p>
  <a class="download" href="https://github.com/$RELEASES_SLUG/releases/download/$TAG/$APP_NAME-$VERSION.dmg">Download $APP_NAME $VERSION</a>
  <div class="note">
    <p><strong>First launch shows a warning.</strong> macOS says the app cannot be
    checked, because it is signed by its author rather than by Apple. This is
    expected. <a href="INSTALL.md">How to open it anyway</a> &mdash; it takes about
    fifteen seconds, once.</p>
  </div>
  <p>After that, $APP_NAME updates itself. It asks before installing anything.</p>
  <p><a href="https://github.com/$RELEASES_SLUG/releases">All versions</a></p>
</body>
</html>
EOF

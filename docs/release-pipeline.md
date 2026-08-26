# Making a release

One command:

```
make release VERSION=0.2.0
```

That does all of this, in order:

1. Refuses to run if the working tree is dirty or the tag already exists.
2. Writes the new version into `version.mk` and bumps the build counter.
3. Builds the release binary and assembles the signed `.app`.
4. Packs `dist/Dictato-<version>.dmg`.
5. Notarizes, if Apple credentials are set. Skips with a message if not.
6. Adds the version to the Sparkle update feed, signed with the EdDSA key.
7. Commits, tags `v<version>`.
8. Uploads the DMG to the public releases repo and pushes the feed.
9. Pushes the source repo and the tag.

To build a release without publishing anything, run `make dist`. Nothing in it
touches git or the network except the notarizing step.

## The version lives in one place

`version.mk` is the only file that carries a version number.

- `VERSION` is what people read: `0.2.0`. It becomes
  `CFBundleShortVersionString`, the string in the Preferences sidebar, the DMG
  file name, the disk image's volume name, the git tag `v0.2.0`, the GitHub
  release title and the appcast entry.
- `BUILD_NUMBER` is a plain counter: 1, 2, 3. It becomes `CFBundleVersion`.

**Why two numbers.** Sparkle decides "is this newer" by comparing
`CFBundleVersion`, not the human version. So `CFBundleVersion` has to only ever
go up, and never repeat. A counter does that with no thought required, and it
stays correct even if you ever release `0.2.0` after `0.10.0`, or re-cut a
version. `make release` bumps it by one every time; never edit it by hand.

`Resources/Info.plist` holds placeholders for everything the build fills in. The
Makefile rewrites those keys with `plutil` when it assembles the bundle, so
there is no second copy of the version anywhere to drift.

## The signing key you must back up

Sparkle proves an update really came from us with an EdDSA key pair.

- The **public** half is in the `Makefile` as `SPARKLE_PUBLIC_KEY` and gets
  written into each build's `Info.plist` as `SUPublicEDKey`. Public, safe to
  commit, safe to share.
- The **private** half lives in the macOS login keychain, under the item
  **"Private key for signing Sparkle updates"**. It is not in this repo and must
  never be committed.

**Back it up now.** Every copy of Dictato already installed carries the public
key baked into it. Those copies will only accept an update signed by the
matching private key. If the key is lost, no existing install can ever be
updated again — you would have to ask every user to download the new version by
hand. Losing the Mac loses the key.

Export it to a file and put that file somewhere safe (a password manager entry
is ideal):

```
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Desktop/sparkle-private-key.txt
```

Delete the file from the Desktop afterwards. To restore it on a new Mac:

```
.build/artifacts/sparkle/Sparkle/bin/generate_keys -f /path/to/sparkle-private-key.txt
```

## Where releases are hosted, and why

The source repo is private, and it is staying private. Sparkle asks for the feed
and the DMG over plain HTTPS with no login, so a private repo answers 404 and
updating silently never works.

So releases go to a **separate public repo** that holds no source:

| File | Where | Served from |
|---|---|---|
| `appcast.xml` (the update feed) | `Dvirco1234/dictato-releases`, main branch | GitHub Pages |
| `index.html` (the download page) | same | GitHub Pages |
| `Dictato-<version>.dmg` | same repo, Releases | GitHub Releases |

The DMG goes to Releases rather than into the repo because a disk image in git
history is dead weight that can never be removed.

`Tools/publish-release.sh` checks the repo exists and prints the exact commands
if it does not.

## Release notes

Write `release-notes/<version>.md` before releasing. Sparkle shows it in the
update window, and it becomes the GitHub release body. If the file is missing,
the release still works but users see a placeholder.

## Notarizing later

Notarizing is Apple scanning the app and vouching for it, which removes the
warning on first launch (see `INSTALL.md`). It needs a paid Apple Developer
account.

When you have one, nothing in this pipeline changes shape. Export three
variables and run the same command:

```
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="ABCDE12345"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
make release VERSION=0.3.0
```

You also have to change `SIGN_ID` in the Makefile to your
`Developer ID Application: ...` identity, because Apple will not notarize
anything signed with a self-signed certificate. `Tools/notarize.sh` checks for
that and skips with an explanation rather than failing.

Note that switching the signing identity resets the app's macOS permissions
once, because macOS ties Accessibility and Microphone grants to the identity.
Expect to grant them again after the first notarized build.

## The developer-only tabs

The **Layout** and **Debug** tabs in Preferences are tools for whoever builds the
app: live layout sliders, inference timings, verbose logging, the log folder
path. Someone who downloads Dictato never sees them.

They appear in a debug build, which is what `make dev` makes, and are absent from
the release build that goes into the DMG. `DeveloperMode` in
`Sources/Dictato/DeveloperMode.swift` is the switch, and it uses `#if DEBUG`,
which SwiftPM defines for `swift build -c debug` and not for `-c release`.

To get them back in a released build you are running yourself:

```
defaults write com.dvir.dictato showDeveloperTabs -bool true
```

Then quit and reopen Dictato. Turn it off again with `defaults delete
com.dvir.dictato showDeveloperTabs`. Nothing in the UI mentions this.

Two related things the released build also does:

- **It ignores `ui-tuning.conf` completely** and uses the numbers compiled into
  `UITuning.shipped`. The file is written once and never updated afterwards, so
  on a stranger's Mac it would quietly pin the layout to whatever the numbers
  were the day they first ran the app — and a later layout fix would reach
  nobody. With the escape hatch on, the file works as before.
- **It forces verbose logging off at launch.** Verbose logging writes a line for
  every global keystroke, and with the Debug tab hidden there is no visible
  switch to turn it back off.

## Renaming the app later

The name and the bundle id come from two lines at the top of the `Makefile`:

```
APP_NAME  := Dictato
BUNDLE_ID := com.dvir.dictato
```

Everything downstream reads from them: the bundle folder name, the executable
name, the icon name inside the bundle, the DMG file name, the disk volume name,
the signing identity (`<name> Self-Signed`), the appcast title and the GitHub
release title.

To rename:

1. Change `APP_NAME` and `BUNDLE_ID` in the `Makefile`.
2. Run `make cert` to mint a `<NewName> Self-Signed` identity.
3. Rename the resource files that carry the old name:
   `Resources/Dictato.icns`, `Resources/DictatoLogo.png`,
   `Resources/DictatoLogoEn.png` — and the `LanguageGlyph.image(named:)` calls
   that load them.
4. Change the user-visible strings in the UI (the sidebar brand text, the
   "Quit Dictato" menu item, the microphone permission sentence in
   `Resources/Info.plist`).
5. Update `RELEASES_REPO` if you want a differently named releases repo, and
   create it.
6. Rewrite `INSTALL.md` and `README.md`.

**Do this before the first public release if you are going to do it at all.**
Changing `BUNDLE_ID` after people have installed the app strands them: macOS and
Sparkle treat the renamed app as a completely different program, so nobody who
installed the old one ever gets an update, and both versions sit in
`/Applications` at once. There is no clean fix for that after the fact.

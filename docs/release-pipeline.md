# Making a release

One command:

```
make release VERSION=0.2.0
```

That does all of this, in order:

1. Refuses to run if the working tree is dirty or the tag already exists.
2. Writes the new version into `version.mk` and bumps the build counter.
3. Builds the release binary and assembles the signed `.app`.
4. Packs `dist/Nivi-<version>.dmg`.
5. Notarizes, if Apple credentials are set. Skips with a message if not.
6. Adds the version to the Sparkle update feed, signed with the EdDSA key.
7. Uploads the DMG as a GitHub Release asset, and writes the new
   `docs/appcast.xml` and `docs/index.html`.
8. Commits, tags `v<version>`, and pushes both.

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

**Back it up now.** Every copy of Nivi already installed carries the public
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

Everything lives in this one public repo. Sparkle asks for the feed and the DMG
over plain HTTPS with no login, and a public repo answers both.

| File | Where | Served from |
|---|---|---|
| `appcast.xml` (the update feed) | `docs/appcast.xml`, committed on `main` | GitHub Pages |
| `index.html` (the download page) | `docs/index.html`, committed on `main` | GitHub Pages |
| `Nivi-<version>.dmg` | this repo, Releases | GitHub Releases |

GitHub Pages is set to serve the `docs` folder, and Pages treats that folder as
the site root. So the two addresses are:

```
https://dvirco1234.github.io/nivi/            the download page
https://dvirco1234.github.io/nivi/appcast.xml the update feed
```

That second address is what the Makefile writes into every build's `Info.plist`
as `SUFeedURL`. It comes from `PAGES_URL` and `APPCAST_URL` at the top of the
`Makefile`, so there is no second copy to drift.

The DMG goes to Releases rather than into the repo because a disk image in git
history is dead weight that can never be removed.

`docs/.nojekyll` stops GitHub from running the folder through Jekyll. The folder
also holds the project's design notes and research, and Jekyll would try to turn
every one of those files into a page, and could fail on one of them.

## Which GitHub account uploads

`gh` on this Mac is logged in as a work account, and this repo belongs to a
personal one. So `Tools/publish-release.sh` looks for a token in the login
keychain first, and only falls back to `gh`'s own login:

```
security find-generic-password -a nivi-release -s nivi-gh-token -w
```

Store it once, with a personal access token that has the `repo` scope:

```
security add-generic-password -a nivi-release -s nivi-gh-token -w <token>
```

Only the API calls need this. Pushing commits and tags goes over SSH through the
`github.com-private` host alias, which already authenticates as the right
account.

## One-time setup, in the browser

Do all of this once, before the first release.

1. **Rename the repo.** Go to
   `https://github.com/Dvirco1234/dictato/settings`, and under **General >
   Repository name** change `dictato` to `nivi`. Click **Rename**.
2. **Make it public.** Same settings page, scroll to **Danger Zone >
   Change repository visibility**, choose **Make public**, and confirm.
3. **Turn on GitHub Pages.** Go to
   `https://github.com/Dvirco1234/nivi/settings/pages`. Under **Build and
   deployment**:
   - **Source:** `Deploy from a branch`
   - **Branch:** `main`
   - **Folder:** `/docs`

   Click **Save**. The first build takes a minute or two.
4. **Point the local clone at the new name.** GitHub redirects the old address,
   but leaving it stale is asking for confusion later:

   ```
   git remote set-url origin git@github.com-private:Dvirco1234/nivi.git
   ```

5. **Store the release token**, as described above, if it is not stored already.

After the first `make release`, check the feed really is being served:

```
curl -I https://dvirco1234.github.io/nivi/appcast.xml
```

A `200` means updates work. A `404` means Pages is off, or is pointed at the
wrong branch or folder.

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
path. Someone who downloads Nivi never sees them.

They appear in a debug build, which is what `make dev` makes, and are absent from
the release build that goes into the DMG. `DeveloperMode` in
`Sources/Nivi/DeveloperMode.swift` is the switch, and it uses `#if DEBUG`,
which SwiftPM defines for `swift build -c debug` and not for `-c release`.

To get them back in a released build you are running yourself:

```
defaults write com.dvir.nivi showDeveloperTabs -bool true
```

Then quit and reopen Nivi. Turn it off again with `defaults delete
com.dvir.nivi showDeveloperTabs`. Nothing in the UI mentions this.

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
APP_NAME  := Nivi
BUNDLE_ID := com.dvir.nivi
```

Everything downstream reads from them: the bundle folder name, the executable
name, the icon name inside the bundle, the DMG file name, the disk volume name,
the signing identity (`<name> Self-Signed`), the appcast title and the GitHub
release title.

To rename:

1. Change `APP_NAME` and `BUNDLE_ID` in the `Makefile`, and `REPO_NAME` if the
   GitHub repo is being renamed too. Renaming the repo changes the Pages address,
   so every already-installed copy stops finding the feed. Leave `REPO_NAME` alone
   unless you are ready for that.
2. Run `make cert` to mint a `<NewName> Self-Signed` identity.
3. Rename the Swift targets and their folders — `Sources/<Name>`,
   `Sources/<Name>Core`, `Tests/<Name>CoreTests` — and the target names in
   `Package.swift`. `Tools/run-core-tests.sh`, `Tools/make-pref-shots.sh` and
   `Tools/make-recording-thumbnails.sh` compile those folders by path, so they
   have to follow.
4. Rename the resource files that carry the old name: `Resources/<Name>.icns`,
   `<Name>Logo.png`, `<Name>LogoEn.png`, `<Name>.entitlements` — and the
   `LanguageGlyph.image(named:)` calls, `Tools/make-iconset.sh`,
   `Tools/make-dmg.sh` and `Tools/notarize.sh` that name them.
5. Change the user-visible strings: the sidebar brand text, the "Quit <Name>"
   menu item, the window title, the overlay mark, the error messages that name
   the app, and the microphone permission sentence in `Resources/Info.plist`.
6. Change the paths and identifiers keyed to the name: the log folder and log
   file in `Sources/<Name>/Log.swift`, the Application Support folder in
   `ModelPaths.appSupportBase()`, the `os.Logger` subsystem, the dispatch queue
   labels, the `NSError` domains and the `Notification.Name` constants.
7. Write the one-time migration for existing installs — see below — and cover it
   in `Tools/core-tests/main.swift`.
8. Rewrite `INSTALL.md` and `README.md`, and fix any example that names the app
   in the project's own notes.

Then `make cert`, `make dev`, and check the result really is the new app:

```sh
codesign -dvvv /Applications/<Name>.app 2>&1 | grep -E "Authority|Identifier"
bash Tools/run-core-tests.sh
```

### Bringing an existing install across

The bundle id decides where macOS keeps the settings, and the app name decides
where the app keeps its files. Rename either and the app opens looking brand
new, with no profiles, no hotkeys, and a 1.6 GB model to download that is
already on the disk.

`Sources/<Name>Core/LegacyNameMigration.swift` handles both, once, at the top of
`main.swift` before anything reads either place:

- the old defaults domain is copied key by key into the new one, skipping keys
  already set under the new name, with a marker so it never runs twice.
- `~/Library/Application Support/<OldName>` is **renamed** to the new name. A
  rename inside one disk is a single step, so the folder is either at the old
  name or the new one and never half at each. Copying gigabytes of model files
  and deleting afterwards could be interrupted and leave a truncated model.

Logs are not migrated. They are diagnostic, they rotate anyway, and the old
folder can simply be deleted.

Permissions cannot be migrated at all. macOS ties Accessibility, Input
Monitoring and Microphone to the signing identity, and a renamed app has a new
one, so the user grants all three again and deletes the old app.

**Do this before the first public release if you are going to do it at all.**
Changing `BUNDLE_ID` after people have installed the app strands them: macOS and
Sparkle treat the renamed app as a completely different program, so nobody who
installed the old one ever gets an update, and both versions sit in
`/Applications` at once. There is no clean fix for that after the fact.

# Working on Nivi

Nivi is an offline dictation app for macOS. You hold a hotkey, you speak, and the
text lands in whatever app you were already typing in. Everything runs on the
machine, using Whisper models through whisper.cpp.

This file is for someone working ON the app. For what the app does and how to
install it, read [README.md](README.md).

Three more docs to read before you change anything:

- [docs/state-of-the-project.md](docs/state-of-the-project.md) is where things
  stand today: what is built, what is released, what is broken, what is untested.
- [docs/architecture.md](docs/architecture.md) is how the code fits together: the
  path a dictation takes, the state machine, how streaming works, the invariants
  a change must not break, and how to add a setting or a test.
- [docs/decisions.md](docs/decisions.md) is what has already been settled and why.
  Read it before you redo something on purpose.

The design notes under `docs/superpowers/` are history. They stop in early August
and some of what they describe changed during implementation. See the README in
that folder.

## Build rules, all of them hard

**Build only with `make dev` or `make app`.** A bare `swift build` refreshes
`.build/debug/Nivi` but leaves the copy inside the app bundle untouched, so the
app you launch is the one you built last time. You will change code, see no
change, and start fixing code that was never broken.

**Never sign ad-hoc. Never use `ALLOW_ADHOC=1`.** macOS ties Accessibility, Input
Monitoring and Microphone permission to the app's signing identity. Ad-hoc
signing mints a new identity on every build, so macOS treats each build as a new
app and drops all three grants. The app still launches. It just quietly stops
pasting, stops seeing the hotkey, and asks for the microphone again. Always sign
with the stable `Nivi Self-Signed` identity, which `make cert` creates once.

**Tests must pass.** `bash Tools/run-core-tests.sh` prints
`ALL CORE CHECKS PASSED`. Run it before you commit.

**Signing happens outside iCloud Drive, and it must stay that way.** This repo
lives in iCloud Drive (see the layout note below). iCloud's file provider keeps
stamping folders with a `com.apple.FinderInfo` extended attribute, and `codesign`
refuses to sign anything carrying one:
`resource fork, Finder information, or similar detritus not allowed`. It
re-stamps faster than `xattr -c` can clear it, so signing in place fails at
random. The Makefile therefore assembles and signs the bundle in a scratch folder
under `TMPDIR` (`STAGE_DIR`) and copies the signed result into `build/`. It looks
like a pointless detour. It is not. Simplifying it back to signing in place
breaks the build in a way that looks random and wastes a session.

## Never drive the UI with synthetic input

The developer uses the same Mac you are testing on. Synthetic clicks and
keystrokes go to whatever is focused, not to this app.

This has already gone wrong twice on this project. One agent sent a synthetic
`Cmd-,` to open Preferences, which tripped the app's own modifier-tap dictation
hotkey and recorded the room. Another started a real dictation from the menu bar,
recorded 102 seconds and pasted 249 characters into whatever app happened to be
in front.

So: no `osascript` keystrokes, no `CGEvent` posting, no `cliclick`, no
Accessibility-API button presses, and never trigger a real dictation.

To check something visually, use the harnesses that compile the real views and
photograph them without opening or driving the running app:

```sh
bash Tools/make-pref-shots.sh general speech    # Preferences tabs
bash Tools/make-recording-thumbnails.sh         # the two recording displays
```

`screencapture` is always safe; it reads pixels and touches no input. The full
rules are in the skill, under "Never drive the UI with synthetic input".

## The skill

`~/.claude/skills/macos-app-dev/` is installed globally and applies to this repo.
It is the reference for building without Xcode, signing, diagnosing permissions,
recovering when `codesign` hangs or returns `errSecInternalComponent`, and
verifying UI safely. Read it before hand-rolling a build or guessing at a
permissions problem.

## Layout

| Path | What is in it |
|---|---|
| `Sources/Nivi/` | The app: AppKit, SwiftUI, AVFoundation, everything that touches the system |
| `Sources/NiviCore/` | Pure logic, Foundation only. Testable without a running app |
| `Sources/CWhisper/` | A small shim over the vendored whisper.cpp static libraries |
| `Tools/` | Build scripts, the test harness, and the screenshot harnesses |
| `docs/` | Design specs, research notes, and the two docs named above |
| `vendor/whisper.cpp` | Git submodule, pinned to v1.7.2. `make vendor` builds it |

**The directory is still named `dictato`, and the app is Nivi.** The rename in
August 2026 changed the app, the bundle id and the GitHub repo, but not the
folder on disk. The remote is `Dvirco1234/nivi`. You are in the right repo.

**`~/personal` is a symlink** to
`/Users/dvir/Library/Mobile Documents/com~apple~CloudDocs/personal-rig-mac`. So
this repo shows up at two paths that are the same directory:

    /Users/dvir/personal/dictato
    /Users/dvir/Library/Mobile Documents/com~apple~CloudDocs/personal-rig-mac/dictato

There is one checkout, not two. Do not try to reconcile them.

## The core-tests constraint

`Tools/run-core-tests.sh` compiles every file in `Sources/NiviCore/` together
with `Tools/core-tests/main.swift` as a **single module**:

```sh
swiftc -O Sources/NiviCore/*.swift Tools/core-tests/main.swift -o .build/core-tests
```

Two consequences:

- Core files must **not** `import NiviCore`. There is no separate module to
  import from inside it.
- Core files may import **Foundation only**. One `import AVFoundation` or
  `import SwiftUI` in `Sources/NiviCore/` breaks every test at once.

This is why anything platform-specific lives in `Sources/Nivi/` and only pure
logic goes in core. It is also why so much of this app is testable without Xcode.
Tests are plain `check(cond, msg)` assertions in `Tools/core-tests/main.swift`.
[docs/architecture.md](docs/architecture.md) has a section on how to add one.

## The private notes

`.claude/` and `.superpowers/sdd/` are symlinks into `~/personal/dev-workspace`,
a separate private repo with one folder per project. The public repo gitignores
both by name (no trailing slash, because they are symlinks and a trailing slash
only matches a real directory).

So agent config and run artifacts are backed up on GitHub, but not in the public
repo. The research and design notes under `docs/` are public on purpose.

**If those paths are missing**, which is what a fresh clone on another Mac looks
like, get them back with:

```sh
git clone git@github.com-private:Dvirco1234/dev-workspace.git ~/personal/dev-workspace
bash ~/personal/dev-workspace/setup.sh nivi ~/personal/dictato
```

`setup.sh` takes a project name and a checkout path. For each private path it
moves any real files into the workspace repo first, then replaces the path with a
relative symlink pointing there. It is safe to run again: a link that is already
correct is left alone, and it refuses rather than guessing if both a real folder
and a stored copy exist. The repo is private, so this needs an account with
access.

Nothing in the app depends on these paths. Without them you lose the agent
config and the run history, not the ability to build.

## Writing style

These are the owner's rules and they apply to code, comments, commit messages and
anything else you write:

- Plain language. Short sentences, one idea each.
- Everyday work English. Prefer "fix" over "remediate", "use" over "leverage".
- Comments explain **why**. If a comment only restates the code, delete it and
  make the name clearer instead.
- Names say what the thing is, in words a newcomer can read. No invented
  abbreviations.
- Never use em dashes.
- Keep exact identifiers, error strings, file paths and numbers verbatim.

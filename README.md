# Nivi

Offline Hebrew dictation for macOS. Say something, and the text lands in
whatever app you are in. The speech never leaves the Mac.

The name comes from the Hebrew word *niv*, a turn of phrase. It is said
NEE-vee. The app was called Dictato until August 2026.

- **Model:** [ivrit-ai/whisper-large-v3-turbo-ggml](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml)
  (downloaded on first launch, about 1.6 GB, then fully offline)
- **Engine:** whisper.cpp on Metal
- **Needs:** macOS 14 or newer, Apple Silicon

## Using it

Hotkeys are per profile and you can change them in Preferences. Out of the box:

- **Double-tap right ⌘** — start recording, an overlay appears
- **Single-tap right ⌘** — stop, transcribe, paste into the app you are in
- **Esc** — cancel the recording

Everything else lives in Preferences: profiles, models, word replacements,
history, and where the app shows itself (Dock icon, menu bar icon, or both).

## Building it

```sh
make cert     # one-time: creates the "Nivi Self-Signed" identity
make vendor   # one-time: clone and build whisper.cpp
make dev      # debug build, signed, installed to /Applications, relaunched
make app      # release build into build/Nivi.app
```

Needs the Xcode command line tools and cmake. Full Xcode is not required.

Always build through `make dev` or `make app`. A bare `swift build` refreshes
`.build/debug/Nivi` but leaves the copy inside the bundle alone, so the app you
launch is the one you built last time.

Never sign ad-hoc. macOS ties Accessibility, Input Monitoring and Microphone to
the signing identity, so an ad-hoc signature mints a new identity on every build
and silently drops all three.

Tests run without full Xcode:

```sh
bash Tools/run-core-tests.sh   # prints ALL CORE CHECKS PASSED
```

## Releasing it

```sh
make release VERSION=0.2.0
```

One command: builds the app, packs `dist/Nivi-0.2.0.dmg`, signs the update feed,
tags, and publishes to the public releases repo. `make dist` does the same
without git or publishing. See [docs/release-pipeline.md](docs/release-pipeline.md)
for the version scheme, where the Sparkle signing key lives, and how to rename
the app. [INSTALL.md](INSTALL.md) is what a new user reads.

## Where things are kept

| What | Where |
|---|---|
| Settings | the `com.dvir.nivi` defaults domain |
| Models, history, layout tuning | `~/Library/Application Support/Nivi/` |
| Logs | `~/Library/Logs/Nivi/nivi.log` |

Settings can be changed from the Terminal too, with
`defaults write com.dvir.nivi <key> <value>`. Everything in Preferences is one
of these keys; `Sources/NiviCore/Settings.swift` is the full list.

## Coming from Dictato

The first launch under the new name brings the old data across by itself: the
settings are copied out of `com.dvir.dictato`, and
`~/Library/Application Support/Dictato/` is renamed to `.../Nivi/`, so the
downloaded models are not fetched again.

Two things it cannot bring across:

- **Permissions.** macOS ties them to the app's identity, and Nivi is a new
  identity, so Microphone, Accessibility and Input Monitoring must be granted
  again. See [INSTALL.md](INSTALL.md).
- **The old app.** `/Applications/Dictato.app` is still there. Delete it once
  Nivi is working, and remove the leftover Dictato rows from Login Items and
  from the Privacy & Security lists.

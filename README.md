# Nivi

Offline Hebrew dictation for macOS. Menu bar app; complements Spokenly
(Spokenly → English, Nivi → Hebrew).

- **Model:** [ivrit-ai/whisper-large-v3-turbo-ggml](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml)
  (downloaded on first launch, ~1.6 GB, then fully offline)
- **Engine:** whisper.cpp (Metal)

## Usage

- **Double-tap right ⌘** — start recording (overlay appears)
- **Single-tap right ⌘** — stop and transcribe; text is pasted into the active app
- **Esc** — cancel recording

## Build

```sh
make vendor   # one-time: clone + build whisper.cpp
make app      # build build/Nivi.app
cp -R build/Nivi.app /Applications/
```

Requires: macOS 14+, Xcode command line tools, cmake.

Permissions: Microphone (recording) and Accessibility (global hotkey + paste).

## Install (shared build)

Nivi is ad-hoc signed (no paid Apple Developer account), so macOS Gatekeeper
blocks it on first open with a "damaged / unidentified developer" message. This
is expected — unlock it once:

1. Open `Nivi.dmg`, drag **Nivi** to **Applications**.
2. Remove the download quarantine:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Nivi.app
   ```
   (Or right-click Nivi → **Open** → **Open** the first time.)
3. Launch Nivi. On first run it downloads the Hebrew model (~1.6 GB), then
   works fully offline.

Grant **Microphone** (recording) and **Accessibility** (global hotkey + paste)
when prompted, then relaunch once so the hotkey monitor picks up the grant.

## Make a release

```sh
make release VERSION=0.2.0
```

One command: builds the app, packs `dist/Nivi-0.2.0.dmg`, signs the update
feed, tags, and publishes to the public releases repo. `make dist` does the same
without git or publishing. See [docs/release-pipeline.md](docs/release-pipeline.md)
for the version scheme, where the Sparkle signing key lives, and how to rename
the app. [INSTALL.md](INSTALL.md) is what a new user reads.

## Settings

No preferences window in v1. `defaults write com.dvir.nivi <key> <value>`:

| Key | Default | Meaning |
|---|---|---|
| `autoPaste` | true | Paste after transcription (false = clipboard only) |
| `showOverlay` | true | Show the floating overlay |
| `doubleTapWindowMs` | 400 | Double-tap window |
| `maxRecordingSeconds` | 600 | Auto-stop cap |
| `verboseLogging` | false | Debug logging |
| `modelPathOverride` | — | Absolute path to an alternative GGML model |

Logs: `~/Library/Logs/Nivi/`.

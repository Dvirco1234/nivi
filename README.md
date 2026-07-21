# Dictato

Offline Hebrew dictation for macOS. Menu bar app; complements Spokenly
(Spokenly → English, Dictato → Hebrew).

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
make app      # build build/Dictato.app
cp -R build/Dictato.app /Applications/
```

Requires: macOS 14+, Xcode command line tools, cmake.

Permissions: Microphone (recording) and Accessibility (global hotkey + paste).

## Settings

No preferences window in v1. `defaults write com.dvir.dictato <key> <value>`:

| Key | Default | Meaning |
|---|---|---|
| `autoPaste` | true | Paste after transcription (false = clipboard only) |
| `showOverlay` | true | Show the floating overlay |
| `doubleTapWindowMs` | 400 | Double-tap window |
| `maxRecordingSeconds` | 600 | Auto-stop cap |
| `verboseLogging` | false | Debug logging |
| `modelPathOverride` | — | Absolute path to an alternative GGML model |

Logs: `~/Library/Logs/Dictato/`.

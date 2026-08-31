# Dictato — Hebrew Dictation for macOS (Design Spec)

Date: 2026-07-21
Status: Approved

## Goal

A lightweight native macOS menu bar app for offline Hebrew speech-to-text, complementing Spokenly (Spokenly → English, Dictato → Hebrew). UX nearly identical to Spokenly: hotkey → overlay → transcribe → paste into the frontmost app.

## Core principles

- 100% offline after initial model download
- Low latency: model resident in memory, inference < 2s for ~10s of speech on Apple Silicon
- Native (SwiftUI + AppKit), menu bar only, no windows
- ~0% CPU when idle
- Works in every application
- Never crashes; every failure recovers to idle

## Decisions (resolved during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Backend | whisper.cpp | ivrit-ai publishes ready GGML weights; zero conversion. WhisperKit would need a Python CoreML conversion pipeline. |
| Model | `ivrit-ai/whisper-large-v3-turbo-ggml` (~1.6GB) | 4–6x faster decode than full large-v3; Hebrew fine-tune keeps quality. |
| Build | SwiftPM executable + Makefile assembling `Dictato.app` | Pure CLI workflow; ad-hoc codesign; no .xcodeproj. |
| Hotkey | **Right ⌘ — double-tap to start, single tap to stop** | Modifier-only key; requires NSEvent global monitor (Accessibility perm — already needed for paste). |
| v1 scope | Minimal: no Preferences window | Defaults in UserDefaults, editable via `defaults write`. Prefs UI = v2. |
| Audio API | In-memory `[Float]` samples, no temp WAV | whisper.cpp consumes Float32 directly; skips disk I/O. |
| Location | `~/personal/dictato`, app name Dictato | — |

## Architecture

```
DictationController (state machine: idle → recording → transcribing → inserting → idle/error)
├── MenuBarController    NSStatusItem + menu
├── OverlayWindow        borderless non-activating NSPanel, bottom-center, never takes focus
├── HotkeyManager        Right-⌘ tap detection via NSEvent global flagsChanged monitor;
│                        Esc monitor active only while recording
├── AudioRecorder        AVAudioEngine → 16 kHz mono Float32, buffered in memory
├── SpeechRecognizer     protocol — backend abstraction
│   └── WhisperCppRecognizer   whisper.cpp via SwiftPM (Metal); loads GGML once, resident; language "he"
├── ModelManager         first-launch download from Hugging Face → Application Support; verify; never redownload
├── TextInserter         clipboard save → set → CGEvent ⌘V → restore (needs Accessibility)
├── PermissionManager    microphone + accessibility checks and guided prompts
├── Settings             UserDefaults wrapper (no UI in v1)
└── Log                  os.Logger + rotating file log in ~/Library/Logs/Dictato/
```

Each module independent and testable. UI never touches the backend directly — only `DictationController` and the `SpeechRecognizer` protocol.

### SpeechRecognizer protocol

```swift
protocol SpeechRecognizer {
    var isLoaded: Bool { get }
    func load() async throws
    func transcribe(samples: [Float]) async throws -> String
    func unload()
}
```

Future backends (WhisperKit, MLX, faster-whisper server, …) implement the same protocol. The model is configuration of the backend, not something the UI knows about.

### State machine

States: `loadingModel`, `idle`, `recording`, `transcribing`, `inserting`, `error(transient)`.

Transitions:
- launch → loadingModel → idle (menu bar shows "Loading Hebrew model…" → "Ready")
- idle + right-⌘ double-tap → recording (overlay appears)
- recording + right-⌘ single tap → transcribing → inserting → success flash (~700 ms) → idle
- recording + Esc → discard audio → idle (no transcription)
- any failure → error overlay (~1.5 s) → idle

### Hotkey detection (right ⌘)

- `NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown])` + local monitors for same.
- Right ⌘ = keyCode 54. A "tap" = press + release with **no other key pressed during the hold** (so ⌘C, ⌘Tab etc. never count).
- Idle: two taps within 400 ms → start recording.
- Recording: one tap → stop and transcribe.
- Esc-to-cancel: monitor registered only while recording, removed after — Esc behaves normally otherwise.
- Requires Accessibility permission (shared with paste; single permission prompt flow).

### Audio

- AVAudioEngine input tap; convert to 16 kHz mono Float32 via AVAudioConverter.
- Accumulate in memory (10 min hard cap → auto-stop).
- No temp files. Buffer discarded after transcription or cancel.

### Model download

- Source: `https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin` (1.62 GB).
- Destination: `~/Library/Application Support/Dictato/models/`.
- URLSession download with progress reported in menu bar item; resume data on interrupt.
- Validate size + GGML magic bytes; corrupt → offer delete + redownload.
- After success: never download again; load on every launch.

### Text insertion

1. Save current `NSPasteboard` contents (string types).
2. Write transcription to pasteboard.
3. Post CGEvent ⌘V to frontmost app.
4. Restore previous pasteboard after ~1 s.
- No Accessibility permission → clipboard-only mode: leave text on clipboard, notify user once per session.

### Menu bar menu

```
Ready / Loading… / Recording… / Error
──────────────
Start Recording        (also stops when recording)
Reload Model
Launch at Login        (toggle, SMAppService)
Open Logs
Quit
```

### Overlay

- Non-activating NSPanel (`.nonactivatingPanel`), window level above normal windows, ignores mouse, bottom-center of the screen with keyboard focus.
- SwiftUI content, states:
  - Recording: animated mic, timer `00:07`, live level-meter waveform
  - Processing: spinner
  - Success: ✓ "Text inserted" ~700 ms
  - Error: ⚠️ short message ~1.5 s
- Hidden entirely when idle.

### Settings (UserDefaults, no UI in v1)

`autoPaste` (default true), `showOverlay` (true), `doubleTapWindowMs` (400), `maxRecordingSeconds` (600), `verboseLogging` (false), `modelPath` (override).

### Logging

os.Logger (subsystem `com.dvir.dictato`) mirrored to a rotating file in `~/Library/Logs/Dictato/`. Events: recording start/stop/cancel, inference start/duration, paste completed, errors. "Open Logs" menu item reveals the folder.

### Error handling

| Failure | Behavior |
|---|---|
| Mic permission denied | Alert + button to System Settings; stay idle |
| Accessibility denied | Clipboard-only fallback + one-time notice |
| Model missing/corrupt | Redownload flow |
| Disk full during download | Error + retry from menu |
| Inference failure | Error overlay, log, back to idle |

## Build & packaging

- SwiftPM executable target; dependency: whisper.cpp (SwiftPM, Metal enabled). Fallback if the package fights us: cmake-build `libwhisper` and link the C API from the Makefile.
- `make app`: swift build -c release → assemble `Dictato.app` (Info.plist: `LSUIElement`, `NSMicrophoneUsageDescription`) → ad-hoc codesign.
- `make run`, `make install` (→ /Applications), `make test`.
- macOS 14+, Apple Silicon primary target.

## Testing

- Unit: state machine transitions, tap-detection logic (injected clock/events), Settings, ModelManager path/validation logic, audio format conversion.
- Manual: end-to-end dictation, permissions flows, hotkeys in various apps, clipboard restore.

## Out of scope (future)

Preferences window, sounds, VAD auto-stop, model switching, streaming transcription, custom prompts, dictation history, LLM post-processing, noise suppression.

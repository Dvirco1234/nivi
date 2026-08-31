# Dictato 2d — Live Streaming Dictation (revised design)

Date: 2026-07-26
Status: Approved
Supersedes: `2026-07-22-dictato-2b-streaming-design.md` (written before 2c profiles shipped;
its hotkey and Settings sections are obsolete — see "Reconciliation" below).

## Goal

Add live, word-by-word dictation. Two live modes join the existing Batch mode:

- **Overlay-live** — words appear and self-correct in the overlay as you speak; a final
  full-context pass is pasted on stop.
- **In-app-live** — stabilized words are typed straight into the focused field as you speak.

## Reconciliation with 2c (what the old spec no longer needs to build)

The original spec predates dictation profiles. 2c already shipped the parts it proposed,
in a more general form, so those sections are dropped rather than reimplemented:

| Old spec proposed | Status after 2c |
|---|---|
| `HotkeyManager` replacing `HotkeyMonitor`, N bindings → mode dispatch | **Already exists** as `HotkeyRouter`, keyed by profile rather than by mode. No change needed. |
| `bindingBatch` / `bindingOverlayLive` / `bindingInAppLive` settings | **Obsolete.** Each profile already carries its own `hotkey` *and* its own `mode`. Per-mode hotkeys fall out for free, and you can have several profiles per mode (e.g. Hebrew-live and English-live). |
| `HotkeyBinding.none` for unassigned modes | **Obsolete.** A mode with no hotkey is simply a profile that doesn't exist. |
| Legacy `dictateBinding` → `bindingBatch` migration | **Already done** by `ProfileSet.migrated`. |
| "Default mode: overlay-live" | **Per profile.** The migrated profile stays `.batch`; the user opts a profile into a live mode. |

Net effect: 2d is now purely the streaming engine plus its UI surface. The mode already
flows through the system — `DictationProfile.mode` is read at record time, and the
Preferences mode picker just needs its "coming soon" gating removed.

## Architecture delta

```
DictatoCore
├── StablePrefixTracker      NEW  pure logic: per-pass text → stable committed prefix
├── InsertionMode            isImplemented becomes true for all three cases
└── Settings                 +maxStreamingSeconds (30), +streamingIntervalMs (500)

Dictato
├── AudioRecorder            +currentSamples() thread-safe snapshot
├── StreamingTranscriber     NEW  serialized re-transcribe loop → StreamingUpdate callback
├── TextInserter             +typeUnicode(_:) append-only typing (CGEventKeyboardSetUnicodeString)
├── DictationController      drives streaming for live-mode profiles; mode-aware stop
├── Overlay/OverlayModel     +liveText
├── Overlay/OverlayView      live-text line above a shrunk waveform when streaming
└── Preferences/ProfilesSection  un-grey the live modes in the mode picker
```

## Components

### StablePrefixTracker (DictatoCore, pure/testable)

```swift
public struct StablePrefixTracker {
    public init(stabilityPasses: Int = 2)
    /// Feed the latest full transcript; returns the word-prefix that has been
    /// identical across the last `stabilityPasses` calls (the "committed" text).
    public mutating func update(_ fullText: String) -> String
}
```

Splits on whitespace into words. The stable prefix is the longest leading run of words
identical (by position and value) across the tracked passes. **Monotonic within a
recording:** once a prefix is committed it never shrinks, because In-app-live has already
typed those words into the user's document and cannot take them back. A fresh instance
per recording resets it.

### StreamingTranscriber (Dictato)

```swift
struct StreamingUpdate { let fullText: String; let stableText: String }

final class StreamingTranscriber {
    init(recognizer: SpeechRecognizer,
         language: String,
         sampleProvider: @escaping () -> [Float],
         intervalMs: Int,
         maxSeconds: Int,
         onUpdate: @escaping (StreamingUpdate) -> Void)
    func start()
    func stop()   // stops the loop; the controller runs the final pass
}
```

Serialized async loop: snapshot samples → if longer than `maxSeconds`, transcribe only the
trailing window (earlier text stays frozen from the last stable output) → transcribe →
feed an internal `StablePrefixTracker` → deliver on the main actor. The next pass waits
`intervalMs` **after** the previous one finishes, so passes never overlap — the model is
serialized and a backlog would only grow. Short/empty buffers skip a pass.

Reuses the already-loaded recognizer for the active profile's model via `RecognizerCache`
— no second model, no reload. `language` comes from the active profile, matching how
batch transcription already resolves it.

### AudioRecorder

Add `currentSamples() -> [Float]`, a copy of the accumulated buffer taken under the
existing `samplesQueue`. Recording continues; `stop()`/`cancel()` unchanged.

### TextInserter

```swift
func typeUnicode(_ string: String)
```

`CGEvent` + `CGEventKeyboardSetUnicodeString` to emit arbitrary Unicode into the frontmost
app — layout-independent (important for Hebrew) and no clipboard churn. Needs
Accessibility, which is already required. The existing clipboard `insert(...)` stays for
Batch and for Overlay-live's final commit.

### DictationController

- `startRecording` already resolves the active profile. For a profile whose `mode` is a
  live mode, additionally start a `StreamingTranscriber` with that profile's model and
  language.
- Updates: Overlay-live → `overlayModel.liveText = update.fullText`. In-app-live → type
  the part of `update.stableText` beyond what was already typed, tracking typed length.
- Stop:
  - Batch — unchanged.
  - Overlay-live — stop streamer, one final pass over the full buffer, paste the result.
  - In-app-live — stop streamer, final pass, type the tail past the already-typed length.
    If what was typed isn't a prefix of the final text, append only the remainder past the
    typed length. That's a knowingly accepted imperfection: append-only never corrupts the
    document, and silently rewriting the user's text would be worse. Logged when it happens.
- Cancel — stop streamer, discard. For In-app-live, already-typed text stays in the
  document; there is no reliable un-type, and this is documented rather than faked.

### Overlay

`OverlayModel.liveText: String` (published). Non-empty → the recording card shows one
RTL-aware line of the newest text (head-truncated so the latest words stay visible) above
a shortened waveform; the card grows to fit. Empty (Batch) → today's layout.

### Settings

`maxStreamingSeconds` (default 30) and `streamingIntervalMs` (default 500), both surfaced
in the Speech section. No binding changes — profiles own those.

## Error handling

- A pass throws → skip it, keep the last preview, continue (logged once per recording).
- No stable words yet → In-app-live types nothing; the final pass covers everything.
- Recognizer unavailable → the profile falls back to Batch behavior with a one-time notice.
- `maxStreamingSeconds` exceeded → live preview freezes; the final pass still runs over the
  full audio, so nothing is lost from the result the user actually keeps.
- Cancel mid-pass → the loop exits after the in-flight pass and the result is discarded.

## Testing

- Core (`Tools/run-core-tests.sh`): `StablePrefixTracker` — growth, monotonicity,
  convergence after a correction, independence across instances; `Settings` streaming
  defaults and persistence; `InsertionMode.isImplemented` now true for all cases.
- Manual: Overlay-live preview corrects mid-sentence then pastes the final text;
  In-app-live appends into TextEdit and Slack without corrupting existing content; cancel
  in each mode; a >30 s dictation freezes preview but still returns full text; two profiles
  with different modes each behave per their own mode.

## Out of scope

VAD auto-stop, true backspace-correcting insertion, dual-model streaming, punctuation
post-processing, dictation history.

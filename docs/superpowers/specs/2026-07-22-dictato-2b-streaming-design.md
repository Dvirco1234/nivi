# Dictato 2b — Streaming Dictation (Design Spec)

Date: 2026-07-22
Status: Approved
Predecessor: `2026-07-22-dictato-2a-packaging-preferences-design.md` (shipped: Dock app, icon, Preferences, Spokenly overlay, hotkey bindings, DMG).

## Goal

Add live, word-by-word dictation to Dictato. Two live modes join the existing Batch mode:

- **Overlay-live** (default) — words appear and self-correct in the overlay as you speak; a final full-context pass is pasted on stop.
- **In-app-live** — stabilized words are typed straight into the focused field as you speak.

Each mode is independently bindable to its own hotkey.

## Decisions (resolved during brainstorming)

| Decision | Choice | Why |
|---|---|---|
| Engine | **Turbo-only, serialized whole-buffer re-transcribe** | One model, no extra download; turbo is fast (~0.6–1.1 s / utterance); whole-buffer gives full-context corrections. |
| Live latency bound | `maxStreamingSeconds` cap (default 30) | Beyond the cap live preview freezes; the final pass still covers all audio. |
| In-app-live insertion | **Append-only, stabilized words only**, typed via Unicode keystrokes | Never corrupts the user's document; no clipboard churn; layout-independent Hebrew. |
| Per-mode hotkeys | **3 optional bindings**, one per mode | Matches "different hotkey per functionality." |
| Default mode | Overlay-live | Safe + live. Batch remains for those who prefer it. |

## Architecture delta

```
DictatoCore
├── StablePrefixTracker      NEW  pure logic: per-pass text → stable committed prefix
├── HotkeyBinding            +case none (unassigned)
└── Settings                 +bindingBatch / bindingOverlayLive / bindingInAppLive, +maxStreamingSeconds, +streamingIntervalMs

Dictato
├── AudioRecorder            +currentSamples() thread-safe snapshot
├── StreamingTranscriber     NEW  serialized re-transcribe loop → StreamingUpdate callback
├── TextInserter             +typeUnicode(_:) append-only Hebrew typing (CGEventKeyboardSetUnicodeString)
├── HotkeyManager            replaces HotkeyMonitor: N bindings → mode dispatch + cancel
├── DictationController      mode-aware start/stop; drives streaming for live modes; final pass
├── Overlay/OverlayModel     +liveText
├── Overlay/OverlayView      live-text line above a shrunk waveform when streaming
└── Preferences/SettingsView Hotkeys tab: 3 recorders (one per mode)
```

## Components

### StablePrefixTracker (DictatoCore, testable)

```swift
public struct StablePrefixTracker {
    public init(stabilityPasses: Int = 2)
    /// Feed the latest full transcript; returns the word-prefix that has been
    /// identical across the last `stabilityPasses` calls (the "committed" text).
    public mutating func update(_ fullText: String) -> String
}
```

- Splits on whitespace into words. Tracks the last `stabilityPasses` outputs; the stable prefix = longest leading run of words identical (by position + value) across all tracked passes.
- Monotonic: the returned stable prefix never shrinks within one recording (once committed, stays committed) — the tracker remembers the max committed length and only grows it.
- Reset via a fresh instance per recording.

### StreamingTranscriber (Dictato)

```swift
struct StreamingUpdate { let fullText: String; let stableText: String }

final class StreamingTranscriber {
    init(recognizer: SpeechRecognizer,
         sampleProvider: @escaping () -> [Float],
         intervalMs: Int,
         maxSeconds: Int,
         onUpdate: @escaping (StreamingUpdate) -> Void)
    func start()
    func stop()   // stops the loop; does NOT run the final pass (controller does)
}
```

- Runs a serialized async loop: snapshot samples → if longer than `maxSeconds`, transcribe only the last `maxSeconds` window (older text is kept from the previous stable output as a frozen prefix) → `recognizer.transcribe` (turbo) → run text through an internal `StablePrefixTracker` → deliver `StreamingUpdate` on the main actor. Next pass waits `intervalMs` after the previous completes (no overlap).
- Guards against empty/too-short buffers (skips a pass).
- Shares the already-loaded turbo recognizer instance (no second model, no reload).

### AudioRecorder change

Add `func currentSamples() -> [Float]` returning a copy of the accumulated buffer under the existing `samplesQueue`. Recording continues; `stop()`/`cancel()` unchanged.

### TextInserter change

```swift
func typeUnicode(_ string: String)   // posts keyDown/up carrying the unicode string
```

- Uses `CGEvent(keyboardEventSource:)` + `CGEventKeyboardSetUnicodeString` to emit arbitrary Unicode (Hebrew) into the frontmost app, layout-independent, no clipboard. Requires Accessibility (already required).
- Existing `insert(_:autoPaste:excludeFromHistory:)` (clipboard paste) stays for Batch and Overlay-live final commit.

### HotkeyManager (replaces HotkeyMonitor)

```swift
struct HotkeyAssignment { let mode: InsertionMode; let binding: HotkeyBinding }

final class HotkeyManager {
    init(assignments: [HotkeyAssignment], cancelBinding: HotkeyBinding)
    var onActivateMode: ((InsertionMode) -> Void)?   // fired on a mode's start/stop tap
    var onCancel: (() -> Void)?
    var cancelEnabled: Bool
    var activeMode: InsertionMode?   // set by controller while recording (enables single-tap stop)
    func start(); func stop()
}
```

- Builds one `ModifierTapDetector` per `modifierTap` assignment; matches `keyCombo` assignments on `.keyDown`; ignores `.none`.
- Idle: a mode's tap (double for `modifierTap` count 2) → `onActivateMode(mode)`.
- Recording (`activeMode` set): a single tap of the **active** mode's key → `onActivateMode(activeMode)` (controller interprets as stop). Other modes' hotkeys ignored while recording.
- Cancel binding matched on `.keyDown` when `cancelEnabled`.
- Global monitors need Accessibility; Esc keyDown needs Input Monitoring (both already handled in 2a).

### DictationController changes

- Reads the three bindings → `HotkeyManager` assignments. `onActivateMode(mode)` → if idle, `startRecording(mode:)`; if recording that mode, stop.
- `startRecording(mode:)` sets `activeMode`; for `.batch` behaves as today; for live modes also starts a `StreamingTranscriber`.
- Live update handling: Overlay-live → `overlayModel.liveText = update.fullText`. In-app-live → type `update.stableText` beyond what was already typed (append-only; track typed length).
- Stop:
  - Batch → unchanged (single turbo pass → paste).
  - Overlay-live → stop streamer, run one final turbo pass on full samples → paste committed text (clipboard, transient).
  - In-app-live → stop streamer, run final turbo pass → type the tail (`final` minus already-typed length) via `typeUnicode`. If already-typed is not a prefix of `final`, append only `final`'s remainder past the typed length (accepted imperfection per append-only rule; logged).
- Cancel (Esc / hover-X): stop streamer, discard. In-app-live: already-typed text remains in the document (documented; no reliable un-type).

### Overlay changes

- `OverlayModel.liveText: String` (published). Non-empty → the recording card shows a single RTL line of the latest text (head-truncated so the newest words stay visible) above a shorter waveform. Empty (Batch) → current layout.
- Card height grows when `liveText` present.

### Settings changes

- Keys: `bindingBatch` (default `.modifierTap(.rightCommand, 2)`), `bindingOverlayLive` (default `.none`), `bindingInAppLive` (default `.none`), `maxStreamingSeconds` (default 30), `streamingIntervalMs` (default 500).
- Migration: if a legacy `dictateBinding` exists and `bindingBatch` is unset, copy it into `bindingBatch`.
- `HotkeyBinding` gains `case none` with `displayString` = "—" and JSON round-trip.

## Error handling

- Streaming pass throws → skip that pass, keep last preview, continue (log once).
- No stable words yet in In-app-live → type nothing until stabilization; final pass covers the rest.
- Recognizer busy/not loaded → live modes fall back to Batch behavior with a one-time notice.
- `maxStreamingSeconds` exceeded → freeze live preview, final pass still runs on full audio.
- Cancel during a pass → loop exits after the in-flight pass; result discarded.

## Testing

- Unit (no-Xcode runner): `StablePrefixTracker` (growth, monotonicity, correction convergence, reset); `HotkeyBinding.none` round-trip + display; `Settings` three bindings + streaming keys defaults/persistence + legacy migration.
- Manual: Overlay-live live text + correction + final paste; In-app-live append-only typing into TextEdit/Slack; each mode's hotkey; cancel in each mode; >30 s dictation cap behavior.

## Out of scope (later)

VAD auto-stop, true backspace-correcting in-app insertion, dual-model, streaming for languages other than Hebrew, punctuation post-processing, dictation history.

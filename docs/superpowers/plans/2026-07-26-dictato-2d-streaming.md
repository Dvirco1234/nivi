# Dictato 2d — Live Streaming Dictation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add live word-by-word dictation in two modes — Overlay-live (words appear and self-correct in the overlay, final text pasted on stop) and In-app-live (stabilized words typed straight into the focused field).

**Architecture:** A pure `StablePrefixTracker` (DictatoCore) turns a sequence of whole-buffer transcripts into a monotonically-growing committed prefix. A `StreamingTranscriber` (app layer) runs a serialized re-transcribe loop over the in-flight recording buffer and publishes `StreamingUpdate`s on the main actor. `DictationController` starts the streamer for profiles whose `mode` is a live mode, feeds the overlay or types stabilized text, and runs a final full-context pass on stop. Mode already flows through the system from 2c — `DictationProfile.mode` is read at record time.

**Tech Stack:** Swift 5.10, SwiftUI + AppKit, SwiftPM, whisper.cpp (Metal). No Xcode/XCTest — core tests run via `bash Tools/run-core-tests.sh`.

## Global Constraints

- macOS 14+, Apple Silicon. Bundle id `com.dvir.dictato`.
- DictatoCore stays pure (no AppKit/SwiftUI/AVFoundation) — it compiles into the core-test binary. App/UI code lives under `Sources/Dictato/`.
- `Settings` accessors use `nonmutating set`.
- Build gate before every commit: `make build` succeeds; `bash Tools/run-core-tests.sh` prints no `FAIL:` lines.
- **Signing: always the stable `Dictato Self-Signed` identity, never ad-hoc** — macOS keys TCC grants (Accessibility, Input Monitoring, Microphone) to the signing identity, and ad-hoc signing silently revokes them. Use `make dev` for the build→bundle→sign→install→relaunch loop; `swift build` alone leaves a stale binary inside `build/Dictato.app`. See the `macos-app-dev` skill.
- **In-app-live is append-only.** Never delete or rewrite text already typed into the user's document. A wrong correction is recoverable; corrupting the user's buffer is not.
- Caveman mode is a conversation style only — code, comments, and commit messages are written normally.

---

## File Structure

- Create `Sources/DictatoCore/StablePrefixTracker.swift` — pure stable-prefix logic.
- Create `Sources/Dictato/StreamingTranscriber.swift` — serialized re-transcribe loop.
- Modify `Sources/DictatoCore/Settings.swift` — `maxStreamingSeconds`, `streamingIntervalMs`.
- Modify `Sources/DictatoCore/ModelSpec.swift` — `InsertionMode.isImplemented` removal (Task 5).
- Modify `Sources/Dictato/AudioRecorder.swift` — `currentSamples()`.
- Modify `Sources/Dictato/TextInserter.swift` — `typeUnicode(_:)`.
- Modify `Sources/Dictato/DictationController.swift` — mode-aware start/update/stop.
- Modify `Sources/Dictato/Overlay/OverlayModel.swift` + `OverlayView.swift` — live text line.
- Modify `Sources/Dictato/Preferences/ProfilesSection.swift` + `SettingsView.swift` — un-gate live modes, streaming settings, drop the dead global insertion-mode picker.
- Modify `Tools/core-tests/main.swift` — tracker + settings tests.

---

## Task 1: `StablePrefixTracker` + streaming settings (DictatoCore, pure, TDD)

**Files:**
- Create: `Sources/DictatoCore/StablePrefixTracker.swift`
- Modify: `Sources/DictatoCore/Settings.swift`
- Test: `Tools/core-tests/main.swift` (append)

**Interfaces:**
- Produces:
  - `public struct StablePrefixTracker { public init(stabilityPasses: Int = 2); public mutating func update(_ fullText: String) -> String }`
  - `Settings.maxStreamingSeconds: Int` (default 30), `Settings.streamingIntervalMs: Int` (default 500), both `nonmutating set`.

- [ ] **Step 1: Write the failing tests** (append to `Tools/core-tests/main.swift`, before the final failure check)

```swift
// --- StablePrefixTracker ---
var tracker = StablePrefixTracker(stabilityPasses: 2)
check(tracker.update("hello") == "", "first pass commits nothing")
check(tracker.update("hello world") == "hello", "word stable across two passes commits")
check(tracker.update("hello world") == "hello world", "all words stable commit")

// a correction before stabilization must not commit the wrong word
var t2 = StablePrefixTracker(stabilityPasses: 2)
_ = t2.update("hello word")
let afterCorrection = t2.update("hello world")
check(afterCorrection == "hello", "unstable trailing word not committed")
check(t2.update("hello world") == "hello world", "converges once stable")

// monotonic: a shorter later transcript never shrinks the committed prefix
var t3 = StablePrefixTracker(stabilityPasses: 2)
_ = t3.update("one two three")
_ = t3.update("one two three")
check(t3.update("one") == "one two three", "committed prefix never shrinks")

// instances are independent (fresh tracker per recording)
var t4 = StablePrefixTracker(stabilityPasses: 2)
check(t4.update("alpha") == "", "fresh instance starts empty")

// stabilityPasses 3 needs three identical passes
var t5 = StablePrefixTracker(stabilityPasses: 3)
_ = t5.update("a b")
_ = t5.update("a b")
check(t5.update("a b") == "a b", "three-pass stability commits on third")

// whitespace/newlines collapse to single-space joins
var t6 = StablePrefixTracker(stabilityPasses: 2)
_ = t6.update("  spaced   out \n text ")
check(t6.update("  spaced   out \n text ") == "spaced out text", "whitespace normalized")

// --- streaming settings ---
let ssuite = UserDefaults(suiteName: "com.dvir.dictato.coretest")!
let st = Settings(defaults: ssuite)
check(st.maxStreamingSeconds == 30, "default maxStreamingSeconds")
check(st.streamingIntervalMs == 500, "default streamingIntervalMs")
st.maxStreamingSeconds = 45
st.streamingIntervalMs = 700
let st2 = Settings(defaults: ssuite)
check(st2.maxStreamingSeconds == 45, "maxStreamingSeconds persists")
check(st2.streamingIntervalMs == 700, "streamingIntervalMs persists")
```

- [ ] **Step 2: Run to verify failure**

Run: `bash Tools/run-core-tests.sh`
Expected: compile error — `cannot find 'StablePrefixTracker' in scope`.

- [ ] **Step 3: Create `Sources/DictatoCore/StablePrefixTracker.swift`**

```swift
import Foundation

/// Turns a sequence of whole-buffer transcripts into a monotonically growing
/// "committed" word prefix.
///
/// Each streaming pass re-transcribes the whole recording, so earlier words can
/// change as later context arrives. A word is only safe to show as final once it
/// has survived several consecutive passes unchanged. The committed prefix never
/// shrinks: In-app-live has already typed those words into the user's document
/// and there is no reliable way to take them back, so retracting would be a lie.
public struct StablePrefixTracker {
    private let stabilityPasses: Int
    private var history: [[String]] = []
    private var committed: [String] = []

    public init(stabilityPasses: Int = 2) {
        self.stabilityPasses = max(1, stabilityPasses)
    }

    public mutating func update(_ fullText: String) -> String {
        let words = fullText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        history.append(words)
        if history.count > stabilityPasses { history.removeFirst() }

        if history.count == stabilityPasses {
            let shortest = history.map(\.count).min() ?? 0
            var stable = 0
            while stable < shortest {
                let word = history[0][stable]
                guard history.allSatisfy({ $0[stable] == word }) else { break }
                stable += 1
            }
            if stable > committed.count {
                // Append only the positions past what is already committed. Never
                // rewrite an existing entry: those words have already been typed into
                // the user's document, and because `history` is a sliding window, a
                // later contradicting-then-agreeing pair could otherwise revise them.
                committed += Array(words.prefix(stable)).dropFirst(committed.count)
            }
        }
        return committed.joined(separator: " ")
    }
}
```

- [ ] **Step 4: Add the streaming settings** — in `Sources/DictatoCore/Settings.swift`, add to the `register(defaults:)` dictionary:

```swift
            Key.maxStreamingSeconds: 30,
            Key.streamingIntervalMs: 500,
```

to the `Key` enum:

```swift
        static let maxStreamingSeconds = "maxStreamingSeconds"
        static let streamingIntervalMs = "streamingIntervalMs"
```

and the accessors:

```swift
    public var maxStreamingSeconds: Int {
        get { defaults.integer(forKey: Key.maxStreamingSeconds) }
        nonmutating set { defaults.set(newValue, forKey: Key.maxStreamingSeconds) }
    }

    public var streamingIntervalMs: Int {
        get { defaults.integer(forKey: Key.streamingIntervalMs) }
        nonmutating set { defaults.set(newValue, forKey: Key.streamingIntervalMs) }
    }
```

- [ ] **Step 5: Run to verify pass**

Run: `bash Tools/run-core-tests.sh`
Expected: no `FAIL:` lines.

- [ ] **Step 6: Commit**

```bash
git add Sources/DictatoCore/StablePrefixTracker.swift Sources/DictatoCore/Settings.swift Tools/core-tests/main.swift
git commit -m "feat(core): StablePrefixTracker + streaming settings"
```

---

## Task 2: Recording snapshot + Unicode typing primitives

**Files:**
- Modify: `Sources/Dictato/AudioRecorder.swift`
- Modify: `Sources/Dictato/TextInserter.swift`

**Interfaces:**
- Produces: `AudioRecorder.currentSamples() -> [Float]`; `TextInserter.typeUnicode(_ string: String)`.

- [ ] **Step 1: Add `currentSamples()` to `AudioRecorder`** — place it next to `stop()`:

```swift
    /// A snapshot of everything recorded so far. Recording continues; the streaming
    /// loop re-transcribes this growing buffer. Taken under `samplesQueue` because
    /// the audio tap appends to `samples` from a real-time thread.
    func currentSamples() -> [Float] {
        samplesQueue.sync { samples }
    }
```

- [ ] **Step 2: Add `typeUnicode(_:)` to `TextInserter`**

```swift
    /// Types text into the frontmost app as Unicode key events.
    ///
    /// Used by In-app-live, where the clipboard path is wrong: it would clobber the
    /// user's clipboard on every stabilized word. Unicode events are also layout
    /// independent, so Hebrew arrives correctly regardless of the active keyboard
    /// layout. Requires Accessibility, which the app already needs for auto-paste.
    func typeUnicode(_ string: String) {
        guard !string.isEmpty, PermissionManager.accessibilityGranted else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        // CGEventKeyboardSetUnicodeString takes UTF-16; chunk it so long strings
        // don't exceed what a single event will carry.
        for chunk in Array(string.utf16).chunked(into: 16) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            var buffer = chunk
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
```

and at the bottom of the file:

```swift
private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
```

- [ ] **Step 3: Build**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: `Build complete!`; no `FAIL:` lines.

- [ ] **Step 4: Commit**

```bash
git add Sources/Dictato/AudioRecorder.swift Sources/Dictato/TextInserter.swift
git commit -m "feat: buffer snapshot for streaming + Unicode typing for in-app insertion"
```

---

## Task 3: `StreamingTranscriber`

**Files:**
- Create: `Sources/Dictato/StreamingTranscriber.swift`

**Interfaces:**
- Consumes: `SpeechRecognizer` (protocol), `StablePrefixTracker` (Task 1), `AudioRecorder.sampleRate`.
- Produces:
  - `struct StreamingUpdate { let fullText: String; let stableText: String }`
  - `final class StreamingTranscriber` with `init(recognizer:language:sampleProvider:intervalMs:maxSeconds:onUpdate:)`, `start()`, `stop()`.

- [ ] **Step 1: Create `Sources/Dictato/StreamingTranscriber.swift`**

```swift
import Foundation
import DictatoCore

struct StreamingUpdate {
    let fullText: String
    let stableText: String
}

/// Re-transcribes the in-flight recording buffer on a serialized loop so the user
/// sees words as they speak.
///
/// Whole-buffer re-transcription (rather than incremental chunks) is what lets later
/// context correct earlier words — the same reason the final pass exists. Passes never
/// overlap: the next one is scheduled `intervalMs` after the previous *finishes*,
/// because the recognizer serializes internally and a backlog would only grow.
final class StreamingTranscriber {
    private let recognizer: SpeechRecognizer
    private let language: String
    private let sampleProvider: () -> [Float]
    private let intervalMs: Int
    private let maxSeconds: Int
    private let onUpdate: (StreamingUpdate) -> Void

    private var task: Task<Void, Never>?
    private var tracker = StablePrefixTracker()
    private var loggedFailure = false
    private var loggedFreeze = false

    init(recognizer: SpeechRecognizer,
         language: String,
         sampleProvider: @escaping () -> [Float],
         intervalMs: Int,
         maxSeconds: Int,
         onUpdate: @escaping (StreamingUpdate) -> Void) {
        self.recognizer = recognizer
        self.language = language
        self.sampleProvider = sampleProvider
        self.intervalMs = intervalMs
        self.maxSeconds = maxSeconds
        self.onUpdate = onUpdate
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runPass()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(100, self.intervalMs)) * 1_000_000)
            }
        }
    }

    /// Stops the loop. The controller runs the final full-context pass itself, so
    /// this deliberately does not produce a last update.
    func stop() {
        task?.cancel()
        task = nil
    }

    private func runPass() async {
        let samples = sampleProvider()

        // whisper needs ~1s of audio to say anything useful; skip until we have it.
        guard samples.count >= Int(AudioRecorder.sampleRate) else { return }

        // Past the cap, freeze the preview rather than re-transcribing an ever-growing
        // buffer: passes would get slower and slower and fall further behind the
        // speaker. The final pass still covers the whole recording, so the text the
        // user actually keeps is unaffected.
        guard samples.count <= Int(AudioRecorder.sampleRate) * maxSeconds else {
            if !loggedFreeze {
                Log.info("Streaming preview frozen past \(maxSeconds)s; final pass still covers all audio")
                loggedFreeze = true
            }
            return
        }

        do {
            let text = try await recognizer.transcribe(samples: samples, language: language)
            guard !Task.isCancelled else { return }
            let stable = tracker.update(text)
            let update = StreamingUpdate(fullText: text, stableText: stable)
            await MainActor.run { self.onUpdate(update) }
        } catch {
            // A dropped pass is not worth surfacing — the next one usually succeeds and
            // the final pass is authoritative. Log once so a systematic failure is still
            // visible without flooding the log every interval.
            if !loggedFailure {
                Log.error("Streaming pass failed: \(error.localizedDescription)")
                loggedFailure = true
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: `Build complete!`; no `FAIL:` lines.

- [ ] **Step 3: Commit**

```bash
git add Sources/Dictato/StreamingTranscriber.swift
git commit -m "feat: StreamingTranscriber serialized re-transcribe loop"
```

---

## Task 4: Controller + overlay wiring

**Files:**
- Modify: `Sources/Dictato/DictationController.swift`
- Modify: `Sources/Dictato/Overlay/OverlayModel.swift`
- Modify: `Sources/Dictato/Overlay/OverlayView.swift`

**Interfaces:**
- Consumes: `StreamingTranscriber`/`StreamingUpdate` (Task 3), `AudioRecorder.currentSamples()` and `TextInserter.typeUnicode(_:)` (Task 2), `DictationProfile.mode`.
- Produces: `OverlayModel.liveText: String` (published).

- [ ] **Step 1: Add `liveText` to `OverlayModel`** — alongside the existing published properties:

```swift
    @Published var liveText: String = ""
```

and clear it in `reset()` (add `liveText = ""` to that method's body).

- [ ] **Step 2: Show live text in `OverlayView`** — replace `recordingBody`:

```swift
    private var recordingBody: some View {
        VStack(spacing: 6) {
            HStack {
                targetApp
                Spacer(minLength: 8)
                brand
            }
            if !model.liveText.isEmpty {
                Text(model.liveText)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.head)   // keep the newest words visible
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            waveform
        }
    }
```

and make the card grow when live text is present — replace the `cardHeight` constant and its uses:

```swift
    private let cardWidth: CGFloat = 360
    private var cardHeight: CGFloat { model.liveText.isEmpty ? 78 : 104 }
```

- [ ] **Step 3: Add streaming state to `DictationController`** — new stored properties next to `recordingTimer`:

```swift
    private var streamer: StreamingTranscriber?
    private var typedLength = 0
```

- [ ] **Step 4: Start streaming for live-mode profiles** — in `startRecording()`, after the existing `transition(.startRequested)` and sound lines, add:

```swift
            if profile?.mode != .batch, let profile {
                startStreaming(for: profile)
            }
```

and add the method:

```swift
    private func startStreaming(for profile: DictationProfile) {
        typedLength = 0
        overlayModel.liveText = ""
        Task { [weak self] in
            guard let self,
                  let model = self.modelStore.catalog.model(id: profile.modelID),
                  let recognizer = try? await self.recognizerCache.recognizer(
                      id: model.id, modelPath: self.modelStore.installedURL(for: model))
            else {
                Log.error("Streaming unavailable — falling back to batch for this recording")
                return
            }
            guard case .recording = self.machine.state else { return }
            let streamer = StreamingTranscriber(
                recognizer: recognizer,
                language: profile.language,
                sampleProvider: { [weak self] in self?.recorder.currentSamples() ?? [] },
                intervalMs: self.settings.streamingIntervalMs,
                maxSeconds: self.settings.maxStreamingSeconds,
                onUpdate: { [weak self] update in
                    Task { @MainActor in self?.handleStreamingUpdate(update, mode: profile.mode) }
                })
            self.streamer = streamer
            streamer.start()
        }
    }

    private func handleStreamingUpdate(_ update: StreamingUpdate, mode: InsertionMode) {
        guard case .recording = machine.state else { return }
        switch mode {
        case .overlayLive:
            overlayModel.liveText = update.fullText
        case .inAppLive:
            overlayModel.liveText = update.fullText
            typeStabilized(update.stableText)
        case .batch:
            break
        }
    }

    /// Types only the part of the stabilized text we haven't typed yet. Append-only:
    /// if the tracker's committed prefix somehow disagrees with what we typed, we
    /// still only ever add. Rewriting the user's document would be worse than an
    /// imperfect tail.
    private func typeStabilized(_ stableText: String) {
        guard stableText.count > typedLength else { return }
        let tail = String(stableText.dropFirst(typedLength))
        let toType = typedLength == 0 ? tail : " " + tail.trimmingCharacters(in: .whitespaces)
        inserter.typeUnicode(toType)
        typedLength = stableText.count
    }
```

- [ ] **Step 5: Make stop mode-aware** — in `stopAndTranscribe()`, stop the streamer first (immediately after `stopTimer()`):

```swift
        streamer?.stop()
        streamer = nil
```

and replace the insertion branch inside the existing `Task` (the `transition(.transcriptionSucceeded)` / `inserter.insert(...)` lines) with:

```swift
                transition(.transcriptionSucceeded)
                switch profile.mode {
                case .batch, .overlayLive:
                    inserter.insert(text,
                                    autoPaste: settings.autoPaste,
                                    excludeFromHistory: settings.excludeFromClipboardHistory)
                case .inAppLive:
                    // Type only what streaming hasn't already typed. If the final text
                    // diverges from what was typed, we accept the seam rather than
                    // rewriting the user's document.
                    if text.count > typedLength {
                        let tail = String(text.dropFirst(typedLength))
                        inserter.typeUnicode(typedLength == 0 ? tail : " " + tail.trimmingCharacters(in: .whitespaces))
                    } else {
                        Log.info("Final text shorter than typed text; leaving document as-is")
                    }
                }
                typedLength = 0
                transition(.insertionCompleted)
```

- [ ] **Step 6: Stop streaming on cancel** — in `cancelRecording()`, after `stopTimer()`:

```swift
        streamer?.stop()
        streamer = nil
        typedLength = 0
        overlayModel.liveText = ""
```

- [ ] **Step 7: Clear live text when leaving the recording state** — in `updateOverlay()`, in the `.idle, .loadingModel` branch, add `overlayModel.liveText = ""` before hiding the panel.

- [ ] **Step 8: Build + core tests**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: `Build complete!`; no `FAIL:` lines.

- [ ] **Step 9: Commit**

```bash
git add Sources/Dictato/DictationController.swift Sources/Dictato/Overlay/OverlayModel.swift Sources/Dictato/Overlay/OverlayView.swift
git commit -m "feat: drive live streaming from live-mode profiles; overlay live text"
```

---

## Task 5: Un-gate live modes in Preferences

**Files:**
- Modify: `Sources/Dictato/Preferences/ProfilesSection.swift`
- Modify: `Sources/Dictato/Preferences/SettingsView.swift`
- Modify: `Sources/DictatoCore/ModelSpec.swift`

**Interfaces:**
- Consumes: `InsertionMode`, `Settings.maxStreamingSeconds` / `.streamingIntervalMs` (Task 1).
- Produces: no new API; removes `InsertionMode.isImplemented`.

- [ ] **Step 1: Remove the `isImplemented` gate** — in `Sources/DictatoCore/ModelSpec.swift`, delete the property:

```swift
    public var isImplemented: Bool { self == .batch }   // 2a: only batch
```

All three modes now work, so a gate that always returns true would just be dead code.

- [ ] **Step 2: Un-grey the profile mode picker** — in `ProfilesSection.swift`'s `ProfileEditSheet`, replace the mode `Picker` and its `.onChange`:

```swift
            Picker("Insertion mode", selection: $draft.mode) {
                ForEach(InsertionMode.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
```

(the `.onChange(of: draft.mode)` that forced `.batch` is deleted entirely), and in `ProfileCard` replace `modeLabel`:

```swift
    private var modeLabel: String { profile.mode.displayName }
```

- [ ] **Step 3: Remove the dead global insertion-mode picker** — in `SettingsView.swift`'s `GeneralSection`, delete the `mode` state property and the `Picker("Insertion mode", …)` with its `.onChange`. Insertion mode is per-profile since 2c; nothing reads `settings.insertionMode`, so leaving a control that changes nothing would mislead. Keep `LaunchAtLoginToggle()` in that `Section`.

- [ ] **Step 4: Surface the streaming settings** — in `SettingsView.swift`'s `SpeechSection`, add state:

```swift
    @State private var streamingInterval = Settings().streamingIntervalMs
    @State private var maxStreaming = Settings().maxStreamingSeconds
```

and a new `Section` before the closing brace of the `Form`:

```swift
            Section {
                Stepper("Live update interval: \(streamingInterval) ms",
                        value: $streamingInterval, in: 200...2000, step: 100)
                    .onChange(of: streamingInterval) { settings.streamingIntervalMs = $0 }
                Stepper("Freeze live preview after \(maxStreaming) s",
                        value: $maxStreaming, in: 10...120, step: 5)
                    .onChange(of: maxStreaming) { settings.maxStreamingSeconds = $0 }
            } footer: {
                Text("Live modes re-transcribe the whole recording each interval. Past the freeze point the preview stops updating, but the final text still covers everything you said.")
                    .font(.caption).foregroundStyle(.secondary)
            }
```

- [ ] **Step 5: Build + core tests**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: `Build complete!`; no `FAIL:` lines. (If a core test still asserts `InsertionMode.overlayLive.isImplemented == false`, delete that assertion — the gate is gone.)

- [ ] **Step 6: Install and smoke test**

Run: `make dev`
Manual checks:
- Edit a profile → the mode picker offers all three modes with no "coming soon".
- Set a profile to Overlay-live → dictate → words appear in the overlay and self-correct → final text pastes on stop.
- Set a profile to In-app-live → dictate into TextEdit → stabilized words appear as you speak, and nothing already typed is ever deleted or rewritten.
- Cancel (Esc) in each live mode: overlay clears; in In-app-live the already-typed text remains (expected).
- Dictate past the freeze point: preview stops updating, final text still covers the whole recording.
- A Batch profile still behaves exactly as before.

- [ ] **Step 7: Commit**

```bash
git add Sources/Dictato/Preferences/ProfilesSection.swift Sources/Dictato/Preferences/SettingsView.swift Sources/DictatoCore/ModelSpec.swift Tools/core-tests/main.swift
git commit -m "feat: enable live insertion modes in Preferences; streaming settings"
```

---

## Self-Review

**Spec coverage:** `StablePrefixTracker` → Task 1. Streaming settings → Tasks 1 + 5. `currentSamples()` / `typeUnicode` → Task 2. `StreamingTranscriber` → Task 3. Controller mode-aware start/update/stop, cancel, final pass → Task 4. Overlay `liveText` + growing card → Task 4. Preferences un-gating → Task 5. Error handling: pass failure logged once (Task 3), freeze past cap (Task 3), recognizer unavailable falls back (Task 4 `startStreaming` guard), cancel discards (Task 4). Testing: core tests Task 1, manual Task 5.

**Deviation from the spec, deliberate:** the spec's `StreamingTranscriber` sketch described transcribing a trailing window past `maxSeconds`, while its error-handling section said the preview freezes. The plan implements **freeze**, which is simpler and avoids a seam between a frozen prefix and a windowed suffix. The final pass covers the full audio either way, so the kept text is identical.

**Type consistency:** `StreamingUpdate(fullText:stableText:)`, `StreamingTranscriber(recognizer:language:sampleProvider:intervalMs:maxSeconds:onUpdate:)`, `start()`/`stop()`, `StablePrefixTracker.update(_:)`, `AudioRecorder.currentSamples()`, `TextInserter.typeUnicode(_:)` used consistently across Tasks 1–5. `typedLength` is reset in `startStreaming`, after the final pass, and on cancel.

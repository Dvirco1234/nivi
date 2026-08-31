# Dictato 2d.1 — Windowed Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make live dictation keep up with the speaker by transcribing only a sliding ~10s window instead of the whole growing recording, and make stopping near-instant by bounding the final pass to the un-frozen tail.

**Architecture:** A pure `StreamWindow` value type (DictatoCore) owns the freeze/stitch state: text for audio that has scrolled out (`frozenText`) plus the sample offset where the live window begins. The recognizer gains a segment-returning entry point so freezing can land on real timestamp boundaries, and takes an `audioCtx` override — the whisper.cpp lever that actually makes a short window cheap. `StreamingTranscriber` drives the window; `DictationController`'s final pass covers only the tail and stitches onto the frozen text.

**Tech Stack:** Swift 5.10, SwiftUI + AppKit, SwiftPM, whisper.cpp (Metal). No Xcode/XCTest — core tests run via `bash Tools/run-core-tests.sh`.

## Global Constraints

- macOS 14+, Apple Silicon. Bundle id `com.dvir.dictato`.
- DictatoCore stays pure (no AppKit/SwiftUI/AVFoundation/CWhisper) — it compiles into the core-test binary. App code lives under `Sources/Dictato/`.
- `Settings` accessors use `nonmutating set`.
- Build gate before every commit: `make build` succeeds; `bash Tools/run-core-tests.sh` prints no `FAIL:` lines.
- **Signing: always the stable `Dictato Self-Signed` identity, never ad-hoc** — macOS keys TCC grants (Accessibility, Input Monitoring, Microphone) to the signing identity, and ad-hoc signing silently revokes them. Use `make dev` for build→bundle→sign→install→relaunch. See the `macos-app-dev` skill.
- **In-app-live insertion is append-only.** Never delete or rewrite text already typed into the user's document. Freezing must not break the monotonicity of the committed prefix.
- **Whisper's encoder cost is fixed per 30s chunk unless `audio_ctx` is lowered.** A shorter window without a scaled `audioCtx` buys nothing. These two changes only work together.
- Caveman mode is a conversation style only — code, comments, and commit messages are written normally.

---

## File Structure

- Create `Sources/DictatoCore/TranscriptSegment.swift` — pure `{ text, startMs, endMs }` value type.
- Create `Sources/DictatoCore/StreamWindow.swift` — pure freeze/stitch logic.
- Modify `Sources/DictatoCore/Settings.swift` — add `streamingWindowSeconds`, remove `maxStreamingSeconds`.
- Modify `Sources/Dictato/SpeechRecognizer.swift` — add `transcribeSegments(samples:language:audioCtx:)`.
- Modify `Sources/Dictato/WhisperCppRecognizer.swift` — implement it (timestamps + `audio_ctx`).
- Modify `Sources/Dictato/StreamingTranscriber.swift` — drive `StreamWindow`, drop the freeze-past-cap path.
- Modify `Sources/Dictato/DictationController.swift` — bounded final pass stitched onto frozen text.
- Modify `Sources/Dictato/Preferences/SettingsView.swift` — replace the freeze-cap stepper with window length.
- Modify `Tools/core-tests/main.swift` — `StreamWindow` and settings tests.

---

## Task 1: `TranscriptSegment` + `StreamWindow` (DictatoCore, pure, TDD)

**Files:**
- Create: `Sources/DictatoCore/TranscriptSegment.swift`
- Create: `Sources/DictatoCore/StreamWindow.swift`
- Test: `Tools/core-tests/main.swift` (append)

**Interfaces:**
- Produces:
  - `public struct TranscriptSegment: Equatable { public let text: String; public let startMs: Int; public let endMs: Int; public init(text: String, startMs: Int, endMs: Int) }`
  - `public struct StreamWindow { public init(); public private(set) var frozenText: String; public private(set) var windowStartSample: Int; public mutating func advance(segments: [TranscriptSegment], windowSampleCount: Int, maxWindowSamples: Int, sampleRate: Int) -> String }`

- [ ] **Step 1: Write the failing tests** (append to `Tools/core-tests/main.swift`, before the final failure check)

```swift
// --- StreamWindow ---
func seg(_ t: String, _ s: Int, _ e: Int) -> TranscriptSegment {
    TranscriptSegment(text: t, startMs: s, endMs: e)
}
let rate = 16_000
let tenSeconds = rate * 10

// Under the window length: nothing freezes, live text is just the window.
var w1 = StreamWindow()
let live1 = w1.advance(segments: [seg("hello world", 0, 2000)],
                       windowSampleCount: rate * 3, maxWindowSamples: tenSeconds, sampleRate: rate)
check(live1 == "hello world", "short window returns window text")
check(w1.frozenText.isEmpty, "nothing frozen under the cap")
check(w1.windowStartSample == 0, "window start unmoved under the cap")

// Over the cap: leading segments freeze and the window start advances to that segment's end.
var w2 = StreamWindow()
let live2 = w2.advance(segments: [seg("first part", 0, 3000), seg("second part", 3000, 12000)],
                       windowSampleCount: rate * 12, maxWindowSamples: tenSeconds, sampleRate: rate)
check(w2.frozenText == "first part", "leading segment frozen once past the cap")
check(w2.windowStartSample == rate * 3, "window start advanced to the frozen segment end")
check(live2 == "first part second part", "live text stitches frozen and window text")

// Several segments can freeze in one pass.
var w3 = StreamWindow()
_ = w3.advance(segments: [seg("a", 0, 2000), seg("b", 2000, 4000), seg("c", 4000, 14000)],
               windowSampleCount: rate * 14, maxWindowSamples: tenSeconds, sampleRate: rate)
check(w3.frozenText == "a b", "multiple segments freeze in one pass")
check(w3.windowStartSample == rate * 4, "window start advanced past the last frozen segment")

// The final segment never freezes, even if it alone exceeds the window: it is still
// being spoken and its text will keep changing.
var w4 = StreamWindow()
_ = w4.advance(segments: [seg("one long unbroken stretch", 0, 20000)],
               windowSampleCount: rate * 20, maxWindowSamples: tenSeconds, sampleRate: rate)
check(w4.frozenText.isEmpty, "sole segment never freezes")
check(w4.windowStartSample == 0, "window start unmoved when only one segment exists")

// A failed/empty pass must not freeze or move the window.
var w5 = StreamWindow()
_ = w5.advance(segments: [seg("kept", 0, 3000), seg("tail", 3000, 12000)],
               windowSampleCount: rate * 12, maxWindowSamples: tenSeconds, sampleRate: rate)
let frozenBefore = w5.frozenText
let startBefore = w5.windowStartSample
let live5 = w5.advance(segments: [], windowSampleCount: rate * 13,
                       maxWindowSamples: tenSeconds, sampleRate: rate)
check(w5.frozenText == frozenBefore, "empty pass does not change frozen text")
check(w5.windowStartSample == startBefore, "empty pass does not move the window")
check(live5 == frozenBefore, "empty pass returns the frozen text alone")

// Window start advances monotonically across passes.
var w6 = StreamWindow()
_ = w6.advance(segments: [seg("x", 0, 2000), seg("y", 2000, 12000)],
               windowSampleCount: rate * 12, maxWindowSamples: tenSeconds, sampleRate: rate)
let afterFirst = w6.windowStartSample
_ = w6.advance(segments: [seg("y", 0, 1000), seg("z", 1000, 11000)],
               windowSampleCount: rate * 11, maxWindowSamples: tenSeconds, sampleRate: rate)
check(w6.windowStartSample >= afterFirst, "window start never goes backwards")

// Stitching produces single spaces, no doubling, and trims segment whitespace.
var w7 = StreamWindow()
let live7 = w7.advance(segments: [seg("  padded  ", 0, 3000), seg("  text  ", 3000, 12000)],
                       windowSampleCount: rate * 12, maxWindowSamples: tenSeconds, sampleRate: rate)
check(live7 == "padded text", "segment whitespace trimmed and joined with single spaces")

// --- settings ---
let wsuite = UserDefaults(suiteName: "com.dvir.dictato.coretest")!
let wset = Settings(defaults: wsuite)
check(wset.streamingWindowSeconds == 10, "default streamingWindowSeconds")
wset.streamingWindowSeconds = 15
check(Settings(defaults: wsuite).streamingWindowSeconds == 15, "streamingWindowSeconds persists")
```

- [ ] **Step 2: Run to verify failure**

Run: `bash Tools/run-core-tests.sh`
Expected: compile error — `cannot find 'TranscriptSegment' in scope`.

- [ ] **Step 3: Create `Sources/DictatoCore/TranscriptSegment.swift`**

```swift
import Foundation

/// One timestamped chunk of transcript. Times are relative to the start of the samples
/// that produced them, not to the whole recording — the caller knows the window offset
/// and converts to absolute positions itself.
public struct TranscriptSegment: Equatable {
    public let text: String
    public let startMs: Int
    public let endMs: Int

    public init(text: String, startMs: Int, endMs: Int) {
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
    }
}
```

- [ ] **Step 4: Create `Sources/DictatoCore/StreamWindow.swift`**

```swift
import Foundation

/// Tracks which part of a recording the live preview still re-transcribes, and the text
/// for the part that has scrolled out of it.
///
/// Re-transcribing the whole recording every pass gets slower the longer you speak, so the
/// live loop only looks at a trailing window. That means committing to text for the audio
/// falling out of the window. Freezing happens on whole segment boundaries because segment
/// timestamps are the only way to know which words belong to which audio — splitting
/// anywhere else would duplicate or drop words at the seam.
public struct StreamWindow {
    /// Transcript for audio that has scrolled out of the live window. Never revised.
    public private(set) var frozenText: String = ""
    /// Offset into the recording where the live window begins. Only ever moves forward.
    public private(set) var windowStartSample: Int = 0

    public init() {}

    /// Folds one pass's segments into the window, returning the full live text
    /// (frozen text plus the current window's text).
    public mutating func advance(segments: [TranscriptSegment],
                                 windowSampleCount: Int,
                                 maxWindowSamples: Int,
                                 sampleRate: Int) -> String {
        // A failed or silent pass tells us nothing; freezing on it would commit to text we
        // never actually saw.
        guard !segments.isEmpty else { return frozenText }

        var frozenCount = 0
        if windowSampleCount > maxWindowSamples {
            let excessSamples = windowSampleCount - maxWindowSamples
            let excessMs = excessSamples * 1000 / sampleRate
            // Never freeze the last segment: it is still being spoken and its text will
            // keep changing. If it alone overflows the window, the window simply runs long
            // for a while — a correct seam matters more than an exact window size.
            // Freeze leading segments in order until the frozen boundary reaches or passes
            // the excess, including the segment that crosses it: freezing a segment whose
            // end is already past the excess still brings the window back under the cap,
            // and stopping short would leave it over.
            while frozenCount < segments.count - 1 {
                frozenCount += 1
                if segments[frozenCount - 1].endMs >= excessMs { break }
            }
            if frozenCount > 0 {
                let newlyFrozen = segments[0..<frozenCount]
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                frozenText = Self.join(frozenText, newlyFrozen.joined(separator: " "))
                windowStartSample += segments[frozenCount - 1].endMs * sampleRate / 1000
            }
        }

        // Only the segments still inside the window: the frozen ones are already in
        // `frozenText`, and including them again here would duplicate them in the preview.
        let windowText = segments.dropFirst(frozenCount)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return Self.join(frozenText, windowText)
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }
        return lhs + " " + rhs
    }
}
```

- [ ] **Step 5: Add the setting** — in `Sources/DictatoCore/Settings.swift`, add to `register(defaults:)`:

```swift
            Key.streamingWindowSeconds: 10,
```

to the `Key` enum:

```swift
        static let streamingWindowSeconds = "streamingWindowSeconds"
```

and the accessor:

```swift
    public var streamingWindowSeconds: Int {
        get { defaults.integer(forKey: Key.streamingWindowSeconds) }
        nonmutating set { defaults.set(newValue, forKey: Key.streamingWindowSeconds) }
    }
```

Leave `maxStreamingSeconds` in place for now — Task 4 removes it once nothing reads it.

- [ ] **Step 6: Run to verify pass**

Run: `bash Tools/run-core-tests.sh`
Expected: no `FAIL:` lines.

- [ ] **Step 7: Commit**

```bash
git add Sources/DictatoCore/TranscriptSegment.swift Sources/DictatoCore/StreamWindow.swift Sources/DictatoCore/Settings.swift Tools/core-tests/main.swift
git commit -m "feat(core): StreamWindow freeze/stitch logic + window length setting"
```

---

## Task 2: Segment-returning recognizer with `audio_ctx`

**Files:**
- Modify: `Sources/Dictato/SpeechRecognizer.swift`
- Modify: `Sources/Dictato/WhisperCppRecognizer.swift`

**Interfaces:**
- Consumes: `TranscriptSegment` (Task 1).
- Produces: `func transcribeSegments(samples: [Float], language: String, audioCtx: Int) async throws -> [TranscriptSegment]` on `SpeechRecognizer`.

- [ ] **Step 1: Add to the protocol** — in `Sources/Dictato/SpeechRecognizer.swift`, inside `protocol SpeechRecognizer`:

```swift
    /// Transcribes with segment timestamps. `audioCtx` overrides whisper's audio context
    /// size (0 = model default); lowering it in proportion to a short window is what makes
    /// a short window actually cheaper, since the encoder otherwise always runs a full 30s
    /// context regardless of how much audio it was given.
    func transcribeSegments(samples: [Float], language: String, audioCtx: Int) async throws -> [TranscriptSegment]
```

and add `import DictatoCore` at the top of the file if it is not already there.

- [ ] **Step 2: Implement it in `WhisperCppRecognizer`** — add this method next to `transcribe`:

```swift
    func transcribeSegments(samples: [Float], language: String, audioCtx: Int) async throws -> [TranscriptSegment] {
        // whisper_full requires at least ~1s of audio; pad short clips with silence.
        var audio = samples
        let minSamples = Int(AudioRecorder.sampleRate * 1.2)
        if audio.count < minSamples {
            audio.append(contentsOf: [Float](repeating: 0, count: minSamples - audio.count))
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let context = self.context else {
                    continuation.resume(throwing: SpeechRecognizerError.notLoaded)
                    return
                }
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                let lang = language == "auto" ? nil : strdup(language)
                defer { if let lang { free(lang) } }
                params.language = lang.map { UnsafePointer($0) }
                params.translate = false
                params.n_threads = Int32(min(8, ProcessInfo.processInfo.activeProcessorCount))
                // Timestamps are the whole point of this entry point: the window can only
                // freeze on boundaries it can actually locate in the audio.
                params.no_timestamps = false
                params.audio_ctx = Int32(audioCtx)
                params.print_progress = false
                params.print_realtime = false
                params.print_special = false
                params.suppress_blank = true

                let status = audio.withUnsafeBufferPointer { buffer in
                    whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
                }
                guard status == 0 else {
                    continuation.resume(throwing: SpeechRecognizerError.inferenceFailed(status))
                    return
                }
                var segments: [TranscriptSegment] = []
                for index in 0..<whisper_full_n_segments(context) {
                    guard let raw = whisper_full_get_segment_text(context, index) else { continue }
                    // whisper reports segment times in centiseconds.
                    let t0 = Int(whisper_full_get_segment_t0(context, index)) * 10
                    let t1 = Int(whisper_full_get_segment_t1(context, index)) * 10
                    segments.append(TranscriptSegment(text: String(cString: raw), startMs: t0, endMs: t1))
                }
                continuation.resume(returning: segments)
            }
        }
    }
```

- [ ] **Step 3: Build**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: `Build complete!`; no `FAIL:` lines.

- [ ] **Step 4: Commit**

```bash
git add Sources/Dictato/SpeechRecognizer.swift Sources/Dictato/WhisperCppRecognizer.swift
git commit -m "feat: segment-timestamped transcription with an audio_ctx override"
```

---

## Task 3: Drive the window from `StreamingTranscriber`

**Files:**
- Modify: `Sources/Dictato/StreamingTranscriber.swift`

**Interfaces:**
- Consumes: `StreamWindow`, `TranscriptSegment` (Task 1); `transcribeSegments(samples:language:audioCtx:)` (Task 2); `StablePrefixTracker`.
- Produces: `StreamingTranscriber.init(recognizer:language:sampleProvider:intervalMs:windowSeconds:onUpdate:)` (replaces `maxSeconds:`), and `var windowStartSample: Int { get }` so the controller can bound its final pass.

- [ ] **Step 1: Replace `maxSeconds` with `windowSeconds` and add window state** — change the stored properties and `init`:

```swift
    private let windowSeconds: Int
    private var window = StreamWindow()

    /// Where the un-frozen tail begins. The controller's final pass starts here so it
    /// re-transcribes only what the preview never froze.
    var windowStartSample: Int { window.windowStartSample }
```

In `init`, replace the `maxSeconds` parameter with `windowSeconds: Int` and store
`self.windowSeconds = max(2, windowSeconds)` — under about two seconds whisper has too
little to work with, and the padding it adds dominates.

Add a computed audio context:

```swift
    /// Whisper's encoder always runs a fixed 30s context unless told otherwise, so a short
    /// window is only cheaper if the context shrinks with it. The floor keeps accuracy from
    /// falling off a cliff — this is a lossy optimization, not a free one.
    private var audioCtx: Int {
        max(256, 1500 * windowSeconds / 30)
    }
```

- [ ] **Step 2: Rewrite `runPass()` to transcribe only the window**

```swift
    private func runPass() async {
        let samples = sampleProvider()
        let windowStart = window.windowStartSample
        guard samples.count > windowStart else { return }
        let windowSamples = Array(samples[windowStart...])

        // whisper needs ~1s of audio to say anything useful; skip until we have it.
        guard windowSamples.count >= Int(AudioRecorder.sampleRate) else { return }

        do {
            let segments = try await recognizer.transcribeSegments(
                samples: windowSamples, language: language, audioCtx: audioCtx)
            guard !Task.isCancelled else { return }
            let fullText = window.advance(
                segments: segments,
                windowSampleCount: windowSamples.count,
                maxWindowSamples: Int(AudioRecorder.sampleRate) * windowSeconds,
                sampleRate: Int(AudioRecorder.sampleRate))
            // The tracker only ever sees the whole live text, so its committed prefix stays
            // monotonic across a freeze — which in-app-live depends on, having already typed
            // that text into the user's document.
            let stable = tracker.update(fullText)
            let update = StreamingUpdate(fullText: fullText, stableText: stable)
            guard !Task.isCancelled else { return }
            onUpdate(update)
        } catch {
            if !loggedFailure {
                Log.error("Streaming pass failed: \(error.localizedDescription)")
                loggedFailure = true
            }
        }
    }
```

Delete the freeze-past-cap `guard` and the `loggedFreeze` property — passes are bounded by
construction now, so there is nothing left to freeze against.

- [ ] **Step 3: Build**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: this will fail to build until Task 4 updates the controller's call site
(`maxSeconds:` no longer exists). That is expected; do not "fix" it by keeping the old
parameter. Verify the error is only about the `StreamingTranscriber(...)` call in
`DictationController.swift`:

Run: `make build 2>&1 | grep -c "StreamingTranscriber"`
Expected: a non-zero count, and no other unrelated errors.

Do NOT commit yet — proceed to Task 4.

---

## Task 4: Bounded final pass in the controller

**Files:**
- Modify: `Sources/Dictato/DictationController.swift`
- Modify: `Sources/DictatoCore/Settings.swift`
- Modify: `Sources/Dictato/Preferences/SettingsView.swift`
- Modify: `Tools/core-tests/main.swift`

**Interfaces:**
- Consumes: `StreamingTranscriber.windowStartSample` and its new `windowSeconds:` initializer (Task 3).

- [ ] **Step 1: Capture the streaming state before tearing the streamer down** — in `stopAndTranscribe()`, replace the two lines that stop the streamer:

```swift
        // Keep what streaming already resolved: the frozen prefix needs no re-transcription,
        // so the final pass only has to cover the tail the window never froze.
        let streamedTailStart = streamer?.windowStartSample ?? 0
        let streamedPrefix = overlayModel.liveText
        streamer?.stop()
        streamer = nil
```

- [ ] **Step 2: Bound the final pass** — inside the `Task` in `stopAndTranscribe()`, replace the single `transcribe` call with a tail-only pass stitched onto the frozen prefix:

```swift
                let inferenceStart = Date()
                let text: String
                if streamedTailStart > 0, samples.count > streamedTailStart {
                    // Re-transcribe only the un-frozen tail, at full context for quality.
                    // Bounding this is what keeps stopping fast after a long dictation; the
                    // cost is that frozen text never gets a whole-buffer correction.
                    let tail = Array(samples[streamedTailStart...])
                    let tailText = try await recognizer.transcribe(samples: tail, language: profile.language)
                    let frozen = Self.frozenPrefix(of: streamedPrefix, tailText: tailText)
                    text = frozen.isEmpty ? tailText : frozen + " " + tailText
                } else {
                    text = try await recognizer.transcribe(samples: samples, language: profile.language)
                }
```

and add this helper to `DictationController`:

```swift
    /// The part of the streamed text that the tail pass does not cover. The streamed text
    /// ends with the window's own transcript, which the tail pass is about to redo, so that
    /// overlap is dropped rather than duplicated.
    private static func frozenPrefix(of streamedText: String, tailText: String) -> String {
        let streamedWords = streamedText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let tailWords = tailText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !streamedWords.isEmpty, !tailWords.isEmpty else { return streamedText }
        // Find the longest suffix of the streamed text that the tail text starts with.
        let maxOverlap = min(streamedWords.count, tailWords.count)
        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(streamedWords.suffix(overlap)) == Array(tailWords.prefix(overlap)) {
                return streamedWords.dropLast(overlap).joined(separator: " ")
            }
        }
        return streamedWords.joined(separator: " ")
    }
```

- [ ] **Step 3: Update the streamer construction** — in `startStreaming(for:generation:)`, replace `maxSeconds: self.settings.maxStreamingSeconds` with:

```swift
                windowSeconds: self.settings.streamingWindowSeconds,
```

- [ ] **Step 4: Remove the now-dead `maxStreamingSeconds`** — delete its `Key` entry, its `register(defaults:)` entry and its accessor from `Sources/DictatoCore/Settings.swift`, and delete any core test asserting its default or persistence from `Tools/core-tests/main.swift`. Confirm nothing references it:

Run: `grep -rn "maxStreamingSeconds" Sources/ Tools/`
Expected: no output.

- [ ] **Step 5: Replace the Preferences control** — in `SettingsView.swift`'s `SpeechSection`, replace the `maxStreaming` state and its Stepper with the window length:

```swift
    @State private var windowSeconds = Settings().streamingWindowSeconds
```

```swift
                Stepper("Live preview window: \(windowSeconds) s",
                        value: $windowSeconds, in: 4...30, step: 1)
                    .onChange(of: windowSeconds) { settings.streamingWindowSeconds = $0 }
```

and update that Section's footer to describe the actual behavior:

```swift
                Text("Live modes re-transcribe only the last few seconds each pass, so the preview keeps up however long you speak. A shorter window is faster; a longer one gives whisper more context to correct itself.")
                    .font(.caption).foregroundStyle(.secondary)
```

- [ ] **Step 6: Build + core tests**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: `Build complete!`; no `FAIL:` lines.

- [ ] **Step 7: Install and smoke test**

Run: `make dev`
Manual checks:
- Dictate 60 s continuously in Overlay-live: the preview keeps up throughout and does not visibly slow down as it runs (this is the whole point of the change).
- Stopping after a long dictation returns text almost immediately.
- Read the pasted text at the freeze boundaries — no duplicated or dropped words where the window advanced.
- In-app-live: typed text is never rewritten or deleted; the tail lands cleanly at stop.
- Batch profile behaves exactly as before.
- Both a Hebrew and an English profile produce the right language, confirmed with:
  `grep -E "Streaming:|Final pass:" ~/Library/Logs/Dictato/dictato.log | tail -4`

- [ ] **Step 8: Commit**

```bash
git add Sources/Dictato/StreamingTranscriber.swift Sources/Dictato/DictationController.swift Sources/DictatoCore/Settings.swift Sources/Dictato/Preferences/SettingsView.swift Tools/core-tests/main.swift
git commit -m "feat: sliding-window live preview and a bounded final pass"
```

---

## Self-Review

**Spec coverage:** `TranscriptSegment` → Task 1. `StreamWindow` freeze-on-segment-boundary, never-freeze-last-segment, empty-pass safety, monotonic window start → Task 1 (with tests). Recognizer `transcribeSegments` + timestamps + `audio_ctx` → Task 2. `audio_ctx` scaling with a floor → Task 3. Window-driven passes and removal of the freeze-past-cap path → Task 3. Bounded final pass stitched onto frozen text, at full context → Task 4. `maxStreamingSeconds` removal and the window-length control → Task 4. Batch untouched → Task 4 Step 2 keeps the whole-buffer path when streaming never ran. Testing → Task 1 core tests, Task 4 manual.

**Known sharp edge, called out deliberately:** Task 4 stitches the final tail onto the *displayed* streamed text (`overlayModel.liveText`), not onto `StreamWindow.frozenText` directly, because the window lives inside the streamer that is being torn down. `frozenPrefix(of:tailText:)` removes the overlap by matching words, so a tail that re-transcribes differently than the preview did cannot duplicate the seam. The reviewer should check this specifically — it is the most likely place for a duplicated-words bug, which is exactly the class of defect that shipped in 2d.

**Placeholder scan:** none — every step carries its code or an exact command.

**Type consistency:** `TranscriptSegment(text:startMs:endMs:)`, `StreamWindow.advance(segments:windowSampleCount:maxWindowSamples:sampleRate:)`, `frozenText`, `windowStartSample`, `transcribeSegments(samples:language:audioCtx:)`, `windowSeconds:` and `StreamingTranscriber.windowStartSample` are used identically across Tasks 1–4.

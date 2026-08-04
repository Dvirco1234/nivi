import Foundation
import DictatoCore

struct StreamingUpdate {
    let fullText: String
    let stableText: String
}

/// Re-transcribes a trailing window of the in-flight recording on a serialized loop so
/// the user sees words as they speak.
///
/// Only the window is re-transcribed: whole-buffer passes get slower the longer you speak
/// and fall further behind the speaker. Text for audio that scrolls out of the window is
/// frozen by `StreamWindow` on segment boundaries, so later context can still correct
/// recent words while old ones stop costing anything. Passes never overlap: the next one
/// is scheduled `intervalMs` after the previous *finishes*, because the recognizer
/// serializes internally and a backlog would only grow.
@MainActor
final class StreamingTranscriber {
    private let recognizer: SpeechRecognizer
    private let language: String
    private let sampleProvider: () -> [Float]
    private let intervalMs: Int
    private let windowSeconds: Int
    private let onUpdate: @MainActor (StreamingUpdate) -> Void

    private var task: Task<Void, Never>?
    private var tracker = StablePrefixTracker()
    private var window = StreamWindow()
    private var loggedFailure = false

    /// Where the un-frozen tail begins. The controller's final pass starts here so it
    /// re-transcribes only what the preview never froze.
    var windowStartSample: Int { window.windowStartSample }

    /// Whisper's encoder always runs a fixed 30s context unless told otherwise, so a short
    /// window is only cheaper if the context shrinks with it. The floor keeps accuracy from
    /// falling off a cliff — this is a lossy optimization, not a free one.
    private var audioCtx: Int {
        max(256, 1500 * windowSeconds / 30)
    }

    init(recognizer: SpeechRecognizer,
         language: String,
         sampleProvider: @escaping () -> [Float],
         intervalMs: Int,
         windowSeconds: Int,
         onUpdate: @escaping @MainActor (StreamingUpdate) -> Void) {
        self.recognizer = recognizer
        self.language = language
        self.sampleProvider = sampleProvider
        self.intervalMs = intervalMs
        // Under about two seconds whisper has too little to work with, and the padding it
        // adds dominates; `defaults write streamingWindowSeconds` is a supported config
        // path, so clamp it here.
        self.windowSeconds = max(2, windowSeconds)
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
            // Re-check after the await, not just before it: `stop()` can land while the
            // transcribe is in flight, and delivering an update after stop would type
            // stale text the append-only insertion can never retract.
            guard !Task.isCancelled else { return }
            onUpdate(update)
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

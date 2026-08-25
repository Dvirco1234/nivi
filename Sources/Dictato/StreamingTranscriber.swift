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
    private var loggedStall = false

    /// Where the un-frozen tail begins. The controller's final pass starts here so it
    /// re-transcribes only what the preview never froze.
    var windowStartSample: Int { window.windowStartSample }

    /// Transcript for audio already frozen out of the live window. Together with a pass
    /// over everything from `windowStartSample`, this covers the whole recording exactly
    /// once — so the final text needs no overlap-guessing between the two.
    var frozenText: String { window.frozenText }

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
        // Under a few seconds whisper has too little to work with, and the padding it
        // adds dominates; `defaults write streamingWindowSeconds` is a supported config
        // path that bypasses the Preferences stepper, so clamp to the stepper's floor.
        self.windowSeconds = max(4, windowSeconds)
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

        // Size the encoder context to this slice, not to the configured window: the window
        // runs long whenever the final segment is still being spoken, and a context cut to
        // the nominal length would drop that overrun before whisper ever heard it.
        let audioCtx = audioContext(forSampleCount: windowSamples.count,
                                    sampleRate: Int(AudioRecorder.sampleRate))

        do {
            let segments = try await recognizer.transcribeSegments(
                samples: windowSamples, language: language, audioCtx: audioCtx)
            guard !Task.isCancelled else { return }
            // `StreamWindow` never freezes the last segment, so a pass that returns a single
            // segment can never advance the window. Sustained single-segment output means the
            // window grows without bound, so every pass gets slower and the final pass falls
            // back to the slow whole-buffer path. Don't clamp the slice — dropping audio no
            // frozen text covers would lose words — just make it visible.
            if !loggedStall,
               segments.count < 2,
               windowSamples.count > 2 * Int(AudioRecorder.sampleRate) * windowSeconds {
                Log.error("Streaming window is not advancing: whisper returned a single segment for \(String(format: "%.1f", Double(windowSamples.count) / AudioRecorder.sampleRate))s of audio (window is \(windowSeconds)s)")
                loggedStall = true
            }
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

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
            // Re-check inside the hop, not just before it: `stop()` can land while this
            // block waits for a busy main actor, and delivering an update after stop
            // would type stale text the append-only insertion can never retract.
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.onUpdate(update)
            }
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

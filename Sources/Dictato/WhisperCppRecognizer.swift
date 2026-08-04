import Foundation
import CWhisper
import DictatoCore

final class WhisperCppRecognizer: SpeechRecognizer {
    private let modelPath: URL
    private var context: OpaquePointer?
    private let queue = DispatchQueue(label: "com.dvir.dictato.whisper", qos: .userInitiated)

    var isLoaded: Bool { context != nil }

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    deinit {
        // Free on the inference queue so a still-running whisper_full can never see a
        // freed context. Deliberately captures only the pointer, never self.
        if let context { queue.async { whisper_free(context) } }
    }

    func load() async throws {
        let path = modelPath.path
        let loaded: OpaquePointer? = await withCheckedContinuation { continuation in
            queue.async {
                var params = whisper_context_default_params()
                params.use_gpu = true
                continuation.resume(returning: whisper_init_from_file_with_params(path, params))
            }
        }
        guard let loaded else { throw SpeechRecognizerError.modelLoadFailed(path) }
        context = loaded
        Log.info("Model loaded: \(path)")
    }

    func transcribe(samples: [Float], language: String) async throws -> String {
        // whisper_full requires at least ~1s of audio; pad short clips with silence.
        var audio = samples
        let minSamples = Int(AudioRecorder.sampleRate * 1.2)
        if audio.count < minSamples {
            audio.append(contentsOf: [Float](repeating: 0, count: minSamples - audio.count))
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // Read the pointer on the serial queue, not before enqueuing: padding a
                // long buffer takes long enough that an unload could otherwise slip in
                // between the read and this block, ordering the free ahead of the
                // inference and running whisper_full on freed memory.
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
                params.no_timestamps = true
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
                var text = ""
                for index in 0..<whisper_full_n_segments(context) {
                    if let segment = whisper_full_get_segment_text(context, index) {
                        text += String(cString: segment)
                    }
                }
                continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

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

    /// Frees the whisper context on the inference queue. `whisper_free` while
    /// `whisper_full` is running is a use-after-free, and with live streaming an
    /// in-flight transcribe is the normal state — "Reload model" and the idle-unload
    /// timer are both reachable mid-recording. Clearing `context` first makes any
    /// further `transcribe` fail fast; routing the free through the serial queue makes
    /// it land after whatever pass is already running.
    func unload() async {
        await withCheckedContinuation { continuation in
            queue.async {
                // Read and clear on the same serial queue that runs inference, so the
                // pointer is only ever touched from one thread.
                if let context = self.context {
                    self.context = nil
                    whisper_free(context)
                }
                continuation.resume()
            }
        }
    }
}

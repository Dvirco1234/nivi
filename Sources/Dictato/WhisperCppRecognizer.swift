import Foundation
import CWhisper

final class WhisperCppRecognizer: SpeechRecognizer {
    private let modelPath: URL
    private var context: OpaquePointer?
    private let queue = DispatchQueue(label: "com.dvir.dictato.whisper", qos: .userInitiated)

    var isLoaded: Bool { context != nil }

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    deinit { unload() }

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
        guard let context else { throw SpeechRecognizerError.notLoaded }
        // whisper_full requires at least ~1s of audio; pad short clips with silence.
        var audio = samples
        let minSamples = Int(AudioRecorder.sampleRate * 1.2)
        if audio.count < minSamples {
            audio.append(contentsOf: [Float](repeating: 0, count: minSamples - audio.count))
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
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

    func unload() {
        if let context {
            whisper_free(context)
            self.context = nil
        }
    }
}

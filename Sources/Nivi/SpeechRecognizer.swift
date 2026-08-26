import Foundation
import NiviCore

/// Backend abstraction. The UI and controller only ever see this protocol;
/// the model is configuration of a concrete backend.
protocol SpeechRecognizer: AnyObject {
    var isLoaded: Bool { get }
    func load() async throws
    func transcribe(samples: [Float], language: String) async throws -> String
    /// Transcribes with segment timestamps. `audioCtx` overrides whisper's audio context
    /// size (0 = model default); lowering it in proportion to a short window is what makes
    /// a short window actually cheaper, since the encoder otherwise always runs a full 30s
    /// context regardless of how much audio it was given.
    func transcribeSegments(samples: [Float], language: String, audioCtx: Int) async throws -> [TranscriptSegment]
    /// Releases the model. Async because freeing must be serialized against any
    /// in-flight inference — a free that overlaps one is a use-after-free.
    func unload() async
}

enum SpeechRecognizerError: LocalizedError {
    case modelLoadFailed(String)
    case notLoaded
    case inferenceFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Could not load model at \(path)"
        case .notLoaded: return "Model not loaded"
        case .inferenceFailed(let code): return "Transcription failed (code \(code))"
        }
    }
}

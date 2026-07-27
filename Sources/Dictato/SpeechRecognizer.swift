import Foundation

/// Backend abstraction. The UI and controller only ever see this protocol;
/// the model is configuration of a concrete backend.
protocol SpeechRecognizer: AnyObject {
    var isLoaded: Bool { get }
    func load() async throws
    func transcribe(samples: [Float], language: String) async throws -> String
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

import Foundation

public enum ModelSource: Codable, Equatable {
    case builtin(url: URL)
    case huggingFace(repo: String, file: String)
    case directURL(URL)
    case localFile(path: String)

    public var downloadURL: URL? {
        switch self {
        case .builtin(let url): return url
        case .huggingFace(let repo, let file):
            return URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")
        case .directURL(let url): return url
        case .localFile: return nil
        }
    }
}

/// Which inference engine a model needs. Whisper models run on the vendored
/// whisper.cpp; Parakeet is NVIDIA's FastConformer and needs a different runtime
/// entirely, so listing one does not make it runnable.
public enum ModelEngine: String, Codable, Equatable {
    case whisperCpp
    case parakeet
}

public struct ManagedModel: Codable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var source: ModelSource
    public var defaultLanguage: String
    public var minSizeBytes: Int
    public var summary: String?
    public var sizeBytesApprox: Int?
    public var accuracy: Int?
    public var speed: Int?
    public var badge: String?
    /// Absent in catalogs written before engines existed, which were all whisper.cpp.
    public var engineRaw: ModelEngine?

    public init(id: String, displayName: String, source: ModelSource,
                defaultLanguage: String, minSizeBytes: Int,
                summary: String? = nil, sizeBytesApprox: Int? = nil,
                accuracy: Int? = nil, speed: Int? = nil, badge: String? = nil,
                engine: ModelEngine = .whisperCpp) {
        self.id = id; self.displayName = displayName; self.source = source
        self.defaultLanguage = defaultLanguage; self.minSizeBytes = minSizeBytes
        self.summary = summary; self.sizeBytesApprox = sizeBytesApprox
        self.accuracy = accuracy; self.speed = speed; self.badge = badge
        self.engineRaw = engine
    }

    public var engine: ModelEngine { engineRaw ?? .whisperCpp }

    /// Whether the app can actually run this model today. Unsupported models are still
    /// listed so the catalog shows where things are heading, but they cannot be
    /// downloaded — a 496 MB download that then refuses to load would be worse than
    /// showing the model as not yet available.
    public var isRunnable: Bool { engine == .whisperCpp }

    public var localFileName: String { "\(id).bin" }

    public var languageLabel: String {
        switch defaultLanguage {
        case "he": return "Hebrew"
        case "en": return "English"
        case "auto", "": return "Multilingual"
        default: return defaultLanguage.uppercased()
        }
    }
}

public struct ModelCatalog: Codable, Equatable {
    public var models: [ManagedModel]
    public var defaultModelID: String

    public init(models: [ManagedModel], defaultModelID: String) {
        self.models = models
        self.defaultModelID = defaultModelID
    }

    public func model(id: String) -> ManagedModel? { models.first { $0.id == id } }
    public var defaultModel: ManagedModel? { model(id: defaultModelID) }

    public static func seeded() -> ModelCatalog {
        ModelCatalog(models: [
            ManagedModel(
                id: "ivrit-large-v3-turbo",
                displayName: "ivrit-ai Large v3 Turbo",
                source: .huggingFace(repo: "ivrit-ai/whisper-large-v3-turbo-ggml", file: "ggml-model.bin"),
                defaultLanguage: "he", minSizeBytes: 1_500_000_000,
                summary: "Hebrew-tuned Whisper. Best Hebrew accuracy, fast on Apple Silicon.",
                sizeBytesApprox: 1_620_000_000, accuracy: 5, speed: 4, badge: "Best for Hebrew"),
            ManagedModel(
                id: "whisper-large-v3-turbo",
                displayName: "Whisper Large v3 Turbo",
                source: .huggingFace(repo: "ggerganov/whisper.cpp", file: "ggml-large-v3-turbo.bin"),
                defaultLanguage: "auto", minSizeBytes: 1_500_000_000,
                summary: "Multilingual transcription in 90+ languages. Great all-rounder.",
                sizeBytesApprox: 1_620_000_000, accuracy: 4, speed: 4, badge: "Multilingual"),
            ManagedModel(
                id: "whisper-small-en",
                displayName: "Whisper Small (English)",
                source: .huggingFace(repo: "ggerganov/whisper.cpp", file: "ggml-small.en.bin"),
                defaultLanguage: "en", minSizeBytes: 400_000_000,
                summary: "Fast English-only transcription. Small footprint.",
                sizeBytesApprox: 488_000_000, accuracy: 3, speed: 5, badge: "Fast · English"),
            ManagedModel(
                id: "parakeet-tdt-0.6b-v3",
                displayName: "NVIDIA Parakeet TDT 0.6B v3",
                source: .huggingFace(repo: "nvidia/parakeet-tdt-0.6b-v3", file: "parakeet-tdt-0.6b-v3.nemo"),
                defaultLanguage: "auto", minSizeBytes: 400_000_000,
                summary: "Ultra-fast transcription powered by NVIDIA FastConformer. Optimized for conversational speech and voice commands.",
                sizeBytesApprox: 496_000_000, accuracy: 5, speed: 5, badge: "Best for Multilingual",
                engine: .parakeet),
            ManagedModel(
                id: "parakeet-tdt-0.6b-v2",
                displayName: "NVIDIA Parakeet TDT 0.6B v2",
                source: .huggingFace(repo: "nvidia/parakeet-tdt-0.6b-v2", file: "parakeet-tdt-0.6b-v2.nemo"),
                defaultLanguage: "en", minSizeBytes: 400_000_000,
                summary: "Ultra-fast English-only transcription powered by NVIDIA FastConformer V2. Optimized for English dictation and voice commands.",
                sizeBytesApprox: 496_000_000, accuracy: 5, speed: 5, badge: "Best for English",
                engine: .parakeet),
        ], defaultModelID: "ivrit-large-v3-turbo")
    }
}

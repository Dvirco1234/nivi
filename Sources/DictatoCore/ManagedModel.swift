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

    public init(id: String, displayName: String, source: ModelSource,
                defaultLanguage: String, minSizeBytes: Int,
                summary: String? = nil, sizeBytesApprox: Int? = nil,
                accuracy: Int? = nil, speed: Int? = nil, badge: String? = nil) {
        self.id = id; self.displayName = displayName; self.source = source
        self.defaultLanguage = defaultLanguage; self.minSizeBytes = minSizeBytes
        self.summary = summary; self.sizeBytesApprox = sizeBytesApprox
        self.accuracy = accuracy; self.speed = speed; self.badge = badge
    }

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
        ], defaultModelID: "ivrit-large-v3-turbo")
    }
}

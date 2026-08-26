import Foundation

public enum ModelValidation: Equatable {
    case ok
    case missing
    case tooSmall
    case badMagic
}

public struct ModelSpec {
    public let fileName: String
    public let url: URL
    public let minSizeBytes: Int

    private static let ggmlMagic: UInt32 = 0x67676D6C  // "ggml"

    public init(fileName: String, url: URL, minSizeBytes: Int) {
        self.fileName = fileName
        self.url = url
        self.minSizeBytes = minSizeBytes
    }

    public static let ivritTurbo = ModelSpec(
        fileName: "ggml-ivrit-large-v3-turbo.bin",
        url: URL(string: "https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin")!,
        minSizeBytes: 1_500_000_000
    )

    public func validate(fileAt url: URL) -> ModelValidation {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int else {
            return .missing
        }
        guard size >= minSizeBytes else { return .tooSmall }
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 4), head.count == 4 else {
            return .badMagic
        }
        let magic = head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return magic.littleEndian == Self.ggmlMagic ? .ok : .badMagic
    }
}

/// How the recording UI is presented while dictating.
public enum RecordingDisplay: String, Codable, CaseIterable {
    /// Floating card near the bottom of the screen.
    case panel
    /// Bar hugging the top of the screen, merging with the MacBook notch where there
    /// is one and rendering as a floating top bar where there isn't.
    case notch

    public var displayName: String {
        switch self {
        case .panel: return "Panel"
        case .notch: return "Notch"
        }
    }
}

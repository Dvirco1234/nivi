import Foundation

/// Where one saved transcription came from.
public enum HistorySource: String, Codable, CaseIterable, Sendable {
    case dictation
    case file
    case modelTest

    public var displayName: String {
        switch self {
        case .dictation: return "Dictation"
        case .file: return "File"
        case .modelTest: return "Model test"
        }
    }
}

/// One saved transcription.
///
/// Only text is kept. Audio is never stored, because a month of daily dictation would
/// be gigabytes of samples while the same month of text is under two megabytes.
public struct HistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var text: String
    /// How long the audio was, not how long transcribing it took.
    public var durationMs: Int
    public var source: HistorySource
    public var modelID: String
    public var language: String
    /// Empty for jobs that do not run through a profile, such as a transcribed file.
    public var profileID: String?
    /// The file name for a file job, or the front app name for a dictation.
    public var sourceName: String?

    public init(id: String = UUID().uuidString,
                createdAt: Date = Date(),
                text: String,
                durationMs: Int,
                source: HistorySource,
                modelID: String,
                language: String,
                profileID: String? = nil,
                sourceName: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.durationMs = durationMs
        self.source = source
        self.modelID = modelID
        self.language = language
        self.profileID = profileID
        self.sourceName = sourceName
    }
}

/// Reading and writing the history file, which is one JSON object per line.
///
/// One line per record means saving a dictation is a single append at the end of the
/// file. A crash in the middle of a write costs at most the last line, and that broken
/// line is skipped on read instead of making the whole file unreadable.
public enum HistoryFile {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Epoch seconds so a line stays readable and stays the same size forever.
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    /// One record as a single line, with no trailing newline.
    public static func line(for record: HistoryRecord) -> String? {
        guard let data = try? makeEncoder().encode(record) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Parses a whole file. Lines that do not parse are skipped rather than failing the read.
    public static func records(fromFileText text: String) -> [HistoryRecord] {
        let decoder = makeDecoder()
        var result: [HistoryRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let record = try? decoder.decode(HistoryRecord.self, from: data) else { continue }
            result.append(record)
        }
        return result
    }

    /// The whole list back as file text, ending with a newline so the next append starts a line.
    public static func fileText(for records: [HistoryRecord]) -> String {
        let lines = records.compactMap { line(for: $0) }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
}

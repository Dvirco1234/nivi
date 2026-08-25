import Foundation

/// Which files the "Transcribe a file" tab can open.
///
/// A plain table of extensions rather than UTType, because this file has to compile with
/// Foundation alone. Everything listed here is decoded by the system's own Core Media
/// decoders, so there is no extra dependency behind it.
public enum TranscribableFormat {
    public static let supportedExtensions: [String] = [
        "wav", "aif", "aiff", "aifc", "caf",
        "mp3", "m4a", "m4b", "aac", "flac",
        "mp4", "mov", "m4v",
    ]

    /// Short names for the grey chips under the drop zone.
    public static let displayNames: [String] = [
        "MP3", "WAV", "M4A", "AAC", "AIFF", "CAF", "FLAC", "MP4", "MOV", "M4V",
    ]

    /// Formats people try that the system cannot decode. Named so the error can say why
    /// instead of failing with nothing useful.
    public static let knownUnsupportedExtensions: [String] = [
        "ogg", "oga", "opus", "webm", "wma", "amr", "mkv",
    ]

    public static func isSupported(fileExtension: String) -> Bool {
        supportedExtensions.contains(normalize(fileExtension))
    }

    public static func isKnownUnsupported(fileExtension: String) -> Bool {
        knownUnsupportedExtensions.contains(normalize(fileExtension))
    }

    private static func normalize(_ fileExtension: String) -> String {
        var value = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasPrefix(".") { value.removeFirst() }
        return value
    }
}

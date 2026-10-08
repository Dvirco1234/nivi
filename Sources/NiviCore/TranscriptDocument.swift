import Foundation

/// Breaks a long transcript into readable paragraphs.
///
/// whisper returns one run of text with no line breaks, and a file transcript is many of
/// those runs glued together. Saved that way, a 45 minute recording became a single line
/// of 67,248 characters. That crashed the app the moment someone clicked into it to copy
/// a sentence: AppKit's text field editor lays the whole paragraph out as one line, and
/// Core Text gives up somewhere past 10,000 characters (October 2026). One line that long
/// is also unreadable in Word.
///
/// Paragraphs are cut after a full stop, question mark or exclamation mark, once they are
/// long enough to read as a paragraph. A stretch with no sentence ending at all, which
/// whisper produces now and then, is cut at a space so nothing is ever longer than
/// `maximumLength`.
public enum TranscriptParagraphs {
    /// A paragraph is closed at the first sentence end after this many characters.
    public static let targetLength = 600
    /// No paragraph is ever longer than this.
    public static let maximumLength = 2_000

    public static func split(_ text: String) -> [String] {
        existingParagraphs(of: text).flatMap(group)
    }

    /// The paragraphs separated by a blank line, which is how they are stored and copied.
    public static func format(_ text: String) -> String {
        split(text).joined(separator: "\n\n")
    }

    /// Keeps breaks that are already there, so formatting twice changes nothing.
    private static func existingParagraphs(of text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func group(_ paragraph: String) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { result.append(current) }
            current = ""
        }
        for sentence in sentences(of: paragraph).flatMap(cutToMaximum) {
            if !current.isEmpty && current.count + 1 + sentence.count > maximumLength { flush() }
            current += current.isEmpty ? sentence : " " + sentence
            if current.count >= targetLength { flush() }
        }
        flush()
        return result
    }

    /// Splits after `.`, `?`, `!` or `…` when a space follows. The space is dropped, which
    /// is why joining with a single space gives the text back.
    private static func sentences(of paragraph: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previousEndsSentence = false
        for character in paragraph {
            if character.isWhitespace && previousEndsSentence {
                result.append(current)
                current = ""
                previousEndsSentence = false
                continue
            }
            current.append(character)
            previousEndsSentence = ".?!…".contains(character)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// A "sentence" longer than the maximum is cut at spaces. A single word longer than the
    /// maximum, which only a broken transcript could contain, is cut wherever it has to be.
    private static func cutToMaximum(_ sentence: String) -> [String] {
        guard sentence.count > maximumLength else { return [sentence] }
        var pieces: [String] = []
        var current = ""
        for word in sentence.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            if !current.isEmpty && current.count + 1 + word.count > maximumLength {
                pieces.append(current)
                current = ""
            }
            if word.count > maximumLength {
                var rest = Substring(word)
                while rest.count > maximumLength {
                    pieces.append(String(rest.prefix(maximumLength)))
                    rest = rest.dropFirst(maximumLength)
                }
                current = String(rest)
            } else {
                current += current.isEmpty ? word : " " + word
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}

/// Which way a piece of text reads, judged by its letters.
///
/// Word and the other document formats need to be told a paragraph is right to left, or
/// they line Hebrew up on the left. A Hebrew sentence often contains an English name or a
/// number, so the answer is whichever kind of letter there is more of.
public enum TextDirection {
    public static func isRightToLeft(_ text: String) -> Bool {
        var rightToLeft = 0
        var leftToRight = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            if isRightToLeftLetter(scalar) { rightToLeft += 1 } else { leftToRight += 1 }
        }
        return rightToLeft > leftToRight
    }

    /// Hebrew, Arabic and their presentation forms.
    private static func isRightToLeftLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
        default: return false
        }
    }
}

/// The kinds of file a transcript can be saved as.
///
/// All four are written by macOS itself, so saving needs no extra library.
public enum TranscriptFormat: String, CaseIterable, Sendable {
    case plainText
    case word
    case richText
    case openDocument

    public var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .word: return "docx"
        case .richText: return "rtf"
        case .openDocument: return "odt"
        }
    }

    /// What the Save as menu says.
    public var menuTitle: String {
        switch self {
        case .plainText: return "Text (.txt)"
        case .word: return "Word (.docx)"
        case .richText: return "Rich Text (.rtf)"
        case .openDocument: return "OpenDocument (.odt)"
        }
    }
}

public enum TranscriptExport {
    /// "meeting.mp4" becomes "meeting transcript.docx".
    public static func suggestedFileName(sourceName: String?, format: TranscriptFormat) -> String {
        let trimmed = (sourceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmed as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !base.isEmpty else { return "Transcript.\(format.fileExtension)" }
        return "\(base) transcript.\(format.fileExtension)"
    }
}

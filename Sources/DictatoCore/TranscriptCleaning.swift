import Foundation

/// Removes the notes Whisper writes when it does not hear speech.
///
/// When a Whisper model hears silence, music, or speech it cannot place, it does not
/// return nothing. It returns a note about it, such as `[BLANK_AUDIO]`,
/// `(speaking foreign language)` or `*clears throat*`. Those are not words anyone said,
/// so they must never be pasted into a document or saved.
///
/// whisper.cpp does not produce these strings itself. They come from the model, which is
/// why its own Python example ends with
/// `decoded_str.replace('[BLANK_AUDIO]', '').strip()`. The bracket, parenthesis, asterisk
/// and musical note characters the models use for these notes are the same ones listed in
/// `non_speech_tokens` in `src/whisper.cpp`.
///
/// The rule is deliberately careful. Someone dictating "put it in brackets like [this]"
/// keeps their brackets. Only a bracketed piece that reads like one of these notes is
/// dropped, and if the sentence still has real words in it, those words stay.
public enum TranscriptCleaning {

    /// The whole content of a bracketed piece, lowercased, that is only ever a note.
    private static let exactNotes: Set<String> = [
        "blank audio", "blank_audio", "blank",
        "silence", "silent", "no speech", "no audio", "pause",
        "music", "musique", "music playing", "music continues",
        "inaudible", "unintelligible", "indistinct", "indistinct chatter", "chatter",
        "noise", "background noise", "static", "beep", "beeping",
        "applause", "cheering", "laughter", "laughs", "laughing", "chuckles",
        "coughs", "coughing", "clears throat", "throat clearing", "sighs", "sniffs",
        "breathing", "heavy breathing", "footsteps", "wind", "wind blowing",
        "typing", "keyboard clicking", "phone ringing", "door closes", "engine running",
        "crowd noise", "crowd cheering", "sound effect", "sound effects",
        "foreign language", "speaking foreign language", "speaking in foreign language",
        "non-english speech", "non english speech", "speaking softly", "whispering",
    ]

    /// Word endings that make a short piece a note, such as "gentle music" or
    /// "background noise".
    private static let noteEndings = [" music", " noise", " sounds", " sound",
                                      " chatter", " laughter", " applause"]

    /// The pieces a note can be wrapped in. Nested brackets are not matched on purpose:
    /// the notes never nest, and a greedy match would swallow real text between two of
    /// them.
    private static let wrappedPiece = try? NSRegularExpression(
        pattern: "\\[[^\\[\\]]*\\]|\\([^()]*\\)|\\*[^*]*\\*|♪[^♪]*♪|♪+",
        options: [])

    /// The transcript with any of these notes taken out.
    ///
    /// Returns an empty string when the whole transcript was one of them, which the
    /// caller should treat exactly like hearing nothing at all.
    public static func clean(_ text: String) -> String {
        guard let wrappedPiece else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let full = text as NSString
        let matches = wrappedPiece.matches(in: text, options: [],
                                           range: NSRange(location: 0, length: full.length))
        var result = ""
        var readFrom = 0
        for match in matches {
            let piece = full.substring(with: match.range)
            guard isNote(piece) else { continue }
            result += full.substring(with: NSRange(location: readFrom,
                                                   length: match.range.location - readFrom))
            result += " "
            readFrom = match.range.location + match.range.length
        }
        result += full.substring(from: readFrom)
        return tidy(result)
    }

    /// True when nothing real is left after the notes are taken out.
    public static func isOnlyNoise(_ text: String) -> Bool {
        clean(text).isEmpty
    }

    /// Whether one bracketed piece, including its brackets, is one of these notes.
    private static func isNote(_ piece: String) -> Bool {
        let inner = String(piece.dropFirst().dropLast())
        let trimmed = inner.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,!?…-–—_")))

        // Bare musical notes, which is how a model marks a stretch of music.
        if piece.allSatisfy({ "♪♫♬".contains($0) }) { return true }
        if trimmed.isEmpty { return !piece.isEmpty && piece.count <= 2 }

        // BLANK_AUDIO and its friends: shouted, with underscores, never a real sentence.
        let looksLikeAToken = trimmed.allSatisfy {
            $0.isUppercase || $0 == "_" || $0 == " " || $0.isNumber
        }
        let lower = trimmed.lowercased()
        if looksLikeAToken && (exactNotes.contains(lower) || lower.contains("_")) { return true }

        if exactNotes.contains(lower) { return true }

        // Short descriptions such as "gentle music" or "speaking in a foreign language".
        // The word limit keeps a real aside like "(see the music section of the report)"
        // out of it: leaving one note through is better than eating someone's words.
        let words = lower.split(separator: " ")
        guard words.count <= 5 else { return false }
        if lower.hasPrefix("speaking ") { return true }
        if noteEndings.contains(where: { lower.hasSuffix($0) }) { return true }
        return false
    }

    /// Closes the gap a removed note leaves behind: no double spaces, no space in front of
    /// a comma or a full stop, and nothing hanging off either end.
    private static func tidy(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        for character in text {
            let isSpace = character == " " || character == "\t"
            if isSpace {
                lastWasSpace = true
                continue
            }
            if lastWasSpace, !out.isEmpty, !",.!?;:".contains(character) {
                out.append(" ")
            }
            lastWasSpace = false
            out.append(character)
        }
        // Newlines from the model survive, but a line that is now empty should not.
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

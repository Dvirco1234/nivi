import Foundation

/// Removes the notes a Whisper model writes about sounds instead of speech.
///
/// When a model hears silence, music, a cough or a room full of people, it does not
/// return nothing. It returns a note about it, wrapped in brackets, parentheses,
/// asterisks or musical notes: `[BLANK_AUDIO]`, `(people chattering)`, `(gentle music)`,
/// `*clears throat*`, `♪`. Nivi turns speech into text and nothing else, so a note
/// like that is never something the user said and must never be pasted or saved.
///
/// ## Why every wrapped piece goes, and not only known ones
///
/// The first version of this file matched a list of known phrases. The list can never be
/// complete. Models invent new notes freely, and `(people chattering)` reached a user's
/// document because it was not on the list. So the rule is now about the shape, not the
/// words: **anything fully wrapped in `[]`, `()`, `**` or `♪♪` is a note and is removed.**
///
/// The obvious worry is eating text the user really dictated. In practice that almost
/// never happens, for two reasons:
///
/// - Nobody speaks a standalone parenthetical. To get brackets on purpose you say the
///   punctuation out loud ("open bracket"), and the model writes those as the words you
///   said, not as the symbol. So a bracket in the output nearly always came from the
///   model, not from the speaker.
/// - The cost is not symmetric. A dropped aside is a missing few words the user can say
///   again. A note that gets through is fake text in someone's Slack message.
///
/// A user who disagrees can turn the whole thing off with one setting, which is why
/// `clean` takes `removeSoundDescriptions`.
///
/// ## Why this works on plain text, not on Whisper's segments
///
/// A note is usually a segment of its own, which would be a useful extra signal. It is
/// not used here on purpose. Cleaning also runs over History entries loaded from disk,
/// where only the text was ever saved, and over the joined text of the streaming and file
/// paths. Making the rule depend on segments would mean the same sentence is cleaned two
/// different ways depending on where it came from. One rule over text is easier to trust.
public enum TranscriptCleaning {

    /// Musical note characters. Models use these for a stretch of music, sometimes bare
    /// and sometimes around a lyric, and they are never dictated.
    private static let musicalNotes: Set<Character> = ["♪", "♫", "♬"]

    /// A piece wrapped in brackets, parentheses, asterisks or musical notes.
    ///
    /// Words between two musical notes go with them. That is a lyric the model heard
    /// playing in the room, not something the user dictated.
    ///
    /// Nested pairs are not matched on purpose: notes never nest, and a greedy match
    /// would swallow the real words sitting between two separate notes.
    private static let wrappedPiece = try? NSRegularExpression(
        pattern: "\\[[^\\[\\]]*\\]|\\([^()]*\\)|\\*[^*\\n]*\\*|[♪♫♬][^♪♫♬\\n]*[♪♫♬]",
        options: [])

    /// The transcript with the model's sound notes taken out.
    ///
    /// Returns an empty string when the whole transcript was notes, which the caller
    /// should treat exactly like hearing nothing at all.
    ///
    /// - Parameter removeSoundDescriptions: the user's setting. When off, only spacing is
    ///   tidied and every wrapped piece is left alone.
    public static func clean(_ text: String, removeSoundDescriptions: Bool = true) -> String {
        guard removeSoundDescriptions, let wrappedPiece else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let full = text as NSString
        let matches = wrappedPiece.matches(in: text, options: [],
                                           range: NSRange(location: 0, length: full.length))
        var result = ""
        var readFrom = 0
        for match in matches {
            result += full.substring(with: NSRange(location: readFrom,
                                                   length: match.range.location - readFrom))
            result += " "
            readFrom = match.range.location + match.range.length
        }
        result += full.substring(from: readFrom)
        // Bare musical notes are left over wherever they were not part of a pair, and a
        // single ♪ on its own line is the common case. They become a space rather than
        // nothing, so one sitting between two words does not glue them together.
        result = String(result.map { musicalNotes.contains($0) ? " " : $0 })
        return tidy(result)
    }

    /// True when nothing real is left after the notes are taken out.
    public static func isOnlyNoise(_ text: String, removeSoundDescriptions: Bool = true) -> Bool {
        clean(text, removeSoundDescriptions: removeSoundDescriptions).isEmpty
    }

    /// Closes the gap a removed note leaves behind: no double spaces, no space in front of
    /// a comma or a full stop, no punctuation left stranded at the start of a line, and
    /// nothing hanging off either end.
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
        // Newlines from the model survive, but a line that is now empty, or that is only
        // the punctuation that used to follow a note, should not.
        let leftovers = CharacterSet(charactersIn: ",.!?;:-–—…\"' ")
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Only drop a line that is nothing but punctuation. A real sentence keeps
                // its full stop.
                return trimmed.unicodeScalars.allSatisfy(leftovers.contains) ? "" : trimmed
            }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

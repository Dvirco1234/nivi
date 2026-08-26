import Foundation

/// Turns what the model returned into the text that goes to the user.
///
/// Two steps run here, and the order matters:
///
/// 1. `TranscriptCleaning` first, because the notes a model writes for silence and music
///    are not words anyone said. Dropping them first means a word rule never has to work
///    around `[BLANK_AUDIO]`, and a rule can never rescue a note by replacing part of it.
/// 2. `WordReplacing` second, so the user's rules see the finished sentence. Cleaning
///    also closes up the gaps a removed note leaves behind, so a whole-word rule matches
///    across the place where a note used to be.
///
/// Everything the user reads, pastes and keeps in History goes through this one function,
/// so the saved text and the pasted text can never differ.
public enum TranscriptFinishing {
    public static func finish(_ text: String,
                              rules: [WordReplacement],
                              removeSoundDescriptions: Bool = true) -> String {
        WordReplacing.apply(rules, to: TranscriptCleaning.clean(
            text, removeSoundDescriptions: removeSoundDescriptions))
    }
}

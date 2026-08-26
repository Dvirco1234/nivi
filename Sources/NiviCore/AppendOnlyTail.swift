import Foundation

/// The text to append so that `alreadyTyped` grows toward `fullText` without ever
/// deleting or rewriting what was already typed.
///
/// In-app-live has already committed `alreadyTyped` to the user's document and there
/// is no reliable way to take it back, so the seam between the streamed text and the
/// authoritative final transcript can only ever be closed by adding.
///
/// The match is made on *words*, not characters: each pass re-transcribes the whole
/// buffer with more context, so whisper routinely re-punctuates and re-capitalizes
/// words it already emitted ("hello world this is" → "Hello, world. This is a test.").
/// A character offset into one string is meaningless in the other and would re-emit a
/// fragment of an already-typed word. Comparing words with punctuation and case
/// ignored finds the real seam and lands on a word boundary.
///
/// Returns "" when there is nothing safe to add, and includes any needed leading space.
public func appendOnlyTail(alreadyTyped: String, fullText: String) -> String {
    let typedWords = words(of: alreadyTyped)
    let finalWords = words(of: fullText)
    guard !finalWords.isEmpty else { return "" }

    // How much of the final text is already in the document. Anything at or before
    // this point must not be re-emitted.
    var shared = 0
    while shared < typedWords.count, shared < finalWords.count,
          normalized(typedWords[shared]) == normalized(finalWords[shared]) {
        shared += 1
    }

    // shared == 0 with something already typed means the final text diverges from the
    // very first word. We still append all of it: we cannot retract what was typed,
    // and dropping the final text would silently lose what the user said.
    let tail = finalWords.dropFirst(shared)
    guard !tail.isEmpty else { return "" }

    let joined = tail.joined(separator: " ")
    if alreadyTyped.isEmpty || alreadyTyped.last?.isWhitespace == true { return joined }
    return " " + joined
}

private func words(of text: String) -> [String] {
    text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
}

/// Case- and punctuation-insensitive form used only for matching, never for output.
private func normalized(_ word: String) -> String {
    String(word.lowercased().unicodeScalars.filter {
        CharacterSet.alphanumerics.contains($0)
    })
}

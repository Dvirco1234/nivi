import Foundation

/// The small pieces of arithmetic behind transcribing a long file in parts.
///
/// Kept here, away from the audio code, so the joining rule and the time estimate can be
/// tested without a file, a model, or a Mac with a microphone.
public enum ChunkedTranscription {

    /// Puts the pieces back together with a single space between them.
    ///
    /// Empty pieces are dropped, which happens when a chunk falls in a silent stretch.
    /// Without that a quiet file comes back full of double spaces.
    public static func join(_ pieces: [String]) -> String {
        pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// A rough guess at the seconds still to go, from the pieces already done.
    ///
    /// Returns nil until at least one piece has finished, because before that there is
    /// nothing to base a guess on and a made-up number is worse than none.
    public static func secondsLeft(chunksDone: Int, chunkCount: Int, elapsedSeconds: Double) -> Double? {
        guard chunksDone > 0, chunkCount > chunksDone, elapsedSeconds > 0 else { return nil }
        let perChunk = elapsedSeconds / Double(chunksDone)
        return perChunk * Double(chunkCount - chunksDone)
    }

    /// The line shown next to the progress bar.
    public static func progressLine(chunksDone: Int, chunkCount: Int, elapsedSeconds: Double) -> String {
        let current = min(chunksDone + 1, chunkCount)
        var line = "Part \(current) of \(chunkCount)"
        if let left = secondsLeft(chunksDone: chunksDone,
                                  chunkCount: chunkCount,
                                  elapsedSeconds: elapsedSeconds) {
            line += ", about \(DurationFormatting.short(left)) left"
        }
        return line
    }
}

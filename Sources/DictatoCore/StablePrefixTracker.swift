import Foundation

/// Turns a sequence of whole-buffer transcripts into a monotonically growing
/// "committed" word prefix.
///
/// Each streaming pass re-transcribes the whole recording, so earlier words can
/// change as later context arrives. A word is only safe to show as final once it
/// has survived several consecutive passes unchanged. The committed prefix never
/// shrinks: In-app-live has already typed those words into the user's document
/// and there is no reliable way to take them back, so retracting would be a lie.
public struct StablePrefixTracker {
    private let stabilityPasses: Int
    private var history: [[String]] = []
    private var committed: [String] = []

    public init(stabilityPasses: Int = 2) {
        self.stabilityPasses = max(1, stabilityPasses)
    }

    public mutating func update(_ fullText: String) -> String {
        let words = fullText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        history.append(words)
        if history.count > stabilityPasses { history.removeFirst() }

        if history.count == stabilityPasses {
            let shortest = history.map(\.count).min() ?? 0
            var stable = 0
            while stable < shortest {
                let word = history[0][stable]
                guard history.allSatisfy({ $0[stable] == word }) else { break }
                stable += 1
            }
            if stable > committed.count {
                committed = Array(words.prefix(stable))
            }
        }
        return committed.joined(separator: " ")
    }
}

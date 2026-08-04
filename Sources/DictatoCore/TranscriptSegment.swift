import Foundation

/// One timestamped chunk of transcript. Times are relative to the start of the samples
/// that produced them, not to the whole recording — the caller knows the window offset
/// and converts to absolute positions itself.
public struct TranscriptSegment: Equatable {
    public let text: String
    public let startMs: Int
    public let endMs: Int

    public init(text: String, startMs: Int, endMs: Int) {
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
    }
}

import Foundation

/// Tracks which part of a recording the live preview still re-transcribes, and the text
/// for the part that has scrolled out of it.
///
/// Re-transcribing the whole recording every pass gets slower the longer you speak, so the
/// live loop only looks at a trailing window. That means committing to text for the audio
/// falling out of the window. Freezing happens on whole segment boundaries because segment
/// timestamps are the only way to know which words belong to which audio — splitting
/// anywhere else would duplicate or drop words at the seam.
public struct StreamWindow {
    /// Transcript for audio that has scrolled out of the live window. Never revised.
    public private(set) var frozenText: String = ""
    /// Offset into the recording where the live window begins. Only ever moves forward.
    public private(set) var windowStartSample: Int = 0

    public init() {}

    /// Folds one pass's segments into the window, returning the full live text
    /// (frozen text plus the current window's text).
    public mutating func advance(segments: [TranscriptSegment],
                                 windowSampleCount: Int,
                                 maxWindowSamples: Int,
                                 sampleRate: Int) -> String {
        // A failed or silent pass tells us nothing; freezing on it would commit to text we
        // never actually saw.
        guard !segments.isEmpty else { return frozenText }

        var frozenCount = 0
        if windowSampleCount > maxWindowSamples {
            let excessSamples = windowSampleCount - maxWindowSamples
            let excessMs = excessSamples * 1000 / sampleRate
            // Never freeze the last segment: it is still being spoken and its text will
            // keep changing. If it alone overflows the window, the window simply runs long
            // for a while — a correct seam matters more than an exact window size.
            //
            // Freeze leading segments in order until the frozen boundary reaches or passes
            // the excess, including the segment that crosses the threshold: freezing a
            // segment whose end is already past the excess still brings the window back
            // under the cap, and stopping earlier would leave it over.
            while frozenCount < segments.count - 1 {
                frozenCount += 1
                if segments[frozenCount - 1].endMs >= excessMs { break }
            }
            if frozenCount > 0 {
                let newlyFrozen = segments[0..<frozenCount]
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                frozenText = Self.join(frozenText, newlyFrozen.joined(separator: " "))
                windowStartSample += segments[frozenCount - 1].endMs * sampleRate / 1000
            }
        }

        // Only the segments still inside the window: the frozen ones are already in
        // `frozenText`, and including them again here would duplicate them in the preview.
        let windowText = segments.dropFirst(frozenCount)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return Self.join(frozenText, windowText)
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }
        return lhs + " " + rhs
    }
}

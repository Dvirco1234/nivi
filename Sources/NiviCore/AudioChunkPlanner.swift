import Foundation

/// Works out where to split a long recording before transcribing it.
///
/// whisper.cpp can swallow an hour in one call, but then there is no progress to show and
/// no way to stop. Splitting the audio gives both. The cost is a little accuracy at each
/// cut, because the model loses the words either side of it, so the cut is moved into the
/// quietest moment nearby.
public enum AudioChunkPlanner {
    /// The smallest tail we are willing to leave as its own chunk, as a share of a full
    /// chunk. A two second last chunk transcribes badly and is not worth a separate pass.
    private static let minimumTailShare: Double = 0.25

    /// Cut positions in samples, not counting the start and the end.
    ///
    /// Chunk 1 is `0 ..< cuts[0]`, chunk 2 is `cuts[0] ..< cuts[1]`, and the last chunk
    /// runs to `sampleCount`. An empty result means "transcribe it in one pass".
    public static func cutPoints(sampleCount: Int, sampleRate: Int, chunkSeconds: Int) -> [Int] {
        guard sampleCount > 0, sampleRate > 0, chunkSeconds > 0 else { return [] }
        let chunkSamples = sampleRate * chunkSeconds
        guard sampleCount > chunkSamples else { return [] }

        var cuts: [Int] = []
        var next = chunkSamples
        while next < sampleCount {
            cuts.append(next)
            next += chunkSamples
        }
        if let last = cuts.last,
           Double(sampleCount - last) < Double(chunkSamples) * minimumTailShare {
            cuts.removeLast()
        }
        return cuts
    }

    /// The same cuts, each moved to the quietest short window near it.
    ///
    /// `searchSeconds` is how far either side of the even cut we are allowed to move.
    /// `quietWindowSeconds` is how long a pause we look for.
    public static func cutPoints(samples: [Float],
                                 sampleRate: Int,
                                 chunkSeconds: Int,
                                 searchSeconds: Double = 10,
                                 quietWindowSeconds: Double = 0.2) -> [Int] {
        let even = cutPoints(sampleCount: samples.count,
                             sampleRate: sampleRate,
                             chunkSeconds: chunkSeconds)
        guard !even.isEmpty else { return [] }

        let searchSamples = max(1, Int(searchSeconds * Double(sampleRate)))
        let windowSamples = max(1, Int(quietWindowSeconds * Double(sampleRate)))

        var result: [Int] = []
        var previous = 0
        for cut in even {
            let lowerLimit = max(previous + windowSamples, cut - searchSamples)
            let upperLimit = min(samples.count - windowSamples, cut + searchSamples)
            guard lowerLimit < upperLimit else {
                result.append(cut)
                previous = cut
                continue
            }
            let quiet = quietestWindowStart(in: samples,
                                            from: lowerLimit,
                                            to: upperLimit,
                                            windowSamples: windowSamples)
            let moved = min(samples.count - 1, quiet + windowSamples / 2)
            let safe = max(previous + 1, moved)
            result.append(safe)
            previous = safe
        }
        return result
    }

    /// Start index of the window with the least sound in it.
    ///
    /// Uses a running total so the search costs one pass over the band rather than one
    /// pass per candidate window.
    private static func quietestWindowStart(in samples: [Float],
                                            from lowerLimit: Int,
                                            to upperLimit: Int,
                                            windowSamples: Int) -> Int {
        var runningTotal: Double = 0
        for index in lowerLimit..<(lowerLimit + windowSamples) {
            runningTotal += Double(abs(samples[index]))
        }
        var bestTotal = runningTotal
        var bestStart = lowerLimit

        var start = lowerLimit + 1
        while start <= upperLimit {
            runningTotal -= Double(abs(samples[start - 1]))
            runningTotal += Double(abs(samples[start + windowSamples - 1]))
            if runningTotal < bestTotal {
                bestTotal = runningTotal
                bestStart = start
            }
            start += 1
        }
        return bestStart
    }
}

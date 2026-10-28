import Foundation

/// The model ids a cache holds, oldest use first, and which of them to unload when the
/// cache is over capacity.
///
/// This is the bookkeeping behind `RecognizerCache`, kept here so it can be tested
/// without loading a model. The cache owns the models and the waiting; this owns the order.
///
/// ## Why adding an id that is already here must not add it twice
///
/// In October 2026 two callers loaded the same model at the same moment, and each one
/// added its id when its load finished. The order then held the id twice. At capacity 1
/// the "oldest" entry was that same id, so the cache unloaded the model it had just
/// stored and handed it out anyway. The dictation failed with
/// `Inference failed: Model not loaded`. So `insert` treats an id it already holds as a
/// use, never as a second entry, and never names the id it was given as one to unload.
public struct RecentlyUsedOrder {
    /// Oldest use first, most recent last. Each id appears at most once.
    public private(set) var ids: [String] = []

    public init() {}

    /// Marks `id` as the most recent use, if it is here.
    public mutating func touch(_ id: String) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.remove(at: index)
        ids.append(id)
    }

    /// Adds `id` as the most recent use and returns the ids that no longer fit, oldest
    /// first. The caller unloads those. `id` itself is never in the result.
    public mutating func insert(_ id: String, capacity: Int) -> [String] {
        ids.removeAll { $0 == id }
        ids.append(id)
        return trim(to: capacity)
    }

    /// Drops the oldest ids until at most `capacity` remain, and returns them.
    public mutating func trim(to capacity: Int) -> [String] {
        let overflow = ids.count - max(1, capacity)
        guard overflow > 0 else { return [] }
        let evicted = Array(ids.prefix(overflow))
        ids.removeFirst(overflow)
        return evicted
    }

    public mutating func removeAll() {
        ids.removeAll()
    }
}

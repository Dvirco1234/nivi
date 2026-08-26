import Foundation

/// What the History tab is currently showing.
public struct HistoryQuery: Equatable, Sendable {
    public var searchText: String
    /// Which kinds of entry to show. `nil` means all of them.
    public var sources: Set<HistorySource>?
    public var newestFirst: Bool

    public init(searchText: String = "",
                sources: Set<HistorySource>? = nil,
                newestFirst: Bool = true) {
        self.searchText = searchText
        self.sources = sources
        self.newestFirst = newestFirst
    }
}

public enum HistoryFiltering {
    /// Filters and sorts in memory. A few thousand short records is small enough that
    /// there is no reason to index anything.
    public static func apply(_ query: HistoryQuery, to records: [HistoryRecord]) -> [HistoryRecord] {
        var result = records

        if let sources = query.sources {
            result = result.filter { sources.contains($0.source) }
        }

        let needle = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            // localizedStandardContains ignores case and accents, which is what someone
            // typing a quick search expects.
            result = result.filter {
                $0.text.localizedStandardContains(needle)
                    || ($0.sourceName?.localizedStandardContains(needle) ?? false)
            }
        }

        result.sort { left, right in
            if left.createdAt == right.createdAt { return left.id < right.id }
            return query.newestFirst ? left.createdAt > right.createdAt
                                     : left.createdAt < right.createdAt
        }
        return result
    }
}

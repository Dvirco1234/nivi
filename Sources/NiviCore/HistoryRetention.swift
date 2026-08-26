import Foundation

/// Decides which saved transcriptions are old enough to drop.
public enum HistoryRetention {
    /// Number of days for each option the picker offers. Zero means keep everything.
    public static let dayOptions: [Int] = [7, 30, 90, 365, 0]

    public static func optionLabel(days: Int) -> String {
        switch days {
        case 0: return "Keep forever"
        case 1: return "1 day"
        case 365: return "1 year"
        default: return "\(days) days"
        }
    }

    /// Returns the records to keep, in the order they came in.
    ///
    /// A record is kept while it is younger than the limit. `retentionDays == 0` keeps
    /// everything, and a negative value is treated the same way so a bad stored number
    /// can never wipe someone's history.
    public static func keeping(_ records: [HistoryRecord],
                               retentionDays: Int,
                               now: Date) -> [HistoryRecord] {
        guard retentionDays > 0 else { return records }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return records.filter { $0.createdAt >= cutoff }
    }
}

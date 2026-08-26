import Foundation

/// Turns a length in seconds into something short enough to sit in a grey chip.
///
/// Written by hand rather than with DateComponentsFormatter so the same string comes out
/// on every machine. The formatter follows the user's locale, which would make the
/// History list read differently for different people and would be untestable here.
public enum DurationFormatting {
    /// "10 seconds", "1 min 12 s", "1 h 04 m".
    public static func short(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 seconds" }
        let total = Int(seconds.rounded())

        if total < 60 {
            return total == 1 ? "1 second" : "\(total) seconds"
        }
        if total < 3600 {
            let minutes = total / 60
            let rest = total % 60
            return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return "\(hours) h \(String(format: "%02d", minutes)) m"
    }

    /// A counter that reads like a stopwatch: "0:07", "1:23", "12:05".
    ///
    /// Hours only appear once the recording really passes an hour ("1:04:09"), so a normal
    /// dictation of a few seconds is not padded out with zeros it never needs.
    ///
    /// Seconds are rounded down, not to nearest, because a counter that starts at "0:01"
    /// the moment you press the key looks like it lost a second.
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let minutes = (total % 3600) / 60
        let rest = total % 60
        if total < 3600 {
            return String(format: "%d:%02d", minutes, rest)
        }
        return String(format: "%d:%02d:%02d", total / 3600, minutes, rest)
    }

    public static func short(milliseconds: Int) -> String {
        short(Double(milliseconds) / 1000)
    }
}

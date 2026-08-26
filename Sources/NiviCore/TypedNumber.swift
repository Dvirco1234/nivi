import Foundation

/// Reading a number that a person typed into a small box in Preferences.
///
/// Kept out of the view so the awkward cases can be tested: letters, an empty box, and
/// numbers outside what the setting allows.
public enum TypedNumber {
    /// The number the text stands for, held inside `range`.
    ///
    /// Returns nil when the text is not a whole number at all. The caller puts the
    /// previous value back in that case, so an empty box or a stray letter never writes a
    /// zero into a setting.
    ///
    /// A number outside the range is not refused, it is pulled to the nearest end: someone
    /// typing 999 into a box that stops at 30 means "as high as it goes".
    public static func read(_ text: String, in range: ClosedRange<Int>) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let typed = Int(trimmed) else { return nil }
        return min(max(typed, range.lowerBound), range.upperBound)
    }
}

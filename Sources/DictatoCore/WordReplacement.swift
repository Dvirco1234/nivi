import Foundation

/// One "when you say this, write that instead" rule.
public struct WordReplacement: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var find: String
    public var replaceWith: String
    /// When true, "cat" does not match inside "category".
    public var matchWholeWord: Bool
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString,
                find: String,
                replaceWith: String,
                matchWholeWord: Bool = true,
                isEnabled: Bool = true) {
        self.id = id
        self.find = find
        self.replaceWith = replaceWith
        self.matchWholeWord = matchWholeWord
        self.isEnabled = isEnabled
    }
}

public enum WordReplacing {
    /// Applies every enabled rule to the text, in the order the rules are listed.
    ///
    /// Matching ignores case. The replacement is written exactly as the user typed it,
    /// so a rule can also be used to fix capitalisation.
    public static func apply(_ rules: [WordReplacement], to text: String) -> String {
        var result = text
        for rule in rules where rule.isEnabled && !rule.find.isEmpty {
            result = applyOne(rule, to: result)
        }
        return result
    }

    private static func applyOne(_ rule: WordReplacement, to text: String) -> String {
        guard rule.matchWholeWord else {
            return text.replacingOccurrences(of: rule.find,
                                             with: rule.replaceWith,
                                             options: [.caseInsensitive])
        }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: rule.find) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let template = NSRegularExpression.escapedTemplate(for: rule.replaceWith)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    public static func decode(json: String) -> [WordReplacement] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WordReplacement].self, from: data)) ?? []
    }

    public static func encode(_ rules: [WordReplacement]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

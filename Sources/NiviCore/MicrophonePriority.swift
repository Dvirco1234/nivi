import Foundation

/// The user's ordered list of microphones, and the rule for picking one from it.
///
/// The list holds unique device ids, best first. Ids are stored instead of names because
/// two devices can share a name, and a name changes when the user renames the device.
public enum MicrophonePriority {

    /// The first id in the list that is plugged in right now.
    ///
    /// Returns nil when the list is empty or none of its devices are connected. The
    /// caller then uses whatever the system's default input is, which is what the app
    /// did before this setting existed.
    public static func firstAvailable(order: [String], available: [String]) -> String? {
        let connected = Set(available)
        return order.first { connected.contains($0) }
    }

    /// The list to show in Preferences: the user's order first, then any device that is
    /// plugged in but not on the list yet, so a new microphone is never invisible.
    public static func listing(order: [String], available: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in order where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        for id in available where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    public static func decode(json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    public static func encode(_ order: [String]) -> String {
        guard let data = try? JSONEncoder().encode(order) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

import CoreGraphics
import Foundation
import DictatoCore

/// Layout numbers that get adjusted by eye rather than derived from anything.
///
/// They live in a plain text file next to the app's data rather than being baked in,
/// because finding the spacing that looks right is guesswork and a rebuild per attempt
/// makes it slow enough that it doesn't get done properly. Edit the file, then close and
/// reopen Preferences to see the change.
///
/// These are tuning aids, not user settings: nothing in the UI exposes them, and the
/// fallbacks in `shipped` are what a fresh install uses. Once a value looks right it
/// belongs back in `shipped` so everyone gets it.
enum UITuning {
    static var fileURL: URL {
        ModelPaths.appSupportBase().appendingPathComponent("ui-tuning.conf")
    }

    /// What ships. The file only ever overrides these.
    static let shipped: [(key: String, value: CGFloat, note: String)] = [
        ("sidebarWidth", 220, "sidebar panel width"),
        ("sidebarInset", 10, "gap between the sidebar panel and the window edges"),
        ("sidebarCorner", 14, "sidebar corner radius"),
        ("brandTop", 40, "space above the Dictato title; also clears the traffic lights"),
        ("brandBottom", 10, "space below the Dictato title"),
        ("brandLeading", 16, "left inset of the title row"),
        ("contentPadding", 20, "padding around the Models and Profiles content"),
        ("cardSpacing", 12, "gap between cards"),
        ("cardPadding", 14, "padding inside each card"),
        ("cardCorner", 12, "card corner radius"),
        ("trafficLightX", 22, "traffic lights: distance from the left edge"),
        ("trafficLightTop", 22, "traffic lights: distance from the top edge"),
        ("trafficLightPitch", 20, "traffic lights: spacing between the three buttons"),
    ]

    private static var overrides: [String: CGFloat] = [:]

    // Sidebar
    static var sidebarWidth: CGFloat { value("sidebarWidth") }
    static var sidebarInset: CGFloat { value("sidebarInset") }
    static var sidebarCorner: CGFloat { value("sidebarCorner") }

    // Brand row at the top of the sidebar
    static var brandTop: CGFloat { value("brandTop") }
    static var brandBottom: CGFloat { value("brandBottom") }
    static var brandLeading: CGFloat { value("brandLeading") }

    // Detail panes (Models, Profiles)
    static var contentPadding: CGFloat { value("contentPadding") }
    static var cardSpacing: CGFloat { value("cardSpacing") }
    static var cardPadding: CGFloat { value("cardPadding") }
    static var cardCorner: CGFloat { value("cardCorner") }

    // Window buttons
    static var trafficLightX: CGFloat { value("trafficLightX") }
    static var trafficLightTop: CGFloat { value("trafficLightTop") }
    static var trafficLightPitch: CGFloat { value("trafficLightPitch") }

    private static func value(_ key: String) -> CGFloat {
        if let override = overrides[key] { return override }
        return shipped.first { $0.key == key }?.value ?? 0
    }

    /// Re-reads the file. Called when Preferences opens, so editing the file and
    /// reopening the window is the whole loop — no rebuild, no restart.
    static func reload() {
        writeTemplateIfMissing()
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        var parsed: [String: CGFloat] = [:]
        for line in text.split(separator: "\n") {
            let stripped = line.prefix { $0 != "#" }
            let parts = stripped.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            // Ignore non-positive values rather than letting a typo collapse the layout
            // into something that can't be clicked back out of.
            guard let number = Double(raw), number > 0 else { continue }
            parsed[key] = CGFloat(number)
        }
        overrides = parsed
    }

    /// Writes the file with every key at its shipped value, so there is something to
    /// edit and the available knobs are discoverable without reading the source.
    static func writeTemplateIfMissing() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var lines = [
            "# Dictato layout tuning.",
            "# Edit a number, then close Preferences (Cmd-W) and reopen it (Cmd-,).",
            "# Delete this file to go back to the shipped values.",
            "",
        ]
        for entry in shipped {
            lines.append("# \(entry.note)")
            lines.append("\(entry.key) = \(Int(entry.value))")
            lines.append("")
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

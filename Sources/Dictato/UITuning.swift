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
        ("sidebarWidth", 228, "sidebar panel width"),
        ("sidebarInset", 6, "gap between the sidebar panel and the window edges"),
        ("sidebarCorner", 24, "sidebar corner radius; the window is rounded to match"),
        ("brandTop", 42, "space above the Dictato title; also clears the traffic lights"),
        ("brandBottom", 6, "space below the Dictato title"),
        ("brandLeading", 16, "left inset of the title row"),
        ("contentPadding", 18, "padding around the Models and Profiles content"),
        ("cardSpacing", 12, "gap between cards"),
        ("cardPadding", 14, "padding inside each card"),
        ("cardCorner", 12, "card corner radius"),
        ("groupSpacing", 22, "gap between one group of settings and the next"),
        ("groupHeadingGap", 7, "gap between a group heading and the card under it"),
        ("pageTitleGap", 4, "gap between the page title and its description"),
        ("pageHeaderBottom", 22, "gap below the description, before the first group"),
        ("rowVerticalPadding", 10, "padding above and below a settings row"),
        ("rowIconWidth", 22, "width of the icon column at the left of a row"),
        ("rowMinHeight", 34, "minimum row height, so single-line rows come out even"),
        ("trafficLightX", 22, "traffic lights: distance from the left edge"),
        ("trafficLightTop", 21, "traffic lights: distance from the top edge"),
        ("trafficLightPitch", 24, "traffic lights: spacing between the three buttons"),

        // Recording panel: the floating card near the bottom of the screen.
        ("panelWidth", 296, "recording panel width"),
        ("panelHeight", 56, "recording panel height while it only shows the wave"),
        ("panelTextHeight", 78, "recording panel height once live text is showing"),
        ("panelCorner", 22, "recording panel corner radius"),
        ("panelBorderOpacity", 6, "recording panel border strength, in percent"),
        ("panelGlowWidth", 4, "thickness of the glow that travels around the panel"),
        ("panelGlowOpacity", 80, "brightness of the travelling glow, in percent"),
        ("panelGlowSeconds", 7, "seconds for the glow to go once around the panel"),

        // Notch bar: the strip that merges with the camera notch.
        ("notchWaveWidth", 60, "width of the wave, to the right of the notch"),
        ("notchIconSize", 16, "size of each icon, to the left of the notch"),
        ("notchIconGap", 6, "gap between the two icons"),
        ("notchIconInset", 10, "space around the icons, at both ends of their strip"),
        ("notchTextHeight", 24, "extra height the notch bar takes when it shows live text"),
    ]

    /// Observable so a change redraws the Preferences tree immediately: dragging a
    /// slider and watching the layout move is the whole point of tuning by eye.
    final class Store: ObservableObject {
        static let shared = Store()
        @Published fileprivate(set) var overrides: [String: CGFloat] = [:]
    }

    private static var overrides: [String: CGFloat] { Store.shared.overrides }

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

    // Preferences pages, groups and rows. Read through PrefTheme at the call sites.

    // Window buttons
    static var trafficLightX: CGFloat { value("trafficLightX") }
    static var trafficLightTop: CGFloat { value("trafficLightTop") }
    static var trafficLightPitch: CGFloat { value("trafficLightPitch") }

    // Recording panel
    static var panelWidth: CGFloat { value("panelWidth") }
    static var panelHeight: CGFloat { value("panelHeight") }
    static var panelTextHeight: CGFloat { value("panelTextHeight") }
    static var panelCorner: CGFloat { value("panelCorner") }
    /// Stored as a percentage because the tuning file only accepts whole numbers.
    static var panelBorderOpacity: Double { Double(value("panelBorderOpacity")) / 100 }
    static var panelGlowWidth: CGFloat { value("panelGlowWidth") }
    static var panelGlowOpacity: Double { Double(value("panelGlowOpacity")) / 100 }
    static var panelGlowSeconds: Double { Double(value("panelGlowSeconds")) }

    // Notch bar
    static var notchWaveWidth: CGFloat { value("notchWaveWidth") }
    static var notchIconSize: CGFloat { value("notchIconSize") }
    static var notchIconGap: CGFloat { value("notchIconGap") }
    static var notchIconInset: CGFloat { value("notchIconInset") }
    static var notchTextHeight: CGFloat { value("notchTextHeight") }

    static func value(_ key: String) -> CGFloat {
        if let override = overrides[key] { return override }
        return shipped.first { $0.key == key }?.value ?? 0
    }

    /// Applies a value live and persists it. The file stays the source of truth so a
    /// session's tweaks survive a restart and can still be edited by hand.
    static func set(_ key: String, to newValue: CGFloat) {
        Store.shared.overrides[key] = newValue
        save()
    }

    static func resetAll() {
        Store.shared.overrides = [:]
        try? FileManager.default.removeItem(at: fileURL)
        writeTemplateIfMissing()
    }

    /// The current values in the file's own format, for pasting back into `shipped`.
    static func exportText() -> String {
        shipped.map { "\($0.key) = \(Int(value($0.key)))" }.joined(separator: "\n")
    }

    private static func save() {
        var lines = [
            "# Dictato layout tuning.",
            "# Edit here or drag the sliders in Preferences > Debug.",
            "# Delete this file to go back to the shipped values.",
            "",
        ]
        for entry in shipped {
            lines.append("# \(entry.note)")
            lines.append("\(entry.key) = \(Int(value(entry.key)))")
            lines.append("")
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
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
        Store.shared.overrides = parsed
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

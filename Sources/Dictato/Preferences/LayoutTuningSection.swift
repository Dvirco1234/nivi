import SwiftUI
import AppKit

/// Live sliders for the layout numbers, so spacing can be judged by dragging rather than
/// by editing a file and reopening the window. Changes apply as you drag and are written
/// back to ui-tuning.conf, which stays hand-editable.
struct LayoutTuningSection: View {
    @ObservedObject private var store = UITuning.Store.shared
    @State private var copied = false

    /// The sliders in the order they appear, split into groups. Anything not named here
    /// falls into "Everything else", so adding a key to `UITuning.shipped` can never make
    /// its slider disappear.
    private static let groups: [(heading: String, keys: [String])] = [
        ("Sidebar", ["sidebarWidth", "sidebarInset", "sidebarCorner",
                     "brandTop", "brandBottom", "brandLeading"]),
        ("Sidebar tabs", ["sidebarRowHeight", "sidebarRowGap", "sidebarRowInset",
                          "sidebarRowCorner"]),
        ("Cards", ["contentPadding", "cardSpacing", "cardPadding", "cardCorner"]),
        ("Pages and rows", ["groupSpacing", "groupHeadingGap", "pageTitleGap",
                            "pageHeaderBottom", "rowVerticalPadding",
                            "rowIconWidth", "rowMinHeight"]),
        ("History and files", ["historyActionHeight", "historyCollapsedLines",
                               "historyExpandedMaxHeight", "historyExpandChars",
                               "dropZoneHeight", "fileResultHeight"]),
        ("Traffic lights", ["trafficLightX", "trafficLightTop", "trafficLightPitch"]),
        ("Recording display pictures", ["recordingThumbnailWidth", "recordingThumbnailHeight",
                                        "recordingThumbnailCorner", "recordingThumbnailGap"]),
        ("Recording panel", ["panelWidth", "panelHeight", "panelTextHeight", "panelCorner",
                             "panelBorderOpacity", "panelGlowWidth", "panelGlowOpacity",
                             "panelGlowSeconds"]),
        ("Notch bar", ["notchWaveWidth", "notchIconSize", "notchIconInset", "notchTextHeight"]),
    ]

    var body: some View {
        PrefPage(title: "Layout",
                 description: "Developer sliders for the window's spacing. Changes save to ui-tuning.conf.") {
            ForEach(Self.groups, id: \.heading) { group in
                PrefGroup(group.heading) {
                    ForEach(entries(for: group.keys), id: \.key) { entry in
                        TuningSliderRow(entry: entry, range: range(for: entry.key))
                    }
                }
            }
            let leftovers = ungrouped
            if !leftovers.isEmpty {
                PrefGroup("Everything else") {
                    ForEach(leftovers, id: \.key) { entry in
                        TuningSliderRow(entry: entry, range: range(for: entry.key))
                    }
                }
            }
            PrefGroup("Values",
                      footer: "Copy pastes the current numbers in the file's own format. Reset deletes your changes and goes back to what ships.") {
                PrefButtonRow(icon: "doc.on.doc",
                              "Copy the current values",
                              caption: copied ? "Copied." : nil,
                              buttonTitle: "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(UITuning.exportText(), forType: .string)
                    copied = true
                }
                PrefButtonRow(icon: "arrow.uturn.backward",
                              "Go back to the shipped values",
                              buttonTitle: "Reset") {
                    UITuning.resetAll()
                    PreferencesWindow.refreshTrafficLights()
                    copied = false
                }
            }
        }
        .navigationTitle("Layout")
    }

    private typealias Entry = (key: String, value: CGFloat, note: String)

    private func entries(for keys: [String]) -> [Entry] {
        keys.compactMap { key in UITuning.shipped.first { $0.key == key } }
    }

    private var ungrouped: [Entry] {
        let named = Set(Self.groups.flatMap(\.keys))
        return UITuning.shipped.filter { !named.contains($0.key) }
    }

    /// Wide enough to find the right value, bounded so a drag can't push the window into
    /// a state that is hard to click back out of.
    private func range(for key: String) -> ClosedRange<Double> {
        switch key {
        case "sidebarWidth": return 160...320
        case "historyCollapsedLines": return 1...10
        case "historyExpandedMaxHeight": return 80...600
        case "historyExpandChars": return 60...600
        case "dropZoneHeight": return 100...320
        case "fileResultHeight": return 100...500
        case "trafficLightPitch": return 14...32
        case "panelWidth": return 220...420
        case "panelHeight": return 40...90
        case "panelTextHeight": return 60...130
        case "panelCorner": return 4...40
        case "panelBorderOpacity", "panelGlowOpacity": return 1...100
        case "panelGlowSeconds": return 2...20
        case "notchWaveWidth": return 20...140
        case "notchIconSize": return 8...28
        default: return 0...60
        }
    }
}

/// One slider row inside a card: the key, its current number, the slider, and the note
/// explaining what the number does.
private struct TuningSliderRow: View {
    let entry: (key: String, value: CGFloat, note: String)
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.key).font(.callout)
                Spacer()
                // The same box as the stepper rows use. Dragging finds the number that
                // looks right; typing is how you put an exact one back afterwards.
                PrefNumberField(value: Binding(get: { Int(UITuning.value(entry.key)) },
                                               set: { apply(CGFloat($0)) }),
                                range: Int(range.lowerBound)...Int(range.upperBound))
            }
            Slider(value: Binding(get: { Double(UITuning.value(entry.key)) },
                                  set: { apply(CGFloat($0.rounded())) }),
                   in: range)
                .controlSize(.small)
            Text(entry.note).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, UITuning.cardPadding)
        .padding(.vertical, PrefTheme.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func apply(_ newValue: CGFloat) {
        UITuning.set(entry.key, to: newValue)
        // The window buttons are AppKit views, so they need to be told. SwiftUI redraws
        // itself.
        PreferencesWindow.refreshTrafficLights()
    }
}

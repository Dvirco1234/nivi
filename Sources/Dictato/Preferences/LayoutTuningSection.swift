import SwiftUI
import AppKit

/// Live sliders for the layout numbers, so spacing can be judged by dragging rather than
/// by editing a file and reopening the window. Changes apply as you drag and are written
/// back to ui-tuning.conf, which stays hand-editable.
struct LayoutTuningSection: View {
    @ObservedObject private var store = UITuning.Store.shared
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                ForEach(UITuning.shipped, id: \.key) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.key).font(.callout)
                            Spacer()
                            Text("\(Int(UITuning.value(entry.key)))")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(UITuning.value(entry.key)) },
                                set: { newValue in
                                    UITuning.set(entry.key, to: CGFloat(newValue.rounded()))
                                    // The window buttons are AppKit views, so they need
                                    // to be told; SwiftUI redraws itself.
                                    PreferencesWindow.refreshTrafficLights()
                                }),
                            in: range(for: entry.key))
                        Text(entry.note).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Layout")
            } footer: {
                Text("Drag to adjust the window's spacing. Saved to ui-tuning.conf, which you can also edit by hand.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Copy values") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(UITuning.exportText(), forType: .string)
                        copied = true
                    }
                    if copied {
                        Text("Copied").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset to shipped values") {
                        UITuning.resetAll()
                        PreferencesWindow.refreshTrafficLights()
                        copied = false
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Layout")
    }

    /// Wide enough to find the right value, bounded so a drag can't push the window into
    /// a state that is hard to click back out of.
    private func range(for key: String) -> ClosedRange<Double> {
        switch key {
        case "sidebarWidth": return 160...320
        case "trafficLightPitch": return 14...32
        default: return 0...60
        }
    }
}

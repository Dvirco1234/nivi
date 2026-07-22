import SwiftUI
import AppKit
import DictatoCore

/// Lets the user either pick a modifier-tap preset or record a standard key-combo.
struct HotkeyRecorderView: View {
    let title: String
    @State var binding: HotkeyBinding
    let onChange: (HotkeyBinding) -> Void

    private let presets: [HotkeyBinding] = [
        .modifierTap(.rightCommand, count: 2),
        .modifierTap(.leftCommand, count: 2),
        .modifierTap(.rightOption, count: 2),
        .modifierTap(.rightControl, count: 2),
    ]

    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Menu(binding.displayString) {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                    Button(preset.displayString) { set(preset) }
                }
                Divider()
                Button("Record key combo…") { KeyComboCatcher.begin { set($0) } }
            }
            .frame(width: 200)
        }
    }

    private func set(_ b: HotkeyBinding) {
        binding = b
        onChange(b)
    }
}

/// One-shot local key-combo capture via a transient monitor.
enum KeyComboCatcher {
    private static var monitor: Any?
    static func begin(_ completion: @escaping (HotkeyBinding) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            completion(.keyCombo(keyCode: event.keyCode, modifiers: mods))
            stop()
            return nil
        }
    }
    private static func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

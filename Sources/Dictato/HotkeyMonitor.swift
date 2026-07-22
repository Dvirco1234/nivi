import AppKit
import DictatoCore

/// Wires NSEvent global+local monitors into a ModifierTapDetector according to the
/// active dictate binding, and fires onCancel when the cancel binding matches.
/// Global monitors only deliver events when Accessibility is granted.
final class HotkeyMonitor {
    private let detector: ModifierTapDetector
    private let dictateModifierKeyCode: UInt16
    private let cancelBinding: HotkeyBinding
    private var monitors: [Any] = []

    var onCancel: (() -> Void)?
    var cancelEnabled = false

    init(detector: ModifierTapDetector, dictateBinding: HotkeyBinding, cancelBinding: HotkeyBinding) {
        self.detector = detector
        self.cancelBinding = cancelBinding
        switch dictateBinding {
        case .modifierTap(let key, _): self.dictateModifierKeyCode = key.keyCode
        case .keyCombo(let keyCode, _): self.dictateModifierKeyCode = keyCode
        }
    }

    func start() {
        guard monitors.isEmpty else { return }
        let flags: (NSEvent) -> Void = { [weak self] e in self?.handleFlags(e) }
        let keys: (NSEvent) -> Void = { [weak self] e in self?.handleKeyDown(e) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keys) { monitors.append(m) }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { keys($0); return $0 } as Any)
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func handleFlags(_ event: NSEvent) {
        if event.keyCode == dictateModifierKeyCode {
            let down = event.modifierFlags.rawValue & requiredMask != 0
            detector.modifierChanged(down: down)
        } else {
            detector.otherKeyDown()
        }
    }

    private var requiredMask: UInt {
        // command 0x100000, option 0x80000, control 0x40000 — pick by keyCode family
        switch dictateModifierKeyCode {
        case 54, 55: return 0x100000
        case 61: return 0x80000
        case 62: return 0x40000
        default: return 0x100000
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if cancelEnabled, case .keyCombo(let kc, _) = cancelBinding, event.keyCode == kc {
            onCancel?()
            return
        }
        detector.otherKeyDown()
    }
}

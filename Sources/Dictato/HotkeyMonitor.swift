import AppKit
import DictatoCore

/// Wires NSEvent global+local monitors into the RightCmdTapDetector.
/// Global monitors only deliver events when Accessibility is granted.
final class HotkeyMonitor {
    private static let rightCommandKeyCode: UInt16 = 54
    private static let escapeKeyCode: UInt16 = 53

    private let detector: RightCmdTapDetector
    private var monitors: [Any] = []

    var onEsc: (() -> Void)?
    var escEnabled = false

    init(detector: RightCmdTapDetector) {
        self.detector = detector
    }

    func start() {
        guard monitors.isEmpty else { return }
        let flagsHandler: (NSEvent) -> Void = { [weak self] event in self?.handleFlags(event) }
        let keyHandler: (NSEvent) -> Void = { [weak self] event in self?.handleKeyDown(event) }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyHandler) {
            monitors.append(monitor)
        }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            flagsHandler(event)
            return event
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            keyHandler(event)
            return event
        } as Any)
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func handleFlags(_ event: NSEvent) {
        if event.keyCode == Self.rightCommandKeyCode {
            detector.rightCmdChanged(down: event.modifierFlags.contains(.command))
        } else {
            // Another modifier changed (shift, option, …) — counts as combo usage.
            detector.otherKeyDown()
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if escEnabled, event.keyCode == Self.escapeKeyCode {
            onEsc?()
            return
        }
        detector.otherKeyDown()
    }
}

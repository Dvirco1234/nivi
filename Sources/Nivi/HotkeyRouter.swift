import AppKit
import NiviCore

/// Owns the global + local flagsChanged/keyDown monitors and dispatches events to one
/// ModifierTapDetector per modifier-tap profile (keyed by modifier keyCode). Key-combo
/// profiles match directly on keyDown. Only the active profile responds while recording.
final class HotkeyRouter {
    var onActivate: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var cancelEnabled = false

    private let doubleTapWindow: TimeInterval

    // keyCode -> (detector, profileID) for modifier-tap profiles
    private var tapDetectors: [UInt16: (detector: ModifierTapDetector, profileID: String)] = [:]
    // profileID -> keyCombo for direct-match profiles
    private var comboProfiles: [(keyCode: UInt16, mods: UInt, profileID: String)] = []
    private var cancelBinding: HotkeyBinding = .defaultCancel
    private var originalModes: [String: ModifierTapDetector.Mode] = [:]

    private var monitors: [Any] = []
    private var recordingProfileID: String?

    init(doubleTapWindowMs: Int) {
        self.doubleTapWindow = Double(doubleTapWindowMs) / 1000.0
    }

    func rebuild(profiles: ProfileSet, cancel: HotkeyBinding) {
        let wasRunning = !monitors.isEmpty
        stop()
        tapDetectors = [:]
        comboProfiles = []
        originalModes = [:]
        cancelBinding = cancel
        for p in profiles.profiles {
            switch p.hotkey {
            case .modifierTap(let key, let count):
                let detector = ModifierTapDetector(
                    doubleTapWindow: doubleTapWindow,
                    now: { ProcessInfo.processInfo.systemUptime })
                detector.mode = count >= 2 ? .doubleTap : .singleTap
                let id = p.id
                detector.onActivate = { [weak self] in self?.fire(id) }
                tapDetectors[key.keyCode] = (detector, id)
                originalModes[id] = detector.mode
            case .keyCombo(let keyCode, let mods):
                comboProfiles.append((keyCode, mods, p.id))
            }
        }
        if wasRunning { start() }
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

    func beginRecording(profileID: String) {
        recordingProfileID = profileID
        // The recording profile's tap detector switches to single-tap so one tap stops.
        for (_, entry) in tapDetectors where entry.profileID == profileID {
            entry.detector.mode = .singleTap
        }
    }

    func endRecording() {
        recordingProfileID = nil
        for (_, entry) in tapDetectors {
            entry.detector.mode = originalModes[entry.profileID] ?? .doubleTap
        }
    }

    private func fire(_ profileID: String) {
        if let active = recordingProfileID, active != profileID { return }  // ignore other profiles mid-record
        onActivate?(profileID)
    }

    private func handleFlags(_ event: NSEvent) {
        if let entry = tapDetectors[event.keyCode] {
            let mask = Self.requiredMask(for: event.keyCode)
            let down = event.modifierFlags.rawValue & mask != 0
            entry.detector.modifierChanged(down: down)
        } else {
            tapDetectors.values.forEach { $0.detector.otherKeyDown() }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Esc arrives here from a global monitor, which macOS gates behind Input Monitoring.
        // Logging it is the fastest way to tell "permission missing" from "wiring broken",
        // but it fires on every Esc system-wide, so keep it behind verbose logging.
        if event.keyCode == 53, Settings().verboseLogging {
            Log.info("Esc keyDown observed (cancelEnabled=\(cancelEnabled))")
        }
        if cancelEnabled, case .keyCombo(let kc, _) = cancelBinding, event.keyCode == kc {
            onCancel?()
            return
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        for combo in comboProfiles where combo.keyCode == event.keyCode && combo.mods == mods {
            fire(combo.profileID)
            return
        }
        tapDetectors.values.forEach { $0.detector.otherKeyDown() }
    }

    private static func requiredMask(for keyCode: UInt16) -> UInt {
        switch keyCode {
        case 54, 55: return 0x100000   // command
        case 61: return 0x80000        // option
        case 62: return 0x40000        // control
        default: return 0x100000
        }
    }
}

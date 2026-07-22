import AppKit

final class TextInserter {
    /// Puts text on the clipboard; if autoPaste and Accessibility allow, posts ⌘V
    /// into the frontmost app and restores the previous clipboard afterwards.
    /// Returns true when the paste keystroke was posted.
    // De-facto standard marker (nspasteboard.com): well-behaved clipboard managers
    // (Raycast, Maccy, Paste, …) skip items carrying this type.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    @discardableResult
    func insert(_ text: String, autoPaste: Bool, excludeFromHistory: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if excludeFromHistory {
            pasteboard.setData(Data(), forType: Self.transientType)
        }

        guard autoPaste, PermissionManager.accessibilityGranted else {
            Log.info("Clipboard-only insertion (\(text.count) chars)")
            return false
        }
        postCmdV()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
        Log.info("Pasted \(text.count) chars")
        return true
    }

    private func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyVDown?.flags = .maskCommand
        keyVUp?.flags = .maskCommand
        keyVDown?.post(tap: .cghidEventTap)
        keyVUp?.post(tap: .cghidEventTap)
    }
}

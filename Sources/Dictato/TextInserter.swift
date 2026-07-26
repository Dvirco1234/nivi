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

    /// Types text into the frontmost app as Unicode key events.
    ///
    /// Used by In-app-live, where the clipboard path is wrong: it would clobber the
    /// user's clipboard on every stabilized word. Unicode events are also layout
    /// independent, so Hebrew arrives correctly regardless of the active keyboard
    /// layout. Requires Accessibility, which the app already needs for auto-paste.
    func typeUnicode(_ string: String) {
        guard !string.isEmpty, PermissionManager.accessibilityGranted else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        // CGEventKeyboardSetUnicodeString takes UTF-16; chunk it so long strings
        // don't exceed what a single event will carry.
        for chunk in Array(string.utf16).chunked(into: 16) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            var buffer = chunk
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

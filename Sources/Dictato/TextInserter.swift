import AppKit
import ApplicationServices

/// What actually happened to a transcription, so the caller can tell the user.
enum InsertionOutcome {
    case pasted
    /// Left on the clipboard: either the user asked for copy-only, or nothing that
    /// accepts text was focused. Either way the clipboard is the only way to reach it,
    /// so it is always kept in clipboard history.
    case copiedToClipboard
}

final class TextInserter {
    // De-facto standard marker (nspasteboard.com): well-behaved clipboard managers
    // (Raycast, Maccy, Paste, …) skip items carrying this type.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Puts text on the clipboard and, unless the user asked for copy-only, pastes it
    /// into the frontmost app.
    ///
    /// "Keep out of clipboard history" is honoured only when the text actually landed
    /// somewhere: if it was merely copied, hiding it from history would leave the user
    /// no way to reach what they just dictated.
    @discardableResult
    func insert(_ text: String, autoPaste: Bool, copyOnly: Bool, excludeFromHistory: Bool) -> InsertionOutcome {
        let willPaste = autoPaste && !copyOnly && PermissionManager.accessibilityGranted
        // Detection only decides whether to keep the text in history — never whether to
        // paste. Editable-focus detection is unreliable in Electron and web views, and a
        // false negative that silently stopped pasting would be far worse than one that
        // leaves an extra clipboard-history entry.
        let hasTextTarget = willPaste && focusedElementAcceptsText()
        let keepInHistory = !willPaste || !hasTextTarget || !excludeFromHistory

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if !keepInHistory {
            pasteboard.setData(Data(), forType: Self.transientType)
        }

        guard willPaste else {
            Log.info("Copied \(text.count) chars to the clipboard (copyOnly: \(copyOnly))")
            return .copiedToClipboard
        }

        postCmdV()

        // Restoring the previous clipboard is only right when this dictation was meant to
        // be invisible. When it is meant to be in history, restoring would push the older
        // item back to the top and bury the text the user just dictated.
        if !keepInHistory, let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
                // Mark the restore transient too, or putting the old text back registers
                // as a fresh copy and reorders the user's history.
                pasteboard.setData(Data(), forType: Self.transientType)
            }
        }
        if !hasTextTarget {
            Log.info("No text target focused — kept \(text.count) chars in clipboard history")
        }
        Log.info("Pasted \(text.count) chars")
        return .pasted
    }

    /// Whether the system-wide focused element looks like something text can be typed
    /// into. Used only to decide whether the dictation must stay reachable via clipboard
    /// history — see the note at the call site about false negatives.
    private func focusedElementAcceptsText() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement

        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else { return false }
        return role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
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
        // Chunk so long strings don't exceed what a single event carries. Chunking by
        // Character rather than by UTF-16 unit matters: a non-BMP character (emoji) is
        // a surrogate pair, and cutting between the halves would post a lone surrogate
        // and garble the output. Insertion is append-only, so a mangled chunk can never
        // be corrected afterwards.
        for chunk in Array(string).chunked(into: 16) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            var buffer = Array(String(chunk).utf16)
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            // Pace the stream. The final pass of a long dictation can emit thousands of
            // synthetic events at once, and Electron apps (Slack) drop or reorder a burst
            // that arrives faster than they drain it. Insertion is append-only, so a
            // dropped chunk can never be repaired.
            usleep(1000)
        }
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

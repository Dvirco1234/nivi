import AppKit
import SwiftUI

/// Read-only text the user can select and copy, safe at any length.
///
/// SwiftUI's `Text(...).textSelection(.enabled)` must not be used for a transcript. When it
/// is clicked, AppKit hands the whole string to its single-field editor, which lays it out
/// as one line. Past roughly 10,000 characters Core Text gives up and the app dies:
///
///     CFRelease() called with NULL
///     __NSCoreTypesetterCreateBaseLineFromAttributedString
///     ...
///     SelectionTextField.Cell._selectOrEdit
///
/// That happened three times in October 2026, on a 67,248-character file transcript. A real
/// `NSTextView` lays text out by paragraph and scrolls, so it has no such limit. Measured
/// in a harness: the field editor crashed at 33,000 characters, this view selected 30,000
/// characters out of 67,000 without trouble.
///
/// The view is as tall as its text, up to `maxHeight`, and scrolls after that.
struct LongSelectableText: NSViewRepresentable {
    let text: String
    let maxHeight: CGFloat

    /// Above this many characters the text is certainly taller than any `maxHeight` used
    /// here, so measuring it would only cost a full layout for the same answer.
    private static let skipMeasuringAbove = 3_000

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.preferredFont(forTextStyle: .callout)
        textView.textColor = .labelColor
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        guard textView.string != text else { return }
        textView.string = text
        textView.font = NSFont.preferredFont(forTextStyle: .callout)
        textView.textColor = .labelColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        guard text.count <= Self.skipMeasuringAbove,
              let textView = scrollView.documentView as? NSTextView,
              let layout = textView.textLayoutManager else {
            return CGSize(width: width, height: maxHeight)
        }
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: layout.documentRange)
        let height = ceil(layout.usageBoundsForTextContainer.height)
        return CGSize(width: width, height: min(max(height, 1), maxHeight))
    }
}

import SwiftUI
import AppKit

/// The colours and spacing every Preferences pane is built from.
///
/// Colours live here rather than in `UITuning` because `UITuning` is a file-backed table
/// of `CGFloat`s meant to be dragged on a slider. A colour is neither a number nor
/// something anyone tunes per install, so widening that file format would buy nothing.
/// The numbers below are read back out of `UITuning`, so call sites get both from one
/// place while the sliders keep working.
///
/// Every colour is derived from a semantic `NSColor`. Hardcoded white opacities look
/// wrong the moment the window is shown in light mode.
enum PrefTheme {

    // MARK: Surfaces

    /// The card sitting on the window background. Slightly lighter than the window, not a
    /// hard edge.
    static let cardFill = Color(nsColor: .controlBackgroundColor).opacity(0.55)
    static let cardStroke = Color(nsColor: .separatorColor)
    /// The hairline between two rows inside one card.
    static let rowDivider = Color(nsColor: .separatorColor).opacity(0.7)

    // MARK: Sidebar tabs

    /// The plate behind the selected tab. A material rather than a flat colour, so it
    /// picks up the light behind it and reads as glass instead of as a painted block.
    static let tabSelectionFill: Material = .ultraThinMaterial
    /// A little light on top of that material. The sidebar is itself a material, so the
    /// plate alone barely separates from it.
    static let tabSelectionTint = Color.primary.opacity(0.07)
    /// The soft edge around the plate, which is what makes it read as a raised piece of
    /// glass rather than a smudge.
    static let tabSelectionStroke = Color.primary.opacity(0.14)
    /// Faint plate under the pointer, so a tab answers before it is clicked.
    static let tabHoverTint = Color.primary.opacity(0.05)

    // MARK: Meaning

    static let accent = Color.accentColor
    static let warning = Color.orange
    static let danger = Color.red
    static let iconTint = Color.secondary
    /// The dot next to the microphone that is actually in use.
    static let online = Color.green

    // MARK: Numbers

    /// Gap between one group and the next.
    static var groupSpacing: CGFloat { UITuning.value("groupSpacing") }
    /// Gap between a group heading and the card under it.
    static var groupHeadingGap: CGFloat { UITuning.value("groupHeadingGap") }
    /// Gap between the page title and the sentence under it.
    static var pageTitleGap: CGFloat { UITuning.value("pageTitleGap") }
    /// Gap below the description, before the first group.
    static var pageHeaderBottom: CGFloat { UITuning.value("pageHeaderBottom") }
    /// Padding above and below a row's content.
    static var rowVerticalPadding: CGFloat { UITuning.value("rowVerticalPadding") }
    /// Width of the leading icon column, so every label in a card starts at the same x.
    static var rowIconWidth: CGFloat { UITuning.value("rowIconWidth") }
    /// Minimum row height, so single-line rows all come out the same size.
    static var rowMinHeight: CGFloat { UITuning.value("rowMinHeight") }

    /// Height kept free for the Copy and Delete buttons on a history entry, so showing
    /// them on hover never changes the size of the card.
    static var historyActionHeight: CGFloat { UITuning.value("historyActionHeight") }

    /// How many lines of a saved entry are shown before it is cut off.
    static var historyCollapsedLines: Int { max(1, Int(UITuning.value("historyCollapsedLines"))) }

    /// The tallest a saved entry can get once it is expanded. Past this the text scrolls
    /// inside the card, so a long file transcript cannot fill the whole tab.
    static var historyExpandedMaxHeight: CGFloat { UITuning.value("historyExpandedMaxHeight") }

    /// Entries longer than this many characters get a Show more button.
    static var historyExpandChars: Int { Int(UITuning.value("historyExpandChars")) }

    /// Height of the dashed drop zone on the Transcribe a file tab.
    static var dropZoneHeight: CGFloat { UITuning.value("dropZoneHeight") }

    /// Height of the box holding a finished file transcript.
    static var fileResultHeight: CGFloat { UITuning.value("fileResultHeight") }

    /// Gap between the icon column and the label.
    static let rowIconGap: CGFloat = 10
}

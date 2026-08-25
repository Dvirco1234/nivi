import SwiftUI
import AppKit

/// The building blocks every Preferences tab is made of.
///
/// A tab is a `PrefPage` holding `PrefGroup`s, and a group holds rows. Written by hand
/// instead of using SwiftUI's grouped `Form` for one reason above all others: the look we
/// want puts the group heading on the window background, outside and above the card. A
/// grouped `Form` glues its header to the top of its own inset box and gives no supported
/// way to move it out. It also owns the fill, the corner radius, the row insets and the
/// separators, so matching the design would mean fighting the style on every row.
///
/// Two tabs, Models and Profiles, already hand-rolled their cards before this file
/// existed. This generalises what they were doing rather than adding a second card style
/// beside them.

// MARK: - Page

/// One whole tab: a big title, one grey sentence, then the scrolling content.
///
/// Draws no background of its own. The window's background belongs to `SettingsView`,
/// which paints an opaque base under a blur; painting again here would either double up
/// or, if it were ever removed from there, hide the bug instead of fixing it.
struct PrefPage<Content: View>: View {
    private let title: String
    private let description: String
    private let content: Content

    init(title: String, description: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        ScrollView {
            // The header scrolls away with the content, the way the apps we are matching
            // do it.
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: PrefTheme.pageTitleGap) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0).frame(height: PrefTheme.pageHeaderBottom)
                VStack(alignment: .leading, spacing: PrefTheme.groupSpacing) {
                    content
                }
            }
            .padding(UITuning.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Group

/// A named group: a small heading on the window background, then one card of rows.
struct PrefGroup<Content: View>: View {
    private let heading: String?
    private let footer: String?
    private let content: Content

    init(_ heading: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.heading = heading
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PrefTheme.groupHeadingGap) {
            if let heading {
                Text(heading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            card
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var card: some View {
        _VariadicView.Tree(PrefDividedRows()) { content }
            .background(PrefTheme.cardFill,
                        in: RoundedRectangle(cornerRadius: UITuning.cardCorner))
            .overlay(
                RoundedRectangle(cornerRadius: UITuning.cardCorner)
                    .strokeBorder(PrefTheme.cardStroke, lineWidth: 1))
    }
}

/// Stacks the rows and drops a hairline between them, but not after the last one.
///
/// `_VariadicView` is an underscored SwiftUI API. It is the only way to see a
/// `ViewBuilder`'s children as a list, and it has been stable for years, but Apple owes us
/// nothing. If it ever goes away the fallback is mechanical: stack the rows in a plain
/// `VStack` and have callers write `PrefDivider()` between them, which is why that view
/// stays available.
private struct PrefDividedRows: _VariadicView_MultiViewRoot {
    @ViewBuilder func body(children: _VariadicView.Children) -> some View {
        let lastID = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != lastID { PrefDivider() }
            }
        }
    }
}

/// The hairline between two rows. Inset on the left so it starts under the label rather
/// than cutting the card in half.
struct PrefDivider: View {
    var body: some View {
        Rectangle()
            .fill(PrefTheme.rowDivider)
            .frame(height: 1)
            .padding(.leading, UITuning.cardPadding)
    }
}

// MARK: - Row

enum PrefCaptionStyle {
    case normal
    case warning

    var color: Color {
        switch self {
        case .normal: return .secondary
        case .warning: return PrefTheme.warning
        }
    }
}

/// One row: leading icon, title, optional grey caption, control pushed to the far right.
///
/// The icon is optional so a row can give its whole width to a wide control, such as the
/// recording display thumbnails.
struct PrefRow<Trailing: View>: View {
    private let icon: String?
    private let title: String
    private let caption: String?
    private let captionStyle: PrefCaptionStyle
    private let trailing: Trailing

    init(icon: String?,
         _ title: String,
         caption: String? = nil,
         captionStyle: PrefCaptionStyle = .normal,
         @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.title = title
        self.caption = caption
        self.captionStyle = captionStyle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PrefTheme.rowIconGap) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(PrefTheme.iconTint)
                    .frame(width: PrefTheme.rowIconWidth, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(captionStyle.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, UITuning.cardPadding)
        .padding(.vertical, PrefTheme.rowVerticalPadding)
        .frame(minHeight: PrefTheme.rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PrefRow where Trailing == EmptyView {
    init(icon: String?, _ title: String, caption: String? = nil,
         captionStyle: PrefCaptionStyle = .normal) {
        self.init(icon: icon, title, caption: caption, captionStyle: captionStyle) {
            EmptyView()
        }
    }
}

// MARK: - Typed rows

struct PrefToggleRow: View {
    let icon: String?
    let title: String
    var caption: String? = nil
    var captionStyle: PrefCaptionStyle = .normal
    @Binding var isOn: Bool

    init(icon: String?, _ title: String, caption: String? = nil,
         captionStyle: PrefCaptionStyle = .normal, isOn: Binding<Bool>) {
        self.icon = icon
        self.title = title
        self.caption = caption
        self.captionStyle = captionStyle
        self._isOn = isOn
    }

    var body: some View {
        PrefRow(icon: icon, title, caption: caption, captionStyle: captionStyle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PrefPickerRow<Value: Hashable>: View {
    let icon: String?
    let title: String
    var caption: String? = nil
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    init(icon: String?, _ title: String, caption: String? = nil,
         selection: Binding<Value>, options: [Value],
         label: @escaping (Value) -> String) {
        self.icon = icon
        self.title = title
        self.caption = caption
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        PrefRow(icon: icon, title, caption: caption) {
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

struct PrefStepperRow: View {
    let icon: String?
    let title: String
    var caption: String? = nil
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let format: (Int) -> String

    init(icon: String?, _ title: String, caption: String? = nil,
         value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         format: @escaping (Int) -> String) {
        self.icon = icon
        self.title = title
        self.caption = caption
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        PrefRow(icon: icon, title, caption: caption) {
            HStack(spacing: 8) {
                Text(format(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

/// "Label on the left, value on the right", with nothing to click.
struct PrefValueRow: View {
    let icon: String?
    let title: String
    var caption: String? = nil
    let value: String

    init(icon: String?, _ title: String, caption: String? = nil, value: String) {
        self.icon = icon
        self.title = title
        self.caption = caption
        self.value = value
    }

    var body: some View {
        PrefRow(icon: icon, title, caption: caption) {
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// A row that opens something else. Shows a chevron, and the whole row is clickable.
struct PrefDisclosureRow: View {
    let icon: String?
    let title: String
    var caption: String? = nil
    var value: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    init(icon: String?, _ title: String, caption: String? = nil,
         value: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.caption = caption
        self.value = value
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PrefRow(icon: icon, title, caption: caption) {
                HStack(spacing: 6) {
                    if let value {
                        Text(value).font(.callout).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .background(isHovering ? Color.primary.opacity(0.05) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// A row whose control is a button, including the ones that delete things.
struct PrefButtonRow: View {
    let icon: String?
    let title: String
    var caption: String? = nil
    let buttonTitle: String
    var role: ButtonRole? = nil
    let action: () -> Void

    init(icon: String?, _ title: String, caption: String? = nil,
         buttonTitle: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.caption = caption
        self.buttonTitle = buttonTitle
        self.role = role
        self.action = action
    }

    var body: some View {
        PrefRow(icon: icon, title, caption: caption) {
            Button(buttonTitle, role: role, action: action)
                .foregroundStyle(role == .destructive ? PrefTheme.danger : Color.primary)
        }
    }
}

// MARK: - Banner

/// The coloured strip that sits above the first group when something needs saying.
struct PrefBanner: View {
    enum Style {
        case info, warning, danger

        var tint: Color {
            switch self {
            case .info: return PrefTheme.accent
            case .warning: return PrefTheme.warning
            case .danger: return PrefTheme.danger
            }
        }
    }

    let style: Style
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    init(_ style: Style, icon: String, title: String, message: String,
         actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.style = style
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: PrefTheme.rowIconGap) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(style.tint)
                .frame(width: PrefTheme.rowIconWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(UITuning.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: UITuning.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: UITuning.cardCorner)
                .strokeBorder(style.tint.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Empty state

/// What a list shows when there is nothing in it yet.
struct PrefEmptyState: View {
    let icon: String
    let title: String
    let message: String

    init(icon: String, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, UITuning.cardPadding)
    }
}

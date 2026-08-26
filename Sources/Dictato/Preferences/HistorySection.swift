import SwiftUI
import AppKit
import DictatoCore

/// The History tab: everything the user has dictated or transcribed, saved on this Mac.
///
/// Searching, filtering and sorting all run over the list `HistoryStore` already holds in
/// memory, through the pure `HistoryFiltering` helper. Nothing here reads the file.
struct HistorySection: View {
    @ObservedObject var store: HistoryStore

    private let settings = Settings()
    @State private var searchText = ""
    @State private var sourceFilter: HistorySourceFilter = .all
    @State private var newestFirst = true
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var expandedIDs: Set<String> = []
    @State private var historyEnabled = Settings().historyEnabled
    @State private var retentionDays = Settings().historyRetentionDays
    @State private var excludeFromClipboardHistory = Settings().excludeFromClipboardHistory
    @State private var confirmDeleteAll = false

    private var visibleRecords: [HistoryRecord] {
        HistoryFiltering.apply(HistoryQuery(searchText: searchText,
                                            sources: sourceFilter.sources,
                                            newestFirst: newestFirst),
                               to: store.records)
    }

    var body: some View {
        PrefPage(title: "History",
                 description: "Everything you have dictated, kept on this Mac only.") {
            if !historyEnabled {
                PrefBanner(.info,
                           icon: "pause.circle",
                           title: "History is off",
                           message: "Nothing new is being saved. What you already have is still here.")
            }

            PrefGroup {
                toolbar
            }

            if visibleRecords.isEmpty {
                PrefGroup {
                    PrefEmptyState(icon: "clock.arrow.circlepath",
                                   title: store.records.isEmpty ? "Nothing here yet" : "No matches",
                                   message: store.records.isEmpty
                                     ? "Dictate something, or transcribe a file, and it will show up here."
                                     : "No saved text matches what you typed.")
                }
            } else {
                // Lazy so a long history does not build thousands of cards at once.
                LazyVStack(alignment: .leading, spacing: UITuning.cardSpacing) {
                    ForEach(visibleRecords) { record in
                        HistoryEntryCard(record: record,
                                         isExpanded: expandedIDs.contains(record.id),
                                         selecting: selecting,
                                         isSelected: selectedIDs.contains(record.id),
                                         onToggleExpanded: { toggle(&expandedIDs, record.id) },
                                         onToggleSelected: { toggle(&selectedIDs, record.id) },
                                         onCopy: { copy(record.text) },
                                         onDelete: { store.delete(id: record.id) })
                    }
                }
            }

            settingsGroup
        }
        .navigationTitle("History")
        .alert("Delete all saved text?", isPresented: $confirmDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { store.deleteAll() }
        } message: {
            Text("This removes all \(store.records.count) saved transcriptions from this Mac. It cannot be undone.")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(HistorySourceFilter.allCases, id: \.self) { filter in
                    FilterChip(title: filter.title,
                               isOn: sourceFilter == filter) { sourceFilter = filter }
                }
                Spacer(minLength: 8)
                if selecting {
                    Button("Delete selected") {
                        store.delete(ids: selectedIDs)
                        selectedIDs = []
                    }
                    .disabled(selectedIDs.isEmpty)
                    Button("Done") {
                        selecting = false
                        selectedIDs = []
                    }
                } else {
                    Menu(newestFirst ? "Newest first" : "Oldest first") {
                        Button("Newest first") { newestFirst = true }
                        Button("Oldest first") { newestFirst = false }
                    }
                    .fixedSize()
                    Button("Select") { selecting = true }
                        .disabled(store.records.isEmpty)
                }
            }
            .controlSize(.small)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PrefTheme.iconTint)
                TextField("Search your saved text", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(PrefTheme.cardFill, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(PrefTheme.cardStroke, lineWidth: 1))

            Text(countLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, UITuning.cardPadding)
        .padding(.vertical, PrefTheme.rowVerticalPadding)
    }

    private var countLine: String {
        let shown = visibleRecords.count
        let total = store.records.count
        if shown == total { return total == 1 ? "1 entry" : "\(total) entries" }
        return "\(shown) of \(total) entries"
    }

    // MARK: - Settings

    private var settingsGroup: some View {
        PrefGroup("History settings",
                  footer: "History is a plain text file on this Mac. It is never uploaded. Audio is never saved, only the text.") {
            PrefToggleRow(icon: "clock.arrow.circlepath",
                          "Keep history",
                          caption: keepHistoryCaption,
                          captionStyle: excludeFromClipboardHistory && historyEnabled ? .warning : .normal,
                          isOn: $historyEnabled)
                .onChange(of: historyEnabled) { settings.historyEnabled = $0 }
            PrefPickerRow(icon: "calendar",
                          "Delete entries older than",
                          selection: $retentionDays,
                          options: HistoryRetention.dayOptions) { HistoryRetention.optionLabel(days: $0) }
                .onChange(of: retentionDays) {
                    settings.historyRetentionDays = $0
                    store.pruneNow()
                }
            PrefValueRow(icon: "doc.text", "History file", value: store.fileURL.path)
            PrefButtonRow(icon: "trash",
                          "Delete all history",
                          buttonTitle: "Delete all",
                          role: .destructive) { confirmDeleteAll = true }
                .disabled(store.records.isEmpty)
        }
    }

    private var keepHistoryCaption: String {
        if excludeFromClipboardHistory && historyEnabled {
            // Both settings are honest on their own, and they pull in opposite
            // directions. Say so rather than quietly turning one of them off.
            return "You keep dictated text out of your clipboard manager. Dictato's own history still saves it here, on this Mac only."
        }
        return "Turning this off stops saving new entries. It does not delete the ones you already have."
    }

    // MARK: - Helpers

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The three chips across the top of the tab.
enum HistorySourceFilter: CaseIterable {
    case all, dictation, files

    var title: String {
        switch self {
        case .all: return "All"
        case .dictation: return "Dictation"
        case .files: return "Files"
        }
    }

    /// `nil` means show everything, including model tests.
    var sources: Set<HistorySource>? {
        switch self {
        case .all: return nil
        case .dictation: return [.dictation]
        case .files: return [.file]
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(isOn ? PrefTheme.accent : Color.primary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One saved transcription: the text, then small grey facts under it.
private struct HistoryEntryCard: View {
    let record: HistoryRecord
    let isExpanded: Bool
    let selecting: Bool
    let isSelected: Bool
    let onToggleExpanded: () -> Void
    let onToggleSelected: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var justCopied = false

    private var showActions: Bool { hovering && !selecting }

    private static let relativeTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if selecting {
                Button(action: onToggleSelected) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? PrefTheme.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(record.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .lineLimit(isExpanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    MetaChip(text: sourceLabel)
                    MetaChip(text: Self.relativeTime.localizedString(for: record.createdAt,
                                                                     relativeTo: Date()))
                    MetaChip(text: DurationFormatting.short(milliseconds: record.durationMs))
                    Spacer(minLength: 8)
                    // The buttons are always laid out and only fade in, and the row is
                    // tall enough for them whether they show or not. Adding them on
                    // hover made the card grow and pushed every card below it down, so
                    // the list moved under the pointer.
                    HStack(spacing: 6) {
                        Button(justCopied ? "Copied" : "Copy") {
                            onCopy()
                            justCopied = true
                        }
                        Button("Delete", role: .destructive, action: onDelete)
                            .foregroundStyle(PrefTheme.danger)
                    }
                    .opacity(showActions ? 1 : 0)
                    .allowsHitTesting(showActions)
                    .accessibilityHidden(!showActions)
                }
                .controlSize(.small)
                .frame(minHeight: PrefTheme.historyActionHeight)
            }
        }
        .padding(UITuning.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PrefTheme.cardFill, in: RoundedRectangle(cornerRadius: UITuning.cardCorner))
        .overlay(RoundedRectangle(cornerRadius: UITuning.cardCorner)
            .strokeBorder(isSelected ? PrefTheme.accent : PrefTheme.cardStroke, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { selecting ? onToggleSelected() : onToggleExpanded() }
        .onHover { hovering = $0; if !$0 { justCopied = false } }
    }

    private var sourceLabel: String {
        if let name = record.sourceName, !name.isEmpty { return name }
        return record.source.displayName
    }
}

/// A small grey fact under a saved entry.
private struct MetaChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

import AVFoundation
import DictatoCore
import SwiftUI

/// The ordered list of microphones on the General tab.
///
/// Dictato walks the list from the top and records from the first device that is plugged
/// in, so the order is the whole setting. Only device ids are saved, and the list also
/// shows devices that are plugged in but not on it yet, so a new microphone is never
/// invisible.
struct MicrophonePriorityGroup: View {
    private let settings = Settings()

    /// The user's saved order, plus anything connected that is not on it yet.
    @State private var order: [String] = []
    @State private var connected: [MicrophoneDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: PrefTheme.groupHeadingGap) {
            PrefHeading("Microphone priority")
            card
            Text("Microphones are tried in priority order. Drag to reorder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: reload)
        // The list has to answer when AirPods connect or a USB microphone is unplugged
        // while Preferences is open, or it shows a device that is no longer there.
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            reload()
        }
    }

    @ViewBuilder private var card: some View {
        Group {
            if order.isEmpty {
                PrefEmptyState(icon: "mic.slash",
                               title: "No microphones found",
                               message: "Plug one in, or check that Dictato is allowed to use the microphone.")
            } else {
                // A List rather than a hand-rolled stack, because `onMove` is the only
                // drag reordering on macOS that behaves the way the rest of the system
                // does. Its own scrolling is switched off so the page keeps scrolling as
                // one piece.
                List {
                    ForEach(order, id: \.self) { id in
                        row(for: id)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove(perform: move)
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: listHeight)
            }
        }
        .background(PrefTheme.cardFill, in: RoundedRectangle(cornerRadius: UITuning.cardCorner))
        .overlay(RoundedRectangle(cornerRadius: UITuning.cardCorner)
            .strokeBorder(PrefTheme.cardStroke, lineWidth: 1))
    }

    /// The list has to be told how tall it is, because its own scrolling is switched off
    /// and it would otherwise take whatever height it feels like. A row never goes below
    /// what a List row is willing to be, so the taller of the two is used.
    private var listHeight: CGFloat {
        CGFloat(order.count) * (max(PrefTheme.rowMinHeight, 28) + 2) + 10
    }

    private func row(for id: String) -> some View {
        let isConnected = connected.contains { $0.id == id }
        return HStack(spacing: PrefTheme.rowIconGap) {
            Image(systemName: isConnected ? "mic" : "mic.slash")
                .font(.system(size: 13))
                .foregroundStyle(isConnected ? PrefTheme.iconTint : Color.secondary.opacity(0.5))
                .frame(width: PrefTheme.rowIconWidth, alignment: .leading)
            Text(MicrophoneDevices.name(for: id))
                .font(.callout)
                .foregroundStyle(isConnected ? Color.primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if id == inUseID {
                Circle()
                    .fill(PrefTheme.online)
                    .frame(width: 8, height: 8)
                    .help("Dictato records from this microphone")
            } else if !isConnected {
                Text("Not plugged in").font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, UITuning.cardPadding)
        .frame(height: PrefTheme.rowMinHeight)
        .contentShape(Rectangle())
    }

    /// The device the next recording will use: the first one on the list that is plugged
    /// in, or the system's own default when the list has nothing to offer.
    private var inUseID: String? {
        MicrophonePriority.firstAvailable(order: order, available: connected.map(\.id))
            ?? MicrophoneDevices.systemDefault()?.id
    }

    private func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func reload() {
        connected = MicrophoneDevices.available()
        order = MicrophonePriority.listing(
            order: MicrophonePriority.decode(json: settings.microphonePriority),
            available: connected.map(\.id))
    }

    private func save() {
        settings.microphonePriority = MicrophonePriority.encode(order)
    }
}

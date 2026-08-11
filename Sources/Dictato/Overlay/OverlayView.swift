import SwiftUI
import AppKit

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @State private var hovering = false

    /// Shared with OverlayPanel, which must resize its content rect to match — a card
    /// taller than the panel is simply clipped.
    static let cardWidth: CGFloat = 330
    static let collapsedHeight: CGFloat = 62
    static let liveTextHeight: CGFloat = 86

    static func cardHeight(liveText: String) -> CGFloat {
        liveText.isEmpty ? collapsedHeight : liveTextHeight
    }

    private var cardWidth: CGFloat { Self.cardWidth }
    private var cardHeight: CGFloat { Self.cardHeight(liveText: model.liveText) }

    var body: some View {
        content
            .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .recording:
            card { recordingBody }
                .overlay(alignment: .topTrailing) { if hovering { cancelButton } }
                .onHover { hovering = $0 }
        case .processing:
            card { centeredRow { ProgressView().controlSize(.small); Text("Processing…") } }
        case .success:
            card { centeredRow { ProgressView().controlSize(.small); Text("Processing…") } }
        case .error(let message):
            card {
                centeredRow { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow); Text(message).lineLimit(1) }
            }
        }
    }

    private var recordingBody: some View {
        VStack(spacing: 6) {
            HStack {
                targetApp
                Spacer(minLength: 8)
                brand
            }
            if !model.liveText.isEmpty {
                Text(model.liveText)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.head)   // keep the newest words visible
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            waveform
        }
    }

    private var cancelButton: some View {
        Button {
            model.onCancel?()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Cancel recording")
    }

    private var targetApp: some View {
        HStack(spacing: 6) {
            if let icon = model.targetAppIcon {
                Image(nsImage: icon).resizable().frame(width: 17, height: 17)
            } else {
                Image(systemName: "app.dashed").frame(width: 17, height: 17)
            }
            Text(model.targetAppName ?? "")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var brand: some View {
        HStack(spacing: 6) {
            logo
            Text("Dictato")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize()
    }

    private var logo: some View {
        Group {
            if let img = LanguageGlyph.image(named: LanguageGlyph.overlayLogoName(for: model.languageCode)) {
                Image(nsImage: img).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "waveform").frame(width: 16, height: 16)
            }
        }
    }

    /// Full-width bar lattice spanning edge-to-edge (aligned with the top row).
    /// Most recent levels align to the right and rise with speech.
    private var waveform: some View {
        let slots = OverlayModel.waveformSlots
        let levels = model.levels
        let pad = max(0, slots - levels.count)
        let trackHeight: CGFloat = 20
        return GeometryReader { geo in
            let colW = geo.size.width / CGFloat(slots)
            HStack(spacing: 0) {
                ForEach(0..<slots, id: \.self) { i in
                    let level: Float = i < pad ? 0 : levels[i - pad]
                    let clamped = CGFloat(min(max(level, 0), 1))
                    Capsule()
                        .fill(.primary.opacity(0.3 + Double(clamped) * 0.55))
                        .frame(width: min(3, colW * 0.7), height: max(3, clamped * trackHeight))
                        .frame(width: colW)
                }
            }
            // Fill the reader and centre: a GeometryReader pins its child to the top, so
            // without this the whole row rides up when the bars are short and drops as
            // they grow. Bars should extend symmetrically from a fixed centre line.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(height: trackHeight)
        .animation(.linear(duration: 0.05), value: model.levels)
    }

    private func centeredRow<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) { c() }.font(.callout)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: cardWidth, height: cardHeight)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }
}

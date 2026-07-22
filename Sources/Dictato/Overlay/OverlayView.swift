import SwiftUI
import AppKit

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @State private var hovering = false

    private let cardWidth: CGFloat = 360
    private let cardHeight: CGFloat = 78

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
        VStack(spacing: 8) {
            HStack {
                targetApp
                Spacer(minLength: 8)
                brand
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
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20)
            }
            Text(model.targetAppName ?? "")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var brand: some View {
        HStack(spacing: 6) {
            logo
            Text("Dictato")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize()
    }

    private var logo: some View {
        Group {
            if let url = Bundle.main.url(forResource: "DictatoLogo", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "waveform").frame(width: 18, height: 18)
            }
        }
    }

    /// Full-width bar lattice spanning edge-to-edge (aligned with the top row).
    /// Most recent levels align to the right and rise with speech.
    private var waveform: some View {
        let slots = OverlayModel.waveformSlots
        let levels = model.levels
        let pad = max(0, slots - levels.count)
        return GeometryReader { geo in
            let colW = geo.size.width / CGFloat(slots)
            HStack(spacing: 0) {
                ForEach(0..<slots, id: \.self) { i in
                    let level: Float = i < pad ? 0 : levels[i - pad]
                    let clamped = CGFloat(min(max(level, 0), 1))
                    Capsule()
                        .fill(.primary.opacity(0.3 + Double(clamped) * 0.55))
                        .frame(width: min(3, colW * 0.7), height: max(3, clamped * 26))
                        .frame(width: colW)
                }
            }
        }
        .frame(height: 28)
        .animation(.linear(duration: 0.05), value: model.levels)
    }

    private func centeredRow<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) { c() }.font(.callout)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: cardWidth, height: cardHeight)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }
}

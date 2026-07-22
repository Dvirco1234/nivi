import SwiftUI
import AppKit

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

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

    /// Full-width dot lattice; most recent levels align right and rise with speech.
    private var waveform: some View {
        let slots = OverlayModel.waveformSlots
        let levels = model.levels
        let pad = max(0, slots - levels.count)
        return HStack(alignment: .center, spacing: 3) {
            ForEach(0..<slots, id: \.self) { i in
                let level: Float = i < pad ? 0 : levels[i - pad]
                Capsule()
                    .fill(.primary.opacity(0.35 + Double(min(level, 1)) * 0.5))
                    .frame(width: 3, height: max(3, CGFloat(min(level, 1)) * 26))
            }
        }
        .frame(maxWidth: .infinity)
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

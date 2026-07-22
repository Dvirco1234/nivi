import SwiftUI
import AppKit

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private let cardWidth: CGFloat = 420
    private let cardHeight: CGFloat = 60

    var body: some View {
        content
            .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .recording:
            card { recordingRow }
        case .processing:
            card { centeredRow { ProgressView().controlSize(.small); Text("Processing…") } }
        case .success:
            card {
                centeredRow { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Text inserted") }
            }
        case .error(let message):
            card {
                centeredRow { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow); Text(message).lineLimit(1) }
            }
        }
    }

    private var recordingRow: some View {
        HStack(spacing: 10) {
            targetApp
            waveform.frame(maxWidth: .infinity)
            brand
        }
    }

    private var targetApp: some View {
        HStack(spacing: 6) {
            if let icon = model.targetAppIcon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.dashed").frame(width: 22, height: 22)
            }
            Text(model.targetAppName ?? "")
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 104, alignment: .leading)
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
                Image(nsImage: img).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "waveform").frame(width: 20, height: 20)
            }
        }
    }

    /// Fixed lattice of dots filling the middle; most recent levels align to the right,
    /// rising in height with speech. Silence stays as a flat baseline of dots.
    private var waveform: some View {
        let slots = OverlayModel.waveformSlots
        let levels = model.levels
        let pad = max(0, slots - levels.count)
        return HStack(alignment: .center, spacing: 3) {
            ForEach(0..<slots, id: \.self) { i in
                let level: Float = i < pad ? 0 : levels[i - pad]
                Capsule()
                    .fill(.primary.opacity(0.6))
                    .frame(width: 3, height: max(3, CGFloat(level) * 26))
            }
        }
        .frame(height: 28)
        .animation(.linear(duration: 0.06), value: model.levels)
    }

    private func centeredRow<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) { c() }.font(.callout)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: cardWidth, height: cardHeight)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }
}

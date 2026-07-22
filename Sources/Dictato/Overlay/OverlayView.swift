import SwiftUI
import AppKit

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        content
            .frame(width: 320, height: 64)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .recording(let elapsed):
            card(recording: true) { recordingRow(elapsed: elapsed) }
        case .processing:
            card(recording: false) { centeredRow { ProgressView().controlSize(.small); Text("Processing…") } }
        case .success:
            card(recording: false) {
                centeredRow { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Text inserted") }
            }
        case .error(let message):
            card(recording: false) {
                centeredRow { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow); Text(message).lineLimit(1) }
            }
        }
    }

    private func recordingRow(elapsed: TimeInterval) -> some View {
        HStack(spacing: 8) {
            targetApp
            Spacer(minLength: 6)
            waveform
            Spacer(minLength: 6)
            brand
        }
    }

    private var targetApp: some View {
        HStack(spacing: 6) {
            if let icon = model.targetAppIcon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20)
            }
            Text(model.targetAppName ?? "").font(.callout).lineLimit(1)
        }
        .frame(maxWidth: 110, alignment: .leading)
    }

    private var brand: some View {
        HStack(spacing: 6) {
            logo
            Text("Dictato").font(.callout).foregroundStyle(.secondary)
        }
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

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Circle()
                    .fill(.primary.opacity(0.75))
                    .frame(width: 3, height: max(3, CGFloat(level) * 22))
            }
        }
        .frame(height: 22)
        .animation(.linear(duration: 0.05), value: model.levels)
    }

    private func centeredRow<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) { c() }.font(.callout)
    }

    private func card<C: View>(recording: Bool, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 320, height: 64)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(recording ? Color.red.opacity(0.8) : Color.white.opacity(0.12),
                                  lineWidth: recording ? 1.5 : 1)
            )
    }
}

import SwiftUI

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        Group {
            switch model.phase {
            case .hidden:
                EmptyView()
            case .recording(let elapsed):
                recordingView(elapsed: elapsed)
            case .processing:
                statusView { ProgressView().controlSize(.small) } label: { Text("Processing…") }
            case .success:
                statusView {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } label: { Text("Text inserted") }
            case .error(let message):
                statusView {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                } label: { Text(message).lineLimit(1) }
            }
        }
        .frame(width: 240, height: 90)
    }

    private func recordingView(elapsed: TimeInterval) -> some View {
        card {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Recording Hebrew…").font(.callout)
                    Text(timeString(elapsed))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                waveform
            }
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.primary.opacity(0.7))
                    .frame(width: 3, height: max(2, CGFloat(level) * 24))
            }
        }
        .frame(height: 24)
        .animation(.linear(duration: 0.05), value: model.levels)
    }

    private func statusView<Icon: View, Label: View>(
        @ViewBuilder _ icon: () -> Icon, @ViewBuilder label: () -> Label
    ) -> some View {
        card {
            HStack(spacing: 8) {
                icon()
                label().font(.callout)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
    }

    private func timeString(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

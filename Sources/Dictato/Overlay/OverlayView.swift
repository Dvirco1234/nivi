import SwiftUI
import AppKit

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    /// Watching the tuning store means dragging a slider in Preferences redraws the
    /// card while it is on screen, which is the only way to judge these numbers.
    @ObservedObject private var tuning = UITuning.Store.shared
    @State private var hovering = false
    @State private var glowPhase: Double = 0

    /// Shared with OverlayPanel, which must resize its content rect to match — a card
    /// taller than the panel is simply clipped.
    static var cardWidth: CGFloat { UITuning.panelWidth }
    static var collapsedHeight: CGFloat { UITuning.panelHeight }
    static var liveTextHeight: CGFloat { UITuning.panelTextHeight }

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
            card(glowing: true) { recordingBody }
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
        VStack(spacing: 5) {
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
                .font(.system(size: 17))
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(5)
        .help("Cancel recording")
    }

    private var targetApp: some View {
        HStack(spacing: 6) {
            if let icon = model.targetAppIcon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed").frame(width: 16, height: 16)
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
                Image(nsImage: img).resizable().frame(width: 15, height: 15)
            } else {
                Image(systemName: "waveform").frame(width: 15, height: 15)
            }
        }
    }

    /// Full-width bar lattice spanning edge-to-edge (aligned with the top row).
    /// Most recent levels align to the right and rise with speech.
    private var waveform: some View {
        let slots = OverlayModel.waveformSlots
        let levels = model.levels
        let pad = max(0, slots - levels.count)
        let trackHeight: CGFloat = 16
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

    private func card<C: View>(glowing: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        let shape = RoundedRectangle(cornerRadius: UITuning.panelCorner, style: .continuous)
        return content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: cardWidth, height: cardHeight)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(UITuning.panelBorderOpacity), lineWidth: 0.5))
            .overlay { if glowing { movingGlow(shape: shape) } }
    }

    /// Colours for the travelling glow. The first and last stop are both clear so the
    /// gradient meets itself without a seam as it turns.
    private static let glowColors: [Color] = [
        .clear,
        Color(red: 0.35, green: 0.78, blue: 1.00),
        Color(red: 0.55, green: 0.50, blue: 1.00),
        .clear,
        .clear,
        Color(red: 0.35, green: 0.78, blue: 1.00).opacity(0.45),
        .clear,
        .clear,
    ]

    /// A band of soft colour that keeps travelling around the card's edge while
    /// recording, so the card looks alive even during a silent pause.
    ///
    /// The movement is one rotation of a gradient, which the graphics card handles on
    /// its own: the view body is not re-run per frame and nothing is redrawn from
    /// scratch. Speaking only nudges the brightness, so a quiet voice still gets the
    /// same motion. The whole thing exists only in the recording case, so it stops the
    /// moment recording does.
    private func movingGlow(shape: RoundedRectangle) -> some View {
        let level = Double(min(max(model.levels.last ?? 0, 0), 1))
        // The gradient square has to cover the card even when turned side-on, so it is
        // as wide as the card's diagonal and is allowed to spill past the edges.
        let diagonal = sqrt(cardWidth * cardWidth + cardHeight * cardHeight)
        return Color.clear
            .overlay {
                Rectangle()
                    .fill(AngularGradient(colors: Self.glowColors, center: .center))
                    .frame(width: diagonal, height: diagonal)
                    .rotationEffect(.degrees(glowPhase))
            }
            .mask(shape.strokeBorder(lineWidth: UITuning.panelGlowWidth * 2))
            .blur(radius: UITuning.panelGlowWidth)
            // The blur throws light well past the edge it was masked to. Nothing held it
            // to the card's rounded corners, only to the window's square ones, so
            // wherever the bright part of the glow happened to be it filled the corner
            // and the card looked like it had a bigger radius on that side. Cutting the
            // glow to the card's own shape pins the outline and leaves only the
            // brightness travelling.
            .clipShape(shape)
            .opacity(UITuning.panelGlowOpacity * (0.7 + 0.3 * level))
            .allowsHitTesting(false)
            .onAppear {
                glowPhase = 0
                withAnimation(.linear(duration: UITuning.panelGlowSeconds)
                    .repeatForever(autoreverses: false)) {
                    glowPhase = 360
                }
            }
    }
}

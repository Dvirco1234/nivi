import SwiftUI
import AppKit

/// The recording UI as a bar hugging the top of the screen.
///
/// On a MacBook with a notch the bar sits behind and around it, so the black card reads
/// as an extension of the notch rather than a window floating near it — which is why the
/// background is opaque black rather than the panel style's translucent material, and why
/// the top corners stay square while the bottom ones are rounded.
struct NotchOverlayView: View {
    @ObservedObject var model: OverlayModel
    /// Watching the tuning store means dragging a slider in Preferences redraws the bar
    /// while it is on screen, which is the only way to judge these numbers.
    @ObservedObject private var tuning = UITuning.Store.shared
    /// Width of the physical notch to leave clear. Zero on displays without one, which
    /// collapses this into a small centred tab at the top of the screen.
    let notchWidth: CGFloat
    /// Height of the strip the camera notch and the menu bar occupy, measured from the
    /// display. Matching it is what makes the bar read as part of the hardware instead
    /// of a separate bar hanging below it.
    let stripHeight: CGFloat

    /// Left of the notch: the two icons and nothing else, so the bar stays narrow.
    /// The inset counts twice, once before the first icon and once after the last, so
    /// the pair sits with the same air on either side.
    static var leftWidth: CGFloat {
        UITuning.notchIconSize * 2 + UITuning.notchIconGap + UITuning.notchIconInset * 2
    }

    /// Right of the notch: a fixed strip for the wave, which nothing else shares.
    static var rightWidth: CGFloat { UITuning.notchWaveWidth }

    static func barWidth(notchWidth: CGFloat) -> CGFloat {
        leftWidth + max(notchWidth, 0) + rightWidth
    }

    /// The bar only grows past the notch when there is live text to hang under it.
    static func barHeight(stripHeight: CGFloat, liveText: String) -> CGFloat {
        liveText.isEmpty ? stripHeight : stripHeight + UITuning.notchTextHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftSide
                    .frame(width: Self.leftWidth)
                // The notch itself: kept empty so nothing is ever hidden behind it.
                Color.clear.frame(width: max(notchWidth, 0))
                rightSide
                    .frame(width: Self.rightWidth)
            }
            .frame(height: stripHeight)

            if !model.liveText.isEmpty {
                Text(model.liveText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Self.barWidth(notchWidth: notchWidth),
               height: Self.barHeight(stripHeight: stripHeight, liveText: model.liveText))
        .background(Color.black)
        .clipShape(BottomRoundedRectangle(radius: 12))
    }

    /// Identity on one side, the meter on the other — the two sides show different
    /// things rather than mirroring, so nothing appears twice.
    ///
    /// The icons start `notchIconInset` in from the left edge, and the strip is sized so
    /// the same gap is left before the notch. The trailing spacer keeps them anchored to
    /// the left when one of the two icons is missing.
    private var leftSide: some View {
        let size = UITuning.notchIconSize
        return HStack(spacing: UITuning.notchIconGap) {
            if let img = LanguageGlyph.image(named: LanguageGlyph.overlayLogoName(for: model.languageCode)) {
                Image(nsImage: img).resizable().frame(width: size, height: size)
            }
            if let icon = model.targetAppIcon {
                Image(nsImage: icon).resizable().frame(width: size, height: size).opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, UITuning.notchIconInset)
    }

    /// The wave starts at the right edge of the notch and fills its strip.
    private var rightSide: some View {
        waveform
            .frame(width: Self.rightWidth, alignment: .leading)
    }

    /// Newest levels sit at the right edge and the bars grow from a fixed centre line,
    /// so the row never shifts as the level changes.
    private var waveform: some View {
        let barWidth: CGFloat = 2
        let gap: CGFloat = 2
        // As many bars as the strip holds, so changing its width keeps the same look.
        let slots = max(1, Int((Self.rightWidth + gap) / (barWidth + gap)))
        let levels = model.levels
        return HStack(spacing: gap) {
            ForEach(0..<slots, id: \.self) { i in
                let index = slots - 1 - i
                let level = levels.count > index ? levels[levels.count - 1 - index] : 0
                let clamped = CGFloat(min(max(level, 0), 1))
                Capsule()
                    .fill(.white.opacity(0.35 + Double(clamped) * 0.55))
                    .frame(width: barWidth, height: max(2, clamped * 16))
            }
        }
        .frame(height: 16)
        .animation(.linear(duration: 0.05), value: model.levels)
    }
}

/// Square at the top so the bar meets the screen edge, rounded below.
private struct BottomRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

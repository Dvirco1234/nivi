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
    /// Width of the physical notch to leave clear. Zero on displays without one, which
    /// collapses this into an ordinary centred top bar.
    let notchWidth: CGFloat

    static let barHeight: CGFloat = 34
    static let liveTextHeight: CGFloat = 58
    /// Waveform width on each side of the notch.
    static let sideWidth: CGFloat = 132

    static func barWidth(notchWidth: CGFloat) -> CGFloat {
        sideWidth * 2 + max(notchWidth, 0)
    }

    static func barHeight(liveText: String) -> CGFloat {
        liveText.isEmpty ? barHeight : liveTextHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftSide
                    .frame(width: Self.sideWidth)
                // The notch itself: kept empty so nothing is ever hidden behind it.
                Color.clear.frame(width: notchWidth)
                rightSide
                    .frame(width: Self.sideWidth)
            }
            .frame(height: Self.barHeight)

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
               height: Self.barHeight(liveText: model.liveText))
        .background(Color.black)
        .clipShape(BottomRoundedRectangle(radius: 12))
    }

    private var leftSide: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let icon = model.targetAppIcon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            waveform(mirrored: true)
                .frame(width: 78)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
    }

    private var rightSide: some View {
        HStack(spacing: 8) {
            waveform(mirrored: false)
                .frame(width: 78)
            if let img = LanguageGlyph.image(named: LanguageGlyph.overlayLogoName(for: model.languageCode)) {
                Image(nsImage: img).resizable().frame(width: 16, height: 16)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
    }

    /// Levels run outward from the notch on both sides, so the newest audio is nearest
    /// the centre and the bar reads as one symmetric meter.
    private func waveform(mirrored: Bool) -> some View {
        let slots = 18
        let levels = model.levels
        return HStack(spacing: 2) {
            ForEach(0..<slots, id: \.self) { i in
                let index = mirrored ? i : slots - 1 - i
                let level = levels.count > index ? levels[levels.count - 1 - index] : 0
                let clamped = CGFloat(min(max(level, 0), 1))
                Capsule()
                    .fill(.white.opacity(0.35 + Double(clamped) * 0.55))
                    .frame(width: 2, height: max(2, clamped * 16))
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

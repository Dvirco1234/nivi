import SwiftUI
import DictatoCore

/// Picks the recording display by showing what each one looks like.
///
/// The two options differ only visually, so a pair of labelled thumbnails communicates
/// the choice far better than the words "Panel" and "Notch" do.
struct RecordingDisplayPicker: View {
    @Binding var selection: RecordingDisplay

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(RecordingDisplay.allCases, id: \.self) { option in
                VStack(spacing: 6) {
                    thumbnail(for: option)
                        .frame(width: 132, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(option == selection ? Color.accentColor : .white.opacity(0.12),
                                              lineWidth: option == selection ? 2.5 : 1)
                        )
                    Text(option.displayName)
                        .font(.caption)
                        .fontWeight(option == selection ? .semibold : .regular)
                        .foregroundStyle(option == selection ? .primary : .secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { selection = option }
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(option == selection ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    @ViewBuilder private func thumbnail(for option: RecordingDisplay) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.44, blue: 0.72),
                                    Color(red: 0.78, green: 0.62, blue: 0.66)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            switch option {
            case .panel:
                miniBars(count: 22, tint: .black.opacity(0.55))
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(.white.opacity(0.92), in: Capsule())
                    .padding(.horizontal, 12)
            case .notch:
                VStack {
                    HStack(spacing: 6) {
                        miniBars(count: 7, tint: .white.opacity(0.85))
                        // The notch itself, left clear in the real bar too.
                        Capsule().fill(.black).frame(width: 16, height: 6)
                        miniBars(count: 7, tint: .white.opacity(0.85))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    Spacer()
                }
            }
        }
    }

    private func miniBars(count: Int, tint: Color) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(tint)
                    .frame(width: 1.5, height: barHeight(i, count: count))
            }
        }
    }

    /// A fixed pseudo-waveform: taller in the middle so the thumbnail reads as speech
    /// rather than a flat row, without animating anything in Preferences.
    private func barHeight(_ index: Int, count: Int) -> CGFloat {
        let mid = Double(count - 1) / 2
        let distance = abs(Double(index) - mid) / max(mid, 1)
        return 3 + CGFloat((1 - distance) * (1 - distance) * 8)
    }
}

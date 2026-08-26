import SwiftUI
import AppKit
import NiviCore

/// Picks the recording display by showing what each one looks like.
///
/// The two options differ only visually, so a pair of labelled pictures communicates the
/// choice far better than the words "Panel" and "Notch" do.
///
/// The pictures are real screenshots of the two overlays, taken against a made-up
/// colourful background. They used to be hand-drawn SwiftUI shapes, which drifted away
/// from the real thing every time the overlays were restyled. Regenerate them with
/// `bash Tools/make-recording-thumbnails.sh` after any change to how the overlays look.
struct RecordingDisplayPicker: View {
    @Binding var selection: RecordingDisplay
    @ObservedObject private var tuning = UITuning.Store.shared

    var body: some View {
        HStack(alignment: .top, spacing: UITuning.recordingThumbnailGap) {
            ForEach(RecordingDisplay.allCases, id: \.self) { option in
                VStack(spacing: 6) {
                    thumbnail(for: option)
                        .frame(width: UITuning.recordingThumbnailWidth,
                               height: UITuning.recordingThumbnailHeight)
                        .clipShape(RoundedRectangle(cornerRadius: UITuning.recordingThumbnailCorner))
                        .overlay(
                            RoundedRectangle(cornerRadius: UITuning.recordingThumbnailCorner)
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
        if let picture = Self.picture(for: option) {
            Image(nsImage: picture)
                .resizable()
                .interpolation(.high)
                // The picture is cut to the same shape as the frame, so filling can only
                // ever trim a rounding error rather than a visible slice.
                .aspectRatio(contentMode: .fill)
        } else {
            // Only reachable if the PNG is missing from the app bundle. Better a plain
            // coloured tile than an empty hole where the choice should be.
            LinearGradient(colors: [Color(red: 0.30, green: 0.34, blue: 0.72),
                                    Color(red: 0.80, green: 0.48, blue: 0.58)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Loaded once and kept, because Preferences redraws this row on every keystroke in
    /// the window and reading two PNGs off disk each time is pure waste.
    private static var cache: [RecordingDisplay: NSImage] = [:]

    private static func picture(for option: RecordingDisplay) -> NSImage? {
        if let hit = cache[option] { return hit }
        let name: String
        switch option {
        case .panel: name = "RecordingDisplayPanel"
        case .notch: name = "RecordingDisplayNotch"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[option] = image
        return image
    }
}

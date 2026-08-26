import AppKit

/// A small tap in the trackpad, so a recording that starts or stops can be felt without
/// looking at the screen.
///
/// Only trackpads that support Force Touch can do this. On any other Mac
/// `NSHapticFeedbackManager` accepts the call and nothing happens, which is why there is
/// no check here and nothing to report.
enum Haptics {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

import AppKit

/// Chooses the aleph (Hebrew) vs Latin-A (English) artwork for a language.
/// English → Latin A; everything else (Hebrew, multilingual, …) → aleph.
enum LanguageGlyph {
    static func overlayLogoName(for language: String) -> String {
        language == "en" ? "NiviLogoEn" : "NiviLogo"
    }

    static func menuBarName(for language: String) -> String {
        language == "en" ? "MenuBarLatinA" : "MenuBarAleph"
    }

    /// Kept because the overlay redraws as fast as the audio meter updates, and reading
    /// the same PNG off disk many times a second is pure waste. Only ever touched from
    /// the main thread, which is where both the overlay and the menu bar draw.
    private static var loaded: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let hit = loaded[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        loaded[name] = image
        return image
    }

    /// How wide the menu bar glyph is for a given height. Both language versions are
    /// drawn on the same canvas, so one of them settles it for both.
    static func menuBarAspectRatio() -> CGFloat {
        guard let image = image(named: "MenuBarAleph"), image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }
}

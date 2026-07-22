import AppKit

/// Chooses the aleph (Hebrew) vs Latin-A (English) artwork for a language.
/// English → Latin A; everything else (Hebrew, multilingual, …) → aleph.
enum LanguageGlyph {
    static func overlayLogoName(for language: String) -> String {
        language == "en" ? "DictatoLogoEn" : "DictatoLogo"
    }

    static func menuBarName(for language: String) -> String {
        language == "en" ? "MenuBarLatinA" : "MenuBarAleph"
    }

    static func image(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

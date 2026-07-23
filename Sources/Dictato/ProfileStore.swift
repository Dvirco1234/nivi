import Foundation
import DictatoCore

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var set: ProfileSet

    private let settings = Settings()

    /// - Parameters:
    ///   - defaultModelID: primary model to seed on first launch (from ModelCatalog).
    ///   - defaultLanguage: that model's language.
    init(defaultModelID: String?, defaultLanguage: String) {
        if let decoded = Self.load(from: settings.profilesJSON), !decoded.profiles.isEmpty {
            set = decoded.normalizedPrimary()
            if set != decoded { persist() }
        } else {
            let name = ProfileStore.languageName(defaultLanguage)
            set = ProfileSet.migrated(from: settings.dictateBinding,
                                      modelID: defaultModelID,
                                      language: defaultLanguage, name: name)
            persist()
            Log.info("Seeded initial dictation profile from legacy settings")
        }
    }

    var cancelBinding: HotkeyBinding { settings.cancelBinding }

    func conflict(for hotkey: HotkeyBinding, excluding id: String?) -> Bool {
        set.conflict(for: hotkey, excluding: id, cancel: settings.cancelBinding)
    }

    func upsert(_ profile: DictationProfile) {
        set = set.upserting(profile)
        changed()
    }

    func remove(_ id: String) {
        set = set.removing(id: id)
        changed()
    }

    func setPrimary(_ id: String) {
        set = set.settingPrimary(id)
        changed()
    }

    func newProfileID() -> String {
        var n = set.profiles.count + 1
        while set.profiles.contains(where: { $0.id == "profile-\(n)" }) { n += 1 }
        return "profile-\(n)"
    }

    private func changed() {
        persist()
        NotificationCenter.default.post(name: .dictatoProfilesChanged, object: nil)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(set),
           let json = String(data: data, encoding: .utf8) {
            settings.profilesJSON = json
        }
    }

    private static func load(from json: String) -> ProfileSet? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProfileSet.self, from: data)
    }

    static func languageName(_ code: String) -> String {
        switch code {
        case "he": return "Hebrew"
        case "en": return "English"
        case "auto", "": return "Multilingual"
        default: return code.uppercased()
        }
    }
}

extension Notification.Name {
    static let dictatoProfilesChanged = Notification.Name("dictatoProfilesChanged")
}

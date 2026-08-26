import Foundation

public struct DictationProfile: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var modelID: String
    public var language: String
    public var mode: InsertionMode
    public var hotkey: HotkeyBinding

    public init(id: String, name: String, modelID: String, language: String,
                mode: InsertionMode, hotkey: HotkeyBinding) {
        self.id = id; self.name = name; self.modelID = modelID
        self.language = language; self.mode = mode; self.hotkey = hotkey
    }

    public var languageLabel: String {
        switch language {
        case "he": return "Hebrew"
        case "en": return "English"
        case "auto", "": return "Multilingual"
        default: return language.uppercased()
        }
    }
}

public struct ProfileSet: Codable, Equatable {
    public var profiles: [DictationProfile]
    public var primaryID: String

    public init(profiles: [DictationProfile], primaryID: String) {
        self.profiles = profiles
        self.primaryID = primaryID
    }

    public func profile(id: String) -> DictationProfile? { profiles.first { $0.id == id } }
    public var primary: DictationProfile? { profile(id: primaryID) }

    /// True if `hotkey` collides with any other profile (excluding `id`) or with `cancel`.
    /// Modifier-tap bindings collide when they share a modifier key regardless of tap count
    /// (the router builds one detector per key). Key-combos collide on exact equality.
    public func conflict(for hotkey: HotkeyBinding, excluding id: String?, cancel: HotkeyBinding) -> Bool {
        if Self.collides(hotkey, cancel) { return true }
        return profiles.contains { p in
            p.id != id && Self.collides(p.hotkey, hotkey)
        }
    }

    private static func collides(_ a: HotkeyBinding, _ b: HotkeyBinding) -> Bool {
        switch (a, b) {
        case let (.modifierTap(ka, _), .modifierTap(kb, _)):
            return ka.keyCode == kb.keyCode
        default:
            return a == b
        }
    }

    /// Seed a single primary profile from the legacy single-dictate binding.
    public static func migrated(from dictate: HotkeyBinding, modelID: String?,
                                language: String, name: String) -> ProfileSet {
        let profile = DictationProfile(
            id: "profile-1", name: name, modelID: modelID ?? "",
            language: language, mode: .batch, hotkey: dictate)
        return ProfileSet(profiles: [profile], primaryID: profile.id)
    }

    /// Remove a profile unless it is the last one; re-point primary if it was removed.
    public func removing(id: String) -> ProfileSet {
        guard profiles.count > 1 else { return self }
        let next = profiles.filter { $0.id != id }
        let primary = (primaryID == id) ? (next.first?.id ?? primaryID) : primaryID
        return ProfileSet(profiles: next, primaryID: primary).normalizedPrimary()
    }

    public func settingPrimary(_ id: String) -> ProfileSet {
        guard profile(id: id) != nil else { return self }
        return ProfileSet(profiles: profiles, primaryID: id)
    }

    /// Ensure `primaryID` resolves to an existing profile; otherwise fall back to first.
    public func normalizedPrimary() -> ProfileSet {
        if profile(id: primaryID) != nil { return self }
        return ProfileSet(profiles: profiles, primaryID: profiles.first?.id ?? "")
    }

    /// Upsert a profile (replace by id, else append).
    public func upserting(_ p: DictationProfile) -> ProfileSet {
        var list = profiles
        if let i = list.firstIndex(where: { $0.id == p.id }) { list[i] = p } else { list.append(p) }
        return ProfileSet(profiles: list, primaryID: primaryID).normalizedPrimary()
    }
}

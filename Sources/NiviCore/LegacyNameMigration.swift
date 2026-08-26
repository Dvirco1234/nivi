import Foundation

/// The app used to be called Dictato, and macOS files an app's data under its name.
///
/// Two things are keyed to the old name and would otherwise look empty under the new
/// one:
///
/// - the settings, which live in the `com.dvir.dictato` defaults domain. Without this
///   the user opens a fresh app: no profiles, no hotkeys, no chosen models.
/// - the folder `~/Library/Application Support/Dictato`, which holds the downloaded
///   models (the Hebrew one alone is about 1.6 GB), `history.jsonl` and
///   `ui-tuning.conf`.
///
/// Both moves run once, on the first launch under the new name, before anything reads
/// either place.
public enum LegacyNameMigration {
    /// The defaults domain the app wrote to when it was called Dictato.
    public static let oldSettingsDomain = "com.dvir.dictato"

    /// Set once the settings have been brought across, so this never runs twice. If it
    /// ran again it would undo a setting the user changed back after the rename.
    public static let didCopySettingsKey = "didCopySettingsFromDictato"

    /// Where the app kept its models, history and layout tuning under the old name.
    public static func legacySupportDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictato", isDirectory: true)
    }

    /// Copies the old settings into the new domain, once.
    ///
    /// A key that already has a value under the new name is left alone, so nothing the
    /// user has set since the rename is overwritten.
    ///
    /// Returns how many keys were copied, or nil if this had already run and did
    /// nothing.
    @discardableResult
    public static func copySettings(from oldDomain: String = oldSettingsDomain,
                                    to newDomain: String,
                                    using defaults: UserDefaults) -> Int? {
        let alreadyThere = defaults.persistentDomain(forName: newDomain) ?? [:]
        guard alreadyThere[didCopySettingsKey] == nil else { return nil }
        defaults.set(true, forKey: didCopySettingsKey)

        guard let old = defaults.persistentDomain(forName: oldDomain) else { return 0 }
        var copied = 0
        for (key, value) in old {
            guard key != didCopySettingsKey, alreadyThere[key] == nil else { continue }
            defaults.set(value, forKey: key)
            copied += 1
        }
        return copied
    }

    /// Renames the old support folder to the new one, once.
    ///
    /// A rename inside the same disk is a single step: the folder is either at the old
    /// name or at the new one, never half at each. Copying then deleting would not be
    /// safe here — the folder holds gigabytes of model files, and a copy stopped part
    /// way could leave a truncated model that the app then offers to download again.
    ///
    /// Does nothing if the old folder is gone or the new one already exists, so a
    /// second run cannot clobber current data.
    ///
    /// Returns true only if the folder was actually moved.
    @discardableResult
    public static func moveSupportDirectory(from old: URL, to new: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: old.path),
              !fileManager.fileExists(atPath: new.path) else { return false }
        do {
            try fileManager.createDirectory(at: new.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.moveItem(at: old, to: new)
            return true
        } catch {
            return false
        }
    }
}

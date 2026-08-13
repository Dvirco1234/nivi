import Foundation

public enum ModelPaths {
    public static func appSupportBase() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictato", isDirectory: true)
    }
    public static func modelsDir(base: URL) -> URL {
        base.appendingPathComponent("models", isDirectory: true)
    }
    public static func installedURL(for model: ManagedModel, base: URL) -> URL {
        if case .localFile(let path) = model.source { return URL(fileURLWithPath: path) }
        return modelsDir(base: base).appendingPathComponent(model.localFileName)
    }
}

public enum ModelCatalogStore {
    public static func load(from url: URL) -> ModelCatalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ModelCatalog.self, from: data)
    }

    public static func save(_ catalog: ModelCatalog, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(catalog) { try? data.write(to: url) }
    }

    public static func migrateLegacy(modelsDir: URL) {
        let legacy = modelsDir.appendingPathComponent("ggml-ivrit-large-v3-turbo.bin")
        let target = modelsDir.appendingPathComponent("ivrit-large-v3-turbo.bin")
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: target.path) else { return }
        try? fm.moveItem(at: legacy, to: target)
    }

    public static func bootstrap(catalogURL: URL, modelsDir: URL) -> ModelCatalog {
        migrateLegacy(modelsDir: modelsDir)
        guard let existing = load(from: catalogURL) else {
            let seeded = ModelCatalog.seeded()
            save(seeded, to: catalogURL)
            return seeded
        }
        let merged = mergingPresets(into: existing)
        if merged != existing { save(merged, to: catalogURL) }
        return merged
    }

    /// Folds the current built-in presets into a saved catalog.
    ///
    /// Without this, a catalog saved before a preset existed would never show it: the
    /// seed only ran on first launch, so anyone who had already used the app never saw
    /// models added later. Presets are refreshed in place so corrected metadata reaches
    /// existing installs too, while models the user added themselves are left alone.
    public static func mergingPresets(into existing: ModelCatalog) -> ModelCatalog {
        var models = existing.models
        for preset in ModelCatalog.seeded().models {
            if let index = models.firstIndex(where: { $0.id == preset.id }) {
                models[index] = preset
            } else {
                models.append(preset)
            }
        }
        return ModelCatalog(models: models, defaultModelID: existing.defaultModelID)
    }

    public static func isInstalled(_ model: ManagedModel, base: URL) -> Bool {
        let url = ModelPaths.installedURL(for: model, base: base)
        return ModelSpec(fileName: model.localFileName, url: url, minSizeBytes: model.minSizeBytes)
            .validate(fileAt: url) == .ok
    }

    /// A model may be deleted only if it is installed, not the default, and not the last installed one.
    public static func canDelete(_ id: String, from catalog: ModelCatalog, installedIDs: Set<String>) -> Bool {
        guard installedIDs.contains(id) else { return false }
        guard id != catalog.defaultModelID else { return false }
        return installedIDs.count > 1
    }
}

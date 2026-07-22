import Foundation
import DictatoCore

enum InstallState: Equatable {
    case notInstalled
    case downloading(Double)
    case installed
    case failed(String)
}

@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var catalog: ModelCatalog
    @Published private(set) var installStates: [String: InstallState] = [:]

    let base = ModelPaths.appSupportBase()
    private var catalogURL: URL { base.appendingPathComponent("models.json") }
    private let downloader = ModelDownloader()

    init() {
        catalog = ModelCatalogStore.bootstrap(
            catalogURL: base.appendingPathComponent("models.json"),
            modelsDir: ModelPaths.modelsDir(base: base))
        refreshInstalledStates()
    }

    func installedURL(for model: ManagedModel) -> URL {
        ModelPaths.installedURL(for: model, base: base)
    }

    func isInstalled(_ id: String) -> Bool { installStates[id] == .installed }

    func refreshInstalledStates() {
        for model in catalog.models {
            if ModelCatalogStore.isInstalled(model, base: base) {
                installStates[model.id] = .installed
            } else if installStates[model.id] == nil || installStates[model.id] == .installed {
                installStates[model.id] = .notInstalled
            }
        }
    }

    private var installedIDs: Set<String> {
        Set(catalog.models.map(\.id).filter { installStates[$0] == .installed })
    }

    func install(_ model: ManagedModel) async {
        installStates[model.id] = .downloading(0)
        do {
            try await downloader.download(model, to: installedURL(for: model)) { [weak self] f in
                self?.installStates[model.id] = .downloading(f)
            }
            installStates[model.id] = .installed
            Log.info("Model installed: \(model.id)")
        } catch {
            installStates[model.id] = .failed(error.localizedDescription)
            Log.error("Model install failed \(model.id): \(error.localizedDescription)")
        }
    }

    func delete(_ id: String) {
        guard ModelCatalogStore.canDelete(id, from: catalog, installedIDs: installedIDs),
              let model = catalog.model(id: id) else { return }
        try? FileManager.default.removeItem(at: installedURL(for: model))
        installStates[id] = .notInstalled
        Log.info("Model deleted: \(id)")
    }

    func setDefault(_ id: String) {
        guard catalog.model(id: id) != nil else { return }
        catalog.defaultModelID = id
        persist()
        NotificationCenter.default.post(name: .dictatoDefaultModelChanged, object: id)
    }

    func addModel(_ model: ManagedModel) {
        guard catalog.model(id: model.id) == nil else { return }
        catalog.models.append(model)
        installStates[model.id] = .notInstalled
        persist()
    }

    private func persist() {
        ModelCatalogStore.save(catalog, to: catalogURL)
    }
}

extension Notification.Name {
    static let dictatoDefaultModelChanged = Notification.Name("dictatoDefaultModelChanged")
}

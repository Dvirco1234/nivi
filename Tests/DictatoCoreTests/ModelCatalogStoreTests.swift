import XCTest
@testable import DictatoCore

final class ModelCatalogStoreTests: XCTestCase {
    private var base: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ModelPaths.modelsDir(base: base), withIntermediateDirectories: true)
    }
    func testMigrateLegacy() throws {
        let dir = ModelPaths.modelsDir(base: base)
        try Data([0x6C,0x6D,0x67,0x67,0,0,0,0]).write(to: dir.appendingPathComponent("ggml-ivrit-large-v3-turbo.bin"))
        ModelCatalogStore.migrateLegacy(modelsDir: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ivrit-large-v3-turbo.bin").path))
    }
    func testBootstrapSeeds() {
        let cat = ModelCatalogStore.bootstrap(catalogURL: base.appendingPathComponent("models.json"),
                                              modelsDir: ModelPaths.modelsDir(base: base))
        XCTAssertEqual(cat.defaultModelID, "ivrit-large-v3-turbo")
    }
    func testDeleteGuards() {
        let cat = ModelCatalog.seeded()
        XCTAssertFalse(ModelCatalogStore.canDelete("ivrit-large-v3-turbo", from: cat, installedIDs: ["ivrit-large-v3-turbo"]))
        XCTAssertFalse(ModelCatalogStore.canDelete("whisper-small-en", from: cat, installedIDs: ["ivrit-large-v3-turbo"]))
        XCTAssertTrue(ModelCatalogStore.canDelete("whisper-small-en", from: cat,
                      installedIDs: ["ivrit-large-v3-turbo", "whisper-small-en"]))
    }
}

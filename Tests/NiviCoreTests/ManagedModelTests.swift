import XCTest
@testable import NiviCore

final class ManagedModelTests: XCTestCase {
    func testHuggingFaceURL() {
        XCTAssertEqual(
            ModelSource.huggingFace(repo: "a/b", file: "m.bin").downloadURL?.absoluteString,
            "https://huggingface.co/a/b/resolve/main/m.bin")
    }
    func testLocalHasNoDownloadURL() {
        XCTAssertNil(ModelSource.localFile(path: "/tmp/m.bin").downloadURL)
    }
    func testSeededCatalog() {
        let c = ModelCatalog.seeded()
        XCTAssertEqual(c.defaultModelID, "ivrit-large-v3-turbo")
        XCTAssertEqual(c.models.count, 3)
        XCTAssertEqual(c.defaultModel?.localFileName, "ivrit-large-v3-turbo.bin")
    }
    func testCodableRoundTrip() throws {
        let c = ModelCatalog.seeded()
        let back = try JSONDecoder().decode(ModelCatalog.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }
}

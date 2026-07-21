import XCTest
@testable import DictatoCore

final class ModelSpecTests: XCTestCase {
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("dictato-tests", isDirectory: true)

    override func setUpWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func write(_ bytes: [UInt8], name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private var spec: ModelSpec {
        ModelSpec(fileName: "m.bin", url: URL(string: "https://example.com/m.bin")!, minSizeBytes: 8)
    }

    func testMissingFile() {
        XCTAssertEqual(spec.validate(fileAt: dir.appendingPathComponent("nope.bin")), .missing)
    }

    func testTooSmall() throws {
        let url = try write([0x6C, 0x6D, 0x67], name: "small.bin")
        XCTAssertEqual(spec.validate(fileAt: url), .tooSmall)
    }

    func testBadMagic() throws {
        let url = try write([0x00, 0x01, 0x02, 0x03, 0, 0, 0, 0], name: "bad.bin")
        XCTAssertEqual(spec.validate(fileAt: url), .badMagic)
    }

    func testValidFile() throws {
        // GGML magic 0x67676d6c stored little-endian: 6C 6D 67 67
        let url = try write([0x6C, 0x6D, 0x67, 0x67, 0, 0, 0, 0], name: "good.bin")
        XCTAssertEqual(spec.validate(fileAt: url), .ok)
    }

    func testIvritTurboSpec() {
        XCTAssertEqual(ModelSpec.ivritTurbo.fileName, "ggml-ivrit-large-v3-turbo.bin")
        XCTAssertEqual(
            ModelSpec.ivritTurbo.url.absoluteString,
            "https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin"
        )
        XCTAssertGreaterThan(ModelSpec.ivritTurbo.minSizeBytes, 1_000_000_000)
    }
}

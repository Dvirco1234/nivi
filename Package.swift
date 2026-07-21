// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Dictato",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DictatoCore"),
        .systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
        .executableTarget(
            name: "Dictato",
            dependencies: ["DictatoCore", "CWhisper"],
            linkerSettings: [
                .unsafeFlags(["-Lvendor/lib"]),
                .linkedLibrary("whisper"),
                .linkedLibrary("ggml"),
                .linkedLibrary("c++"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(name: "DictatoCoreTests", dependencies: ["DictatoCore"]),
    ]
)

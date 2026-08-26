// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Dictato",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Sparkle ships as a pre-built XCFramework, so it needs no Xcode to build.
        // The same download also brings the release tools the Makefile uses:
        // generate_keys, generate_appcast and sign_update.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "DictatoCore"),
        .systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
        .executableTarget(
            name: "Dictato",
            dependencies: ["DictatoCore", "CWhisper", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .unsafeFlags(["-Lvendor/lib"]),
                // Sparkle.framework is copied into Contents/Frameworks when the app
                // bundle is assembled, so the binary has to look for it there.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
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

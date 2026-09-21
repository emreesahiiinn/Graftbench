// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Absolute path to this package's Info.plist, resolved from the manifest's own
// location so it works from any build working directory — both `swift build`
// and Xcode (whose linker runs inside DerivedData).
let infoPlistPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Packaging/Info.plist")
    .path

let package = Package(
    name: "Graftbench",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Graftbench", targets: ["Graftbench"])
    ],
    targets: [
        .executableTarget(
            name: "Graftbench",
            path: "Sources/Graftbench",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                // Embed Info.plist into the executable so Bundle.main has a
                // proper bundle identifier even when the raw binary is run
                // directly (silences the "missing main bundle identifier" /
                // CoreUI / Intents console noise). In the packaged .app the
                // real Info.plist in Contents/ takes over.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath
                ])
            ]
        )
    ]
)

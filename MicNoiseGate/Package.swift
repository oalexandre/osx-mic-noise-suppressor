// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MicNoiseGate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MicNoiseGate", targets: ["MicNoiseGate"])
    ],
    targets: [
        .systemLibrary(
            name: "CRNNoise",
            path: "Sources/RNNoise",
            pkgConfig: "rnnoise",
            providers: [
                .brew(["rnnoise"])
            ]
        ),
        .target(
            name: "SharedMemoryBridge",
            path: "Sources/SharedMemoryBridge",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "MicNoiseGate",
            dependencies: ["CRNNoise", "SharedMemoryBridge"],
            path: "Sources",
            exclude: ["RNNoise", "SharedMemoryBridge"],
            linkerSettings: [
                .unsafeFlags(["-L/Users/xaero/.local/lib", "-lrnnoise"])
            ]
        )
    ]
)

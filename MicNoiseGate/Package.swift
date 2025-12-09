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
        .executableTarget(
            name: "MicNoiseGate",
            dependencies: ["CRNNoise"],
            path: "Sources",
            exclude: ["RNNoise"],
            linkerSettings: [
                .unsafeFlags(["-L/Users/xaero/.local/lib", "-lrnnoise"])
            ]
        )
    ]
)

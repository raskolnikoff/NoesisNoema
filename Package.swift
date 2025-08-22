// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NoesisNoema",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .executable(name: "nn", targets: ["LlamaBridgeTest"])
    ],
    targets: [
        .executableTarget(
            name: "LlamaBridgeTest",
            dependencies: [],
            path: "LlamaBridgeTest",
            sources: ["main.swift"]
        ),
        .target(
            name: "NoesisNoemaShared",
            dependencies: [],
            path: "NoesisNoema/Shared",
            sources: [
                "ModelSpec.swift",
                "GGUFReader.swift", 
                "ModelRegistry.swift",
                "ModelManager.swift",
                "LLMModel.swift",
                "EmbeddingModel.swift",
                "Settings.swift"
            ]
        )
    ]
)
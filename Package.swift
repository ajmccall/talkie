// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Talkie",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Parakeet speech-to-text on Core ML (Apache 2.0).
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.7"),
        // LLM inference on Apple silicon (MIT).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        // Hugging Face downloader and tokenizers used by mlx-swift-lm (Apache 2.0).
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Talkie",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/Talkie",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TalkieTests",
            dependencies: ["Talkie"],
            path: "Tests/TalkieTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

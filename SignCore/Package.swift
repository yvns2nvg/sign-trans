// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SignCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SignCore", targets: ["SignCore"]),
        .library(name: "SignInference", targets: ["SignInference"]),
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
    ],
    targets: [
        .target(name: "SignCore", resources: [.copy("Resources")]),
        .target(name: "SignInference",
                dependencies: ["SignCore",
                               .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")],
                resources: [.copy("Resources")]),
        .testTarget(name: "SignCoreTests", dependencies: ["SignCore"]),
        .testTarget(name: "SignInferenceTests", dependencies: ["SignInference", "SignCore"]),
    ]
)

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
        // 폴더째(.copy("Resources")) 넣으면 iOS 코드 서명이 번들을 잘못된 형식으로 본다. 파일 단위로 넣는다.
        .target(name: "SignCore", resources: [.copy("Resources/sentence_tables.json")]),
        .target(name: "SignInference",
                dependencies: ["SignCore",
                               .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")],
                resources: [.copy("Resources/sign_c1200.onnx"), .copy("Resources/labels.json")]),
        .testTarget(name: "SignCoreTests", dependencies: ["SignCore"]),
        .testTarget(name: "SignInferenceTests", dependencies: ["SignInference", "SignCore"]),
    ]
)

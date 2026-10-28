// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SignCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "SignCore", targets: ["SignCore"])],
    targets: [
        .target(name: "SignCore", resources: [.copy("Resources")]),
        .testTarget(name: "SignCoreTests", dependencies: ["SignCore"]),
    ]
)

// swift-tools-version: 5.9
// google-ai-edge/mediapipe v1.1.1 (커밋 50505c8) Package.swift 에서 Vision 에 필요한 부분만 옮긴 로컬 래퍼.
// 원본이 링커 옵션 -all_load 를 .unsafeFlags 로 쓰기 때문에 Xcode 앱이 원격 패키지로 직접 쓸 수 없다.
// 로컬 경로 패키지는 이 제한을 받지 않는다. 바이너리 URL·체크섬은 원본과 같다.
import PackageDescription

let package = Package(
    name: "MediaPipe",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "MediaPipeTasksVision", targets: ["MediaPipeLink", "MediaPipeTasksVision"]),
    ],
    targets: [
        .binaryTarget(
            name: "MediaPipeTasksCommonBinary",
            url: "https://dl.google.com/cpdc/20261013-213039/MediaPipeTasksCommon-1.1.1.xcframework.zip",
            checksum: "25690f3005c0405a7f27b6d273b4db241811d00fbb01c54004057ee1d0e983d8"
        ),
        .binaryTarget(
            name: "MediaPipeTaskGraphsBinary",
            url: "https://dl.google.com/cpdc/20261013-213039/MediaPipeTaskGraphs-1.1.1.xcframework.zip",
            checksum: "e4d88ed65c101764ef90281a411b9942f369e48673d448eff1f934e1f68d9633"
        ),
        .binaryTarget(
            name: "MediaPipeTasksVision",
            url: "https://dl.google.com/cpdc/20261013-213039/MediaPipeTasksVision-1.1.1.xcframework.zip",
            checksum: "755390ce853b062536899f0729321156d4cdceb263aa92c4bf3b2dd05fe640e0"
        ),
        .target(
            name: "MediaPipeLink",
            dependencies: ["MediaPipeTasksCommonBinary", "MediaPipeTaskGraphsBinary", "MediaPipeTasksVision"],
            linkerSettings: [
                // 원본과 같음: C++ 계산기 등록 생성자가 링커에 의해 지워지지 않게 한다.
                .unsafeFlags(["-Xlinker", "-all_load"]),
                .linkedLibrary("c++"),
                .linkedLibrary("sqlite3"),   // MediaPipeTasksCommon 의 벡터 저장소 코드가 -all_load 로 함께 링크됨
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ]
)

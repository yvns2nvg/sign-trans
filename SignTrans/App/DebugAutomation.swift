#if DEBUG
import Foundation
import SignCore
import SignInference

/// 시뮬레이터 두 대로 연결 흐름을 손으로 누르지 않고 확인하기 위한 디버그 전용 실행 인자.
///   -autoName 이름  -autoRole deaf|hearing  -autoInvite  -autoAccept|-autoDecline  -autoEndAfter 초
@MainActor enum DebugAutomation {
    /// -selfTest: 실기기에서 ONNX 모델 실행·추론 시간(PRD D2 4단계, S3)과 문장 표를 점검해 로그로 남긴다.
    static func selfTest() {
        DispatchQueue.global().async {
            do {
                let clf = try SignClassifier.bundled()
                let zeros = [[Float]](repeating: [Float](repeating: 0, count: Featurizer.featureDim), count: 64)
                _ = try clf.logits(zeros)
                let t0 = Date()
                for _ in 0..<100 { _ = try clf.logits(zeros) }
                let ms = Date().timeIntervalSince(t0) * 10
                let s = try SentenceComposer.bundled().compose(["사과", "달다"], style: .polite)
                print("[selftest] labels \(clf.labels.count), ORT \(String(format: "%.2f", ms)) ms/회, 문장 \(s)")
            } catch {
                print("[selftest] FAIL \(error)")
            }
        }
    }

    static func run(_ m: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-selfTest") { selfTest() }
        if args.contains("-soloHearing") {   // 상대 없이 청인 화면 + 카메라 파이프라인
            if args.contains("-front") { (m.hearing as? HearingController)?.pipeline.position = .front }
            if args.contains("-noFace") { (m.hearing as? HearingController)?.pipeline.useFace = false }
            if args.contains("-mirror") { (m.hearing as? HearingController)?.pipeline.camera.mirrorFrames = true }
            print("[auto] solo hearing front=\(args.contains("-front")) face=\(!args.contains("-noFace")) mirror=\(args.contains("-mirror"))")
            m.role = .hearing
            m.showDevInfo = true
            m.connected(to: NearbyPeer(id: "solo", name: "테스트", role: .deaf))
            return
        }
        func value(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        if let n = value("-autoName") { m.myName = n }
        guard let role = value("-autoRole").flatMap(UserRole.init(rawValue:)) else { return }
        m.choose(role: role)
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .milliseconds(500))
                if args.contains("-autoInvite"), m.screen == .discovery, m.pendingRequest == nil, m.partner == nil,
                   let p = m.nearby.first {
                    print("[auto] invite \(p.name)")
                    m.sendRequest(to: p)
                }
                if case .request(let p) = m.screen {
                    if args.contains("-autoDecline") { print("[auto] decline \(p.name)"); m.decline() }
                    if args.contains("-autoAccept") { print("[auto] accept \(p.name)"); m.accept() }
                }
                if m.screen == .conversation, let s = value("-autoEndAfter").flatMap(Double.init) {
                    try? await Task.sleep(for: .seconds(s))
                    print("[auto] end conversation"); m.endConversation(); return
                }
            }
        }
    }
}
#endif

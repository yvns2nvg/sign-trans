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
        // -demoVocab "감기,진단서,급하다" 로 상황 어휘 모드를 켜고(앱을 다시 열어도 유지), -demoVocab off 로 끈다.
        if let v = value("-demoVocab") {
            if v == "off" {
                UserDefaults.standard.removeObject(forKey: "demoVocabulary")
                print("[auto] 상황 어휘 모드 끔")
            } else {
                let words = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                UserDefaults.standard.set(words, forKey: "demoVocabulary")
                print("[auto] 상황 어휘 모드 켬: \(words)")
            }
        }
        // -demoAlias "최소=원하다" 로 상황 어휘 모드의 대체 단어를 정하고(유지됨), -demoAlias off 로 끈다.
        if let v = value("-demoAlias") {
            if v == "off" {
                UserDefaults.standard.removeObject(forKey: "demoAliases")
                print("[auto] 대체 단어 끔")
            } else {
                var map: [String: String] = [:]
                for pair in v.split(separator: ",") {
                    let kv = pair.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                    if kv.count == 2, !kv[0].isEmpty, !kv[1].isEmpty { map[kv[0]] = kv[1] }
                }
                UserDefaults.standard.set(map, forKey: "demoAliases")
                print("[auto] 대체 단어: \(map)")
            }
        }
        if args.contains("-soloHearing") {   // 상대 없이 청인 화면 + 카메라 파이프라인
            if args.contains("-front") { (m.hearing as? HearingController)?.pipeline.position = .front }
            if args.contains("-noFace") { (m.hearing as? HearingController)?.pipeline.useFace = false }
            if args.contains("-mirror") { (m.hearing as? HearingController)?.pipeline.camera.mirrorFrames = true }
            print("[auto] solo hearing front=\(args.contains("-front")) face=\(!args.contains("-noFace")) mirror=\(args.contains("-mirror"))")
            m.role = .hearing
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

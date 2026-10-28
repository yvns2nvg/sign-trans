#if DEBUG
import Foundation
import SignCore

/// 시뮬레이터 두 대로 연결 흐름을 손으로 누르지 않고 확인하기 위한 디버그 전용 실행 인자.
///   -autoName 이름  -autoRole deaf|hearing  -autoInvite  -autoAccept|-autoDecline  -autoEndAfter 초
@MainActor enum DebugAutomation {
    static func run(_ m: AppModel) {
        let args = ProcessInfo.processInfo.arguments
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

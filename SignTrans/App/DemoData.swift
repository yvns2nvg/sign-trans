import Foundation
import SignCore

/// -demoScreen 인자로 화면을 가짜 데이터로 띄운다 (목업 비교 스크린샷용).
@MainActor enum DemoData {
    static func apply(_ name: String, to m: AppModel) {
        let minsu = NearbyPeer(id: "d1", name: "민수", role: .hearing)
        let jimin = NearbyPeer(id: "d2", name: "지민", role: .deaf)
        switch name {
        case "discovery":
            m.role = .hearing; m.myName = "민수"; m.nearby = [jimin]; m.screen = .discovery
        case "request":
            m.role = .deaf; m.screen = .request(minsu)
        case "deaf":
            m.role = .deaf; m.partner = minsu; m.screen = .conversation
            let base = Calendar.current.date(bySettingHour: 14, minute: 16, second: 0, of: Date())!
            m.captions = [CaptionLine(text: "안녕하세요.\n무엇을 도와드릴까요?", time: base)]
            m.liveCaption = "도서관은 이 건물 2층에 있어요."
        case "hearing":
            m.role = .hearing; m.partner = jimin; m.screen = .conversation
            m.translation = "도서관에 가고 싶어요."
        default:
            break
        }
    }
}

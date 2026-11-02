import Testing
import Foundation
import SignCore
@testable import SignTrans

final class FakeTransport: PeerTransport {
    var log: [String] = []
    var sent: [PeerMessage] = []
    func start(name: String, role: UserRole) { log.append("start \(name) \(role.rawValue)") }
    func stop() { log.append("stop") }
    func invite(peerID: String) { log.append("invite \(peerID)") }
    func cancelInvite() { log.append("cancel") }
    func respond(accept: Bool) { log.append("respond \(accept)") }
    func send(_ m: PeerMessage) { sent.append(m) }
    func disconnect() { log.append("disconnect") }
}

final class FakeHearing: HearingControlling {
    var log: [String] = []
    func start() { log.append("start") }
    func stop() { log.append("stop") }
    func setMic(_ on: Bool) { log.append("mic \(on)") }
}

@MainActor struct AppModelTests {
    let jimin = NearbyPeer(id: "p1", name: "지민", role: .deaf)

    func model(_ role: UserRole) -> (AppModel, FakeTransport) {
        let m = AppModel(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let t = FakeTransport()
        m.transport = t
        m.choose(role: role)
        return (m, t)
    }

    @Test func choosingRoleStartsDiscovery() {
        let (m, t) = model(.hearing)
        #expect(m.screen == .discovery)
        #expect(t.log.first?.hasPrefix("start ") == true)
    }

    @Test func sameRolePeersAreHidden() {
        let (m, _) = model(.hearing)
        m.peerFound(NearbyPeer(id: "x", name: "다른청인", role: .hearing))
        m.peerFound(jimin)
        #expect(m.nearby == [jimin])
    }

    @Test func requestAcceptedOpensConversation() {
        let (m, t) = model(.hearing)
        m.peerFound(jimin)
        m.sendRequest(to: jimin)
        #expect(m.pendingRequest == jimin && t.log.contains("invite p1"))
        m.connected(to: jimin)
        #expect(m.screen == .conversation && m.partner == jimin && m.link == .connected)
    }

    @Test func declinedRequestShowsToast() {
        let (m, _) = model(.hearing)
        m.peerFound(jimin); m.sendRequest(to: jimin)
        m.requestFailed(peerID: "p1")
        #expect(m.screen == .discovery && m.pendingRequest == nil)
        #expect(m.toast == "지민님이 요청을 거절했어요")
    }

    @Test func incomingRequestAcceptAndDecline() {
        let (m, t) = model(.deaf)
        let minsu = NearbyPeer(id: "p2", name: "민수", role: .hearing)
        m.requestReceived(from: minsu)
        #expect(m.screen == .request(minsu))
        m.decline()
        #expect(m.screen == .discovery && t.log.contains("respond false"))
        m.requestReceived(from: minsu); m.accept()
        #expect(t.log.contains("respond true"))
    }

    @Test func captionsAccumulate() {
        let (m, _) = model(.deaf)
        m.connected(to: NearbyPeer(id: "p2", name: "민수", role: .hearing))
        m.received(PeerMessage(kind: .captionPartial, seq: 1, text: "도서관은"))
        #expect(m.liveCaption == "도서관은" && m.captions.isEmpty)
        m.received(PeerMessage(kind: .captionFinal, seq: 2, text: "도서관은 이 건물 2층에 있어요."))
        #expect(m.liveCaption.isEmpty && m.captions.map(\.text) == ["도서관은 이 건물 2층에 있어요."])
    }

    @Test func peerLostDuringConversationShowsDisconnected() {
        let (m, _) = model(.deaf)
        let minsu = NearbyPeer(id: "p2", name: "민수", role: .hearing)
        m.connected(to: minsu)
        m.disconnected(from: "p2")
        #expect(m.screen == .conversation && m.link == .lost)
    }

    @Test func endConversationSendsByeAndReturnsToDiscovery() {
        let (m, t) = model(.hearing)
        m.connected(to: jimin)
        m.endConversation()
        #expect(t.sent.last?.kind == .bye && t.log.contains("disconnect"))
        #expect(m.screen == .discovery && m.partner == nil && m.captions.isEmpty)
    }

    @Test func partnerByeShowsToast() {
        let (m, _) = model(.hearing)
        m.connected(to: jimin)
        m.received(PeerMessage(kind: .bye, seq: 9))
        #expect(m.screen == .discovery && m.toast == "지민님이 대화를 끝냈어요")
    }

    /// 청인은 마이크 버튼을 누르고 있는 동안에만 말이 자막으로 간다.
    @Test func micIsOnOnlyWhileHeld() {
        let (m, _) = model(.hearing)
        let h = FakeHearing()
        m.hearing = h
        m.connected(to: jimin)
        #expect(m.micOn == false)
        m.setMic(true)
        #expect(m.micOn == true)
        m.setMic(false)
        #expect(m.micOn == false)
        m.setMic(true)
        m.endConversation()
        #expect(m.micOn == false)
        #expect(h.log.filter { $0.hasPrefix("mic") } == ["mic true", "mic false", "mic true", "mic false"])
    }

    /// 시연 모드 표시: 확정 단어가 맨 앞, 20% 미만이면 20~25%, 다른 후보는 그보다 낮게.
    @Test func demoDisplayLiftsLowAcceptedWord() {
        let shown = HearingPipeline.demoDisplay(
            accepted: GlossScore(gloss: "진단서", probability: 0.08),
            candidates: [GlossScore(gloss: "이력서", probability: 0.08), GlossScore(gloss: "진단서", probability: 0.08),
                         GlossScore(gloss: "경고", probability: 0.04)])
        #expect(shown.map(\.gloss) == ["진단서", "이력서", "경고"])
        #expect((0.20...0.25).contains(shown[0].probability))
        #expect(shown[1].probability < shown[0].probability && shown[2].probability < shown[0].probability)
        let high = HearingPipeline.demoDisplay(accepted: GlossScore(gloss: "원하다", probability: 0.46),
                                               candidates: [GlossScore(gloss: "원하다", probability: 0.46)])
        #expect(high == [GlossScore(gloss: "원하다", probability: 0.46)])   // 20% 이상이면 그대로
    }
}

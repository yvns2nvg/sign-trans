import Foundation
import SignCore

struct NearbyPeer: Identifiable, Hashable { let id: String; let name: String; let role: UserRole }
struct CaptionLine: Identifiable, Equatable { let id = UUID(); let text: String; let time: Date }
enum Screen: Equatable { case start, discovery, request(NearbyPeer), conversation }
enum LinkState: Equatable { case connected, reconnecting, lost }

protocol PeerTransport: AnyObject {
    func start(name: String, role: UserRole)
    func stop()
    func invite(peerID: String)
    func cancelInvite()
    func respond(accept: Bool)
    func send(_ m: PeerMessage)
    func disconnect()
}

protocol HearingControlling: AnyObject {
    func start()
    func stop()
}

/// 화면 흐름과 대화 상태. 서비스는 이벤트 메서드로만 상태를 바꾼다.
@MainActor final class AppModel: ObservableObject {
    @Published var screen: Screen = .start
    @Published var role: UserRole?
    @Published var myName: String { didSet { defaults.set(myName, forKey: "myName") } }
    @Published var nearby: [NearbyPeer] = []
    @Published var pendingRequest: NearbyPeer?
    @Published var partner: NearbyPeer?
    @Published var link: LinkState = .connected
    @Published var captions: [CaptionLine] = []
    @Published var liveCaption = ""
    @Published var translation = ""
    @Published var translationWords: [String] = []
    @Published var hint: String?
    @Published var toast: String?
    @Published var peerStatus: PeerStatus?
    @Published var devInfo = ""
    @Published var showDevInfo = false

    var transport: PeerTransport?
    var hearing: HearingControlling?
    private let defaults: UserDefaults
    private var seq = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        myName = defaults.string(forKey: "myName") ?? "사용자\(Int.random(in: 100...999))"
    }

    // MARK: 사용자 동작
    func choose(role: UserRole) {
        self.role = role
        screen = .discovery
        nearby = []
        transport?.start(name: myName, role: role)
    }

    func sendRequest(to peer: NearbyPeer) {
        pendingRequest = peer
        transport?.invite(peerID: peer.id)
    }

    func cancelRequest() {
        transport?.cancelInvite()
        pendingRequest = nil
    }

    func accept() { transport?.respond(accept: true) }

    func decline() {
        transport?.respond(accept: false)
        screen = .discovery
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let role else { return }
        myName = trimmed
        transport?.stop()
        transport?.start(name: myName, role: role)
    }

    func endConversation() {
        send(.bye)
        hearing?.stop()
        transport?.disconnect()
        resetConversation()
        screen = .discovery
    }

    func searchAgain() {
        hearing?.stop()
        transport?.disconnect()
        resetConversation()
        screen = .discovery
        if let role { transport?.stop(); transport?.start(name: myName, role: role) }
    }

    func backToStart() {
        transport?.stop()
        resetConversation()
        nearby = []
        role = nil
        screen = .start
    }

    // MARK: 서비스 이벤트
    func peerFound(_ peer: NearbyPeer) {
        guard let role, peer.role == role.opposite else { return }
        nearby.removeAll { $0.id == peer.id }
        nearby.append(peer)
    }

    func peerLost(id: String) { nearby.removeAll { $0.id == id } }

    func requestReceived(from peer: NearbyPeer) {
        guard screen == .discovery else { transport?.respond(accept: false); return }
        screen = .request(peer)
    }

    func requestFailed(peerID: String) {
        guard let p = pendingRequest, p.id == peerID else { return }
        pendingRequest = nil
        toast = "\(p.name)님이 요청을 거절했어요"
    }

    func requestCancelledByPeer() {
        if case .request = screen {
            screen = .discovery
            toast = "요청이 취소됐어요"
        }
    }

    func connected(to peer: NearbyPeer) {
        pendingRequest = nil
        partner = peer
        link = .connected
        screen = .conversation
        if role == .hearing { hearing?.start() }
    }

    func disconnected(from peerID: String) {
        guard partner?.id == peerID, screen == .conversation else { return }
        hearing?.stop()
        link = .lost
    }

    func received(_ m: PeerMessage) {
        switch m.kind {
        case .captionPartial: liveCaption = m.text ?? ""
        case .captionFinal:
            if let t = m.text, !t.isEmpty { captions.append(CaptionLine(text: t, time: m.sentAt)) }
            liveCaption = ""
        case .translationFinal: translation = m.text ?? ""
        case .status: peerStatus = m.status
        case .hello: break
        case .bye:
            let name = partner?.name ?? "상대방"
            hearing?.stop()
            transport?.disconnect()
            resetConversation()
            screen = .discovery
            toast = "\(name)님이 대화를 끝냈어요"
        }
    }

    // MARK: 청인 쪽 출력 (HearingPipeline/SpeechService 가 호출)
    func send(_ kind: PeerMessage.Kind, text: String? = nil, status: PeerStatus? = nil) {
        seq += 1
        transport?.send(PeerMessage(kind: kind, seq: seq, text: text, status: status))
    }

    private func resetConversation() {
        partner = nil
        pendingRequest = nil
        captions = []
        liveCaption = ""
        translation = ""
        translationWords = []
        hint = nil
        peerStatus = nil
        link = .connected
    }
}

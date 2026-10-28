import Foundation
import MultipeerConnectivity
import SignCore

/// MultipeerConnectivity 로 주변 기기 찾기 → 초대 → 수락 → 텍스트 메시지 주고받기.
/// 블루투스와 기기 간 와이파이를 시스템이 알아서 고른다.
final class PeerService: NSObject, PeerTransport {
    static let serviceType = "sign-trans"
    private weak var model: AppModel?
    private var me: MCPeerID?
    private var intro: PeerIntro?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peers: [String: (MCPeerID, NearbyPeer)] = [:]
    private var pendingInvitation: ((Bool, MCSession?) -> Void)?
    private var invitingPeer: MCPeerID?
    private var connectedPeer: NearbyPeer?

    init(model: AppModel) { self.model = model }

    func start(name: String, role: UserRole) {
        stop()
        let id = MCPeerID(displayName: name)
        me = id
        intro = PeerIntro(name: name, role: role)
        let s = MCSession(peer: id, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        let adv = MCNearbyServiceAdvertiser(peer: id, discoveryInfo: ["name": name, "role": role.rawValue],
                                            serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        let br = MCNearbyServiceBrowser(peer: id, serviceType: Self.serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil; browser = nil; session = nil
        peers = [:]; invitingPeer = nil; pendingInvitation = nil; connectedPeer = nil
    }

    func invite(peerID: String) {
        guard let (mc, _) = peers[peerID], let session, let intro,
              let ctx = try? JSONEncoder().encode(intro) else { return }
        invitingPeer = mc
        browser?.invitePeer(mc, to: session, withContext: ctx, timeout: 30)
    }

    /// MC 에는 초대 취소가 없어 세션을 새로 만든다.
    func cancelInvite() {
        invitingPeer = nil
        resetSession()
    }

    func respond(accept: Bool) {
        pendingInvitation?(accept, accept ? session : nil)
        pendingInvitation = nil
    }

    func send(_ m: PeerMessage) {
        guard let session, !session.connectedPeers.isEmpty, let data = try? m.encoded() else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    func disconnect() {
        connectedPeer = nil
        resetSession(flushDelay: 0.5)
    }

    /// 새 세션으로 갈아끼운다. flushDelay 가 있으면 옛 세션은 그만큼 뒤에 끊어,
    /// 직전에 보낸 메시지(예: bye)가 상대에게 도착할 시간을 준다.
    private func resetSession(flushDelay: TimeInterval = 0) {
        if let old = session {
            if flushDelay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + flushDelay) { old.disconnect() }
            } else {
                old.disconnect()
            }
        }
        guard let me else { return }
        let s = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
    }

    private func key(_ p: MCPeerID) -> String { "\(p.displayName)#\(p.hash)" }

    private func onMain(_ f: @escaping @MainActor (AppModel) -> Void) {
        Task { @MainActor [weak model] in if let model { f(model) } }
    }
}

extension PeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let info, let name = info["name"], let role = info["role"].flatMap(UserRole.init(rawValue:)) else { return }
        let peer = NearbyPeer(id: key(peerID), name: name, role: role)
        peers[peer.id] = (peerID, peer)
        onMain { $0.peerFound(peer) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let id = key(peerID)
        peers[id] = nil
        onMain { $0.peerLost(id: id) }
    }
}

extension PeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard let context, let intro = try? JSONDecoder().decode(PeerIntro.self, from: context) else {
            invitationHandler(false, nil); return
        }
        let peer = NearbyPeer(id: key(peerID), name: intro.name, role: intro.role)
        peers[peer.id] = (peerID, peer)
        pendingInvitation = invitationHandler
        onMain { $0.requestReceived(from: peer) }
    }
}

extension PeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard session === self.session else { return }
        let id = key(peerID)
        let peer = peers[id]?.1 ?? NearbyPeer(id: id, name: peerID.displayName, role: .deaf)
        switch state {
        case .connected:
            invitingPeer = nil
            connectedPeer = peer
            onMain { $0.connected(to: peer) }
        case .notConnected:
            if invitingPeer == peerID {
                invitingPeer = nil
                onMain { $0.requestFailed(peerID: id) }
            } else if connectedPeer?.id == id {
                connectedPeer = nil
                onMain { $0.disconnected(from: id) }
            } else {
                onMain { $0.requestCancelledByPeer() }
            }
        case .connecting: break
        @unknown default: break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let m = try? PeerMessage.decode(data) else { return }
        onMain { $0.received(m) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

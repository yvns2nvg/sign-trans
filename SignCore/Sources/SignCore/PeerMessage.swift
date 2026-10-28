import Foundation

public enum UserRole: String, Codable, Sendable {
    case deaf, hearing
    public var label: String { self == .deaf ? "농인" : "청인" }
    public var opposite: UserRole { self == .deaf ? .hearing : .deaf }
}

public enum PeerStatus: String, Codable, Sendable {
    case listening       // 음성을 듣고 있음
    case speechStopped   // 음성 인식이 멈춤(지원 안 됨, 오류)
    case micOff          // 마이크 권한 없음
    case cameraOff       // 카메라 권한 없음
}

/// 연결 요청에 실어 보내는 내 정보.
public struct PeerIntro: Codable, Equatable, Sendable {
    public let name: String
    public let role: UserRole
    public init(name: String, role: UserRole) { self.name = name; self.role = role }
}

/// 두 폰 사이 메시지 (PRD F2-6). JSON 텍스트.
public struct PeerMessage: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hello
        case captionPartial = "caption.partial"
        case captionFinal = "caption.final"
        case translationFinal = "translation.final"
        case status
        case bye
    }

    public static let currentVersion = 1
    public var v: Int
    public var kind: Kind
    public var seq: Int
    public var text: String?
    public var status: PeerStatus?
    public var sentAt: Date

    public init(kind: Kind, seq: Int, text: String? = nil, status: PeerStatus? = nil,
                sentAt: Date = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())) {
        self.v = Self.currentVersion; self.kind = kind; self.seq = seq
        self.text = text; self.status = status; self.sentAt = sentAt
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> PeerMessage { try JSONDecoder().decode(Self.self, from: data) }
}

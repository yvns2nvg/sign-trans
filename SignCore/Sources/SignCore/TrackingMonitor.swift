public enum TrackingGuidance: Equatable, Sendable {
    case ok
    case calibrating      // 어깨너비 보정 전
    case showUpperBody    // 2초 이상 어깨 미검출
    case showHands        // 3초 이상 양손 미검출
}

/// 촬영 안내 판정 (PRD 화면 5 오류 상태). 원시 frame89(스무딩 전)를 넣는다.
public struct TrackingMonitor: Sendable {
    public var bodyMissingAfter = 2.0
    public var handsMissingAfter = 3.0
    private var bodyMissing = 0.0
    private var handsMissing = 0.0

    public init() {}

    public mutating func update(frame: Frame, calibrated: Bool, dt: Double) -> TrackingGuidance {
        let hasBody = Featurizer.shoulderScale(frame) >= Featurizer.degenerateScalePx
        let hasHands = Layout.leftHand.contains { frame[$0] != .zero }
            || Layout.rightHand.contains { frame[$0] != .zero }
        bodyMissing = hasBody ? 0 : bodyMissing + dt
        handsMissing = hasHands ? 0 : handsMissing + dt
        if !calibrated { return .calibrating }
        if bodyMissing >= bodyMissingAfter - 1e-9 { return .showUpperBody }
        if handsMissing >= handsMissingAfter - 1e-9 { return .showHands }
        return .ok
    }
}

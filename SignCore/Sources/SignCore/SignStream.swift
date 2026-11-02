/// 프레임 하나의 처리 결과.
public struct StreamStep: Sendable {
    public let smoothed: Frame
    public let normalized: Frame?
    public let energy: Double
    public let label: SegmentGate.Label
    /// 길이 minSegmentFrames 이상으로 끝난 단어 구간(스무딩된 원시 좌표). 없으면 nil.
    public let segment: [Frame]?
    /// 이 프레임 처리 후 게이트가 대기 상태인가 (Python realtime.py 의 gate.state == "idle").
    public let isIdle: Bool
}

/// kslx/realtime.py auto 모드의 프레임 루프:
/// 스무딩 → 실시간 정규화 → 손 에너지 → 구간 게이트.
public final class SignStream {
    public static let minSegmentFrames = 4
    public let smoother: OneEuroFilter?
    public let normalizer = LiveNormalizer()
    public let gate: SegmentGate
    private var prevNorm: Frame?
    /// true 면 손 인식이 끊겼다 돌아온 직후(연속 handStableFrames 미만)의 손은 이동량에서 뺀다.
    /// 끊긴 프레임은 손 좌표가 0 이라 손이 순간이동한 것처럼 계산된다. 기본값은 Python 과 같은 동작.
    public var ignoreHandDropouts = false
    public static let handStableFrames = 3
    private var handRun = (left: 0, right: 0)

    public init(smoothing: Bool = true, gate: SegmentGate = SegmentGate()) {
        self.smoother = smoothing ? OneEuroFilter() : nil
        self.gate = gate
    }

    public func push(_ frame: Frame, dt: Double) -> StreamStep {
        let sm = smoother.map { $0(frame, dt: dt) } ?? frame
        let n = normalizer.normalize(sm)
        var energy = 0.0
        let seen = (left: Layout.leftHand.contains { frame[$0] != .zero },
                    right: Layout.rightHand.contains { frame[$0] != .zero })
        handRun = (seen.left ? handRun.left + 1 : 0, seen.right ? handRun.right + 1 : 0)
        if let p = prevNorm, let n {
            energy = ignoreHandDropouts
                ? handEnergy(prev: p, curr: n, left: handRun.left >= Self.handStableFrames,
                             right: handRun.right >= Self.handStableFrames)
                : handEnergy(prev: p, curr: n)
        }
        if let n { prevNorm = n }
        let (label, buf) = gate.step(sm, energy: energy)
        let segment = (label == .finished && (buf?.count ?? 0) >= Self.minSegmentFrames) ? buf : nil
        return StreamStep(smoothed: sm, normalized: n, energy: energy, label: label,
                          segment: segment, isIdle: !gate.isRecording)
    }

    /// 전체 초기화(R 키와 같음). 어깨너비 보정값은 유지한다.
    public func reset() {
        gate.reset()
        smoother?.reset()
        prevNorm = nil
        handRun = (0, 0)
    }
}

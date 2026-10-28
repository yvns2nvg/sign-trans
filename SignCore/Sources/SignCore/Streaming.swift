/// kslx/stream.py 이식.

/// 적응형 저역통과 필터 (Casiez et al. 2012). 좌표 성분마다 따로 적용한다.
public final class OneEuroFilter {
    public let minCutoff: Double, beta: Double, dCutoff: Double
    private var xPrev: Frame?
    private var dxPrev: Frame?

    public init(minCutoff: Double = 1.2, beta: Double = 0.3, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff; self.beta = beta; self.dCutoff = dCutoff
    }

    static func alpha(_ dt: Double, _ cutoff: Double) -> Double {
        let r = 2 * Double.pi * cutoff * dt
        return r / (r + 1)
    }

    public func callAsFunction(_ x: Frame, dt: Double) -> Frame {
        guard let xp = xPrev, let dxp = dxPrev else {
            xPrev = x
            dxPrev = Array(repeating: .zero, count: x.count)
            return x
        }
        let dt = max(dt, 1e-3)
        let aD = Self.alpha(dt, dCutoff)
        var out = x, dxHat = x
        for i in x.indices {
            let dx = (x[i] - xp[i]) / dt
            let dh = aD * dx + (1 - aD) * dxp[i]
            let a = SIMD2(Self.alpha(dt, minCutoff + beta * abs(dh.x)),
                          Self.alpha(dt, minCutoff + beta * abs(dh.y)))
            out[i] = a * x[i] + (1 - a) * xp[i]
            dxHat[i] = dh
        }
        xPrev = out
        dxPrev = dxHat
        return out
    }

    public func reset() { xPrev = nil; dxPrev = nil }
}

/// 실시간 목 원점 / 어깨너비 정규화. 어깨가 안 잡히면 마지막 정상 스케일을 쓰고,
/// 한 번도 못 잡았으면 nil(그 프레임은 건너뜀).
public final class LiveNormalizer {
    public private(set) var lastScale: Double?
    public var calibrated: Bool { lastScale != nil }
    public init() {}

    public func normalize(_ f: Frame) -> Frame? {
        var scale = Featurizer.shoulderScale(f)
        if scale < Featurizer.degenerateScalePx {
            guard let last = lastScale else { return nil }
            scale = last
        } else {
            lastScale = scale
        }
        let neck = f[Layout.neck]
        return f.map { ($0 - neck) / scale }
    }

    public func reset() { lastScale = nil }
}

/// 두 정규화 프레임 사이 양손 42점 평균 이동량(어깨너비 단위).
public func handEnergy(prev: Frame, curr: Frame) -> Double {
    var sum = 0.0
    for i in Array(Layout.leftHand) + Array(Layout.rightHand) {
        let d = curr[i] - prev[i]
        sum += (d.x * d.x + d.y * d.y).squareRoot()
    }
    return sum / Double(Layout.nHand * 2)
}

/// 에너지 기반 단어 구간 상태 머신: idle → recording → finished → idle.
public final class SegmentGate {
    public enum Label: String, Sendable { case idle, started, recording, finished }

    public let startEnergy: Double, endEnergy: Double
    public let endHold: Int, minFrames: Int, maxFrames: Int
    public private(set) var isRecording = false
    public private(set) var buffer: [Frame] = []
    private var lowRun = 0

    public init(startEnergy: Double = 0.06, endEnergy: Double = 0.03, endHold: Int = 10,
                minFrames: Int = 6, maxFrames: Int = 90) {
        self.startEnergy = startEnergy; self.endEnergy = endEnergy
        self.endHold = endHold; self.minFrames = minFrames; self.maxFrames = maxFrames
    }

    public func step(_ frame: Frame, energy: Double) -> (Label, [Frame]?) {
        if !isRecording {
            guard energy > startEnergy else { return (.idle, nil) }
            isRecording = true
            buffer = [frame]
            lowRun = 0
            return (.started, nil)
        }
        buffer.append(frame)
        lowRun = energy < endEnergy ? lowRun + 1 : 0
        let finished = (lowRun >= endHold && buffer.count >= minFrames) || buffer.count >= maxFrames
        guard finished else { return (.recording, nil) }
        let trim = min(lowRun, max(0, buffer.count - minFrames))
        let out = trim > 0 ? Array(buffer.prefix(buffer.count - trim)) : buffer
        reset()
        return (.finished, out)
    }

    public func reset() { isRecording = false; buffer = []; lowRun = 0 }
}

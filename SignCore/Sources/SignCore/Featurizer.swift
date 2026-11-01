/// kslx/normalize.py 이식: 목 원점 + 어깨너비 스케일, 64프레임 선형 보간, 속도 특징.
public enum Featurizer {
    public static let degenerateScalePx = 5.0
    public static let minScale = 1e-3
    public static let clipLimit = 20.0
    public static let featureDim = Layout.nTotal * 2 * 2   // 356

    public static func shoulderScale(_ f: Frame) -> Double {
        let v = f[Layout.rShoulder] - f[Layout.lShoulder]
        return (v.x * v.x + v.y * v.y).squareRoot()
    }

    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// 어깨가 둘 다 미검출인 프레임은 클립 안 정상 프레임의 중앙값 스케일을 쓴다.
    public static func centerAndScale(_ seq: [Frame]) -> [Frame] {
        let scales = seq.map(shoulderScale)
        let valid = scales.filter { $0 >= degenerateScalePx }
        let fallback = valid.isEmpty ? minScale : median(valid)
        return zip(seq, scales).map { f, s in
            let scale = max(s >= degenerateScalePx ? s : fallback, minScale)
            let neck = f[Layout.neck]
            return f.map { ($0 - neck) / scale }
        }
    }

    /// np.interp 와 같은 선형 보간. 입력이 1프레임이면 반복한다.
    public static func resampleTime(_ seq: [Frame], tOut: Int) -> [Frame] {
        let tIn = seq.count
        if tIn == tOut { return seq }
        if tIn == 1 { return Array(repeating: seq[0], count: tOut) }
        let step = 1.0 / Double(tIn - 1)
        return (0..<tOut).map { k in
            let x = tOut == 1 ? 0.0 : Double(k) / Double(tOut - 1)
            let j = min(Int((x / step).rounded(.down)), tIn - 2)
            let w = (x - Double(j) * step) / step
            return zip(seq[j], seq[j + 1]).map { a, b in a + (b - a) * w }
        }
    }

    /// (T, 89) 원시 픽셀 좌표 → (tOut, 356) 모델 입력. 356 = 위치 178 + 속도 178.
    public static func featurize(_ seq: [Frame], tOut: Int = 64) -> [[Float]] {
        precondition(!seq.isEmpty, "빈 구간")
        let lo = SIMD2<Double>(repeating: -clipLimit), hi = SIMD2<Double>(repeating: clipLimit)
        let norm = centerAndScale(seq).map { $0.map { $0.clamped(lowerBound: lo, upperBound: hi) } }
        let r = resampleTime(norm, tOut: tOut)
        return (0..<tOut).map { t in
            var row = [Float]()
            row.reserveCapacity(featureDim)
            for p in r[t] { row.append(Float(p.x)); row.append(Float(p.y)) }
            for i in r[t].indices {
                let v = t == 0 ? SIMD2<Double>.zero : r[t][i] - r[t - 1][i]
                row.append(Float(v.x)); row.append(Float(v.y))
            }
            return row
        }
    }
}

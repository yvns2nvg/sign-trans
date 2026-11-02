import Testing
@testable import SignCore

struct StreamFixture: Decodable {
    struct Segment: Decodable { let end_frame: Int; let length: Int; let features: [[Double]] }
    let dt: Double
    let frames: [[[Double]]]
    let smoothed: [[[Double]]]
    let norm: [[[Double]]?]
    let energy: [Double]
    let label: [String]
    let segments: [Segment]
}

@Test func streamMatchesPython() throws {
    let fx = try Fixtures.load("stream.json", as: StreamFixture.self)
    let stream = SignStream()
    var segments: [(end: Int, frames: [Frame])] = []
    for t in fx.frames.indices {
        let step = stream.push(Fixtures.frame(fx.frames[t]), dt: fx.dt)
        #expect(Fixtures.maxAbsDiff(step.smoothed, Fixtures.frame(fx.smoothed[t])) < 1e-3, "smoothed t=\(t)")
        if let exp = fx.norm[t] {
            let got = try #require(step.normalized, "norm nil t=\(t)")
            #expect(Fixtures.maxAbsDiff(got, Fixtures.frame(exp)) < 1e-4, "norm t=\(t)")
        } else {
            #expect(step.normalized == nil, "norm should be nil t=\(t)")
        }
        #expect(abs(step.energy - fx.energy[t]) < 1e-5, "energy t=\(t)")
        #expect(step.label.rawValue == fx.label[t], "label t=\(t)")
        if let seg = step.segment { segments.append((t, seg)) }
    }
    #expect(segments.count == fx.segments.count)
    for (got, exp) in zip(segments, fx.segments) {
        #expect(got.end == exp.end_frame && got.frames.count == exp.length)
        let d = Fixtures.maxAbsDiff(Featurizer.featurize(got.frames), exp.features)
        #expect(d < 1e-4, "segment end=\(exp.end_frame) diff \(d)")
    }
}

@Test func normalizerSkipsUntilCalibrated() {
    let n = LiveNormalizer()
    #expect(n.normalize(Array(repeating: .zero, count: 89)) == nil)
    #expect(!n.calibrated)
}

/// 가만히 있는 손이 잠깐 인식에서 빠졌다 돌아올 때(좌표 0 → 실제) 녹화가 시작되면 안 된다 (앱 설정).
@Test func handDropoutDoesNotStartRecording() {
    func still(_ t: Int, rightHand: Bool) -> Frame {
        var f = Frame(repeating: .zero, count: Layout.nTotal)
        f[Layout.neck] = [360, 400]; f[Layout.rShoulder] = [260, 400]; f[Layout.lShoulder] = [460, 400]
        let jitter = Double(t % 2) * 0.5                                    // 0.5px 떨림
        for i in Layout.leftHand { f[i] = [420 + Double(i % 5) * 4 + jitter, 640 + Double(i % 7) * 3] }
        if rightHand { for i in Layout.rightHand { f[i] = [300 + Double(i % 5) * 4 - jitter, 640 + Double(i % 7) * 3] } }
        return f
    }
    // 30프레임 정지 → 오른손 1프레임 빠짐 → 20프레임 → 5프레임 빠짐 → 20프레임
    var seq: [Frame] = (0..<30).map { still($0, rightHand: true) }
    seq.append(still(30, rightHand: false))
    seq += (31..<51).map { still($0, rightHand: true) }
    seq += (51..<56).map { still($0, rightHand: false) }
    seq += (56..<76).map { still($0, rightHand: true) }

    func recordedFrames(_ ignore: Bool) -> Int {
        let s = SignStream()
        s.ignoreHandDropouts = ignore
        return seq.reduce(0) { n, f in n + (s.push(f, dt: 1.0 / 30).isIdle ? 0 : 1) }
    }
    #expect(recordedFrames(false) > 0)      // Python 과 같은 기본 동작: 튐 때문에 녹화 시작
    #expect(recordedFrames(true) == 0)
}

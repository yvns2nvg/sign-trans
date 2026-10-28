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

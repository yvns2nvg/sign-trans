import Foundation
import Testing
@testable import SignCore

/// 항상 같은 결과를 내는 가짜 분류기.
final class FixedClassifier: SignClassifying {
    var scores: [GlossScore]
    var calls = 0
    init(_ scores: [GlossScore]) { self.scores = scores }
    func classify(_ features: [[Float]]) throws -> [GlossScore] {
        #expect(features.count == 64 && features[0].count == Featurizer.featureDim)
        calls += 1
        return scores
    }
}

struct SentenceTimingFixture: Decodable {
    let dt: Double
    let frames: [[[Double]]]
    let sentence_end_frames: [Int]
}

@Test func sentenceTimingMatchesPython() throws {
    let fx = try Fixtures.load("stream.json", as: SentenceTimingFixture.self)
    #expect(!fx.sentence_end_frames.isEmpty)
    let session = TranslationSession(classifier: FixedClassifier([GlossScore(gloss: "사과", probability: 0.9)]),
                                     composer: try .bundled())
    var ends: [Int] = []
    for t in fx.frames.indices {
        let (_, events) = session.process(Fixtures.frame(fx.frames[t]), dt: fx.dt)
        if events.contains(where: { if case .sentence = $0 { true } else { false } }) { ends.append(t) }
    }
    #expect(ends == fx.sentence_end_frames)
}

@Test func rejectedWordsNeverEnterSentence() throws {
    let fx = try Fixtures.load("stream.json", as: SentenceTimingFixture.self)
    let clf = FixedClassifier([GlossScore(gloss: "사과", probability: 0.49)])
    let session = TranslationSession(classifier: clf, composer: try .bundled())
    var rejected = 0, sentences = 0
    for f in fx.frames {
        for e in session.process(Fixtures.frame(f), dt: fx.dt).events {
            if case .wordRejected = e { rejected += 1 }
            if case .sentence = e { sentences += 1 }
        }
    }
    #expect(rejected == clf.calls && rejected > 0)
    #expect(sentences == 0 && session.pendingWords.isEmpty)
}

@Test func finalizeNowComposesPendingWords() throws {
    let session = TranslationSession(classifier: FixedClassifier([]), composer: try .bundled())
    #expect(session.finalizeNow() == nil)
    session.builder.onWord("사과"); session.builder.onWord("달다")
    #expect(session.finalizeNow() == .sentence(words: ["사과", "달다"], text: "사과가 달아요"))
}

@Test func trackingGuidance() {
    var m = TrackingMonitor()
    let zero = Frame(repeating: .zero, count: 89)
    #expect(m.update(frame: zero, calibrated: false, dt: 0.1) == .calibrating)
    for _ in 0..<17 { _ = m.update(frame: zero, calibrated: true, dt: 0.1) }
    #expect(m.update(frame: zero, calibrated: true, dt: 0.1) != .showUpperBody)   // 1.9초
    #expect(m.update(frame: zero, calibrated: true, dt: 0.1) == .showUpperBody)   // 2초
    var body = zero
    body[Layout.rShoulder] = SIMD2(100, 100); body[Layout.lShoulder] = SIMD2(300, 100)
    var m2 = TrackingMonitor()
    for _ in 0..<29 { #expect(m2.update(frame: body, calibrated: true, dt: 0.1) != .showHands) }
    #expect(m2.update(frame: body, calibrated: true, dt: 0.1) == .showHands)        // 3초
    var withHand = body
    withHand[Layout.leftHand.lowerBound] = SIMD2(10, 10)
    #expect(m2.update(frame: withHand, calibrated: true, dt: 0.1) == .ok)
}

@Test func peerMessageRoundTrip() throws {
    let m = PeerMessage(kind: .captionPartial, seq: 3, text: "안녕하세요")
    let back = try PeerMessage.decode(m.encoded())
    #expect(back == m)
    let json = String(decoding: try m.encoded(), as: UTF8.self)
    #expect(json.contains("\"caption.partial\""))
    let intro = PeerIntro(name: "민수", role: .hearing)
    #expect(try JSONDecoder().decode(PeerIntro.self, from: JSONEncoder().encode(intro)) == intro)
    #expect(UserRole.hearing.label == "청인" && UserRole.deaf.opposite == .hearing)
}

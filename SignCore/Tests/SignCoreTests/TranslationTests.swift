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

@Test func shortSegmentsAreNotClassified() throws {
    let fx = try Fixtures.load("stream.json", as: StreamFixture.self)
    let minFrames = 30
    let expected = fx.segments.filter { $0.length >= minFrames }.count
    #expect(expected > 0 && expected < fx.segments.count)          // 기준 데이터에 짧은 구간과 긴 구간이 둘 다 있음
    let clf = FixedClassifier([GlossScore(gloss: "사과", probability: 0.9)])
    let session = TranslationSession(classifier: clf, composer: try .bundled())
    session.minClassifyFrames = minFrames
    var accepted = 0
    for f in fx.frames {
        for e in session.process(Fixtures.frame(f), dt: fx.dt).events {
            if case .wordAccepted = e { accepted += 1 }
        }
    }
    #expect(clf.calls == expected && accepted == expected)
}

/// 상황 어휘 모드: 상위 후보 안에 허용 단어가 있으면 확률과 무관하게 그 단어로 확정한다.
@Test func allowedWordsPickFromTopCandidates() throws {
    let fx = try Fixtures.load("stream.json", as: StreamFixture.self)
    let clf = FixedClassifier([GlossScore(gloss: "단명", probability: 0.69),
                               GlossScore(gloss: "감기", probability: 0.04),
                               GlossScore(gloss: "경북", probability: 0.02)])
    let session = TranslationSession(classifier: clf, composer: try .bundled())
    session.allowedWords = ["감기", "진단서", "급하다"]
    var accepted: [String] = []
    for f in fx.frames {
        for e in session.process(Fixtures.frame(f), dt: fx.dt).events {
            if case .wordAccepted(let g) = e { accepted.append(g.gloss) }
        }
    }
    #expect(clf.calls > 0 && accepted == Array(repeating: "감기", count: clf.calls))
}

@Test func allowedWordsRejectWhenNoneInTopCandidates() throws {
    let fx = try Fixtures.load("stream.json", as: StreamFixture.self)
    let clf = FixedClassifier([GlossScore(gloss: "단명", probability: 0.95)])
    let session = TranslationSession(classifier: clf, composer: try .bundled())
    session.allowedWords = ["감기", "진단서", "급하다"]
    var accepted = 0, rejected = 0
    for f in fx.frames {
        for e in session.process(Fixtures.frame(f), dt: fx.dt).events {
            if case .wordAccepted = e { accepted += 1 }
            if case .wordRejected = e { rejected += 1 }
        }
    }
    #expect(accepted == 0 && rejected == clf.calls)   // 확률 95%여도 허용 단어가 아니면 버림
}

/// 상황 어휘 모드는 상위 allowedWordsTopK(앱 3) 안의 허용 단어만 확정한다.
@Test func allowedWordsIgnoreLowRankedCandidates() throws {
    let fx = try Fixtures.load("stream.json", as: StreamFixture.self)
    let clf = FixedClassifier([GlossScore(gloss: "지팡이", probability: 0.27),
                               GlossScore(gloss: "필기시험", probability: 0.03),
                               GlossScore(gloss: "샛길", probability: 0.02),
                               GlossScore(gloss: "원하다", probability: 0.01)])   // 4위
    let session = TranslationSession(classifier: clf, composer: try .bundled())
    session.allowedWords = ["감기", "진단서", "원하다"]
    session.allowedWordsTopK = 3
    var accepted = 0
    for f in fx.frames {
        for e in session.process(Fixtures.frame(f), dt: fx.dt).events {
            if case .wordAccepted = e { accepted += 1 }
        }
    }
    #expect(clf.calls > 0 && accepted == 0)
}

/// 같은 단어가 연달아 확정되면 문장에는 한 번만 넣는다 (앱 설정).
@Test func consecutiveDuplicateWordsCollapse() throws {
    let b = SentenceBuilder(composer: try SentenceComposer.bundled(), sentenceEndHold: 3)
    b.collapseRepeats = true
    b.onWord("원하다"); b.onWord("원하다")
    #expect(b.words == ["원하다"])
    b.onWord("진단서"); b.onWord("원하다")
    #expect(b.words == ["원하다", "진단서", "원하다"])     // 연달아가 아니면 그대로
    let plain = SentenceBuilder(composer: try SentenceComposer.bundled())
    plain.onWord("원하다"); plain.onWord("원하다")
    #expect(plain.words == ["원하다", "원하다"])          // 기본값은 Python 과 같은 동작
}

/// 시연용 대체 단어: 상황 어휘 모드에서 '최소'가 상위 후보에 있으면 '원하다'로 확정한다.
@Test func wordAliasesMapToAllowedWord() throws {
    let fx = try Fixtures.load("stream.json", as: StreamFixture.self)
    let clf = FixedClassifier([GlossScore(gloss: "최소", probability: 0.46),
                               GlossScore(gloss: "최대", probability: 0.11),
                               GlossScore(gloss: "진단서", probability: 0.04)])
    let session = TranslationSession(classifier: clf, composer: try .bundled())
    session.allowedWords = ["감기", "진단서", "원하다"]
    session.allowedWordsTopK = 3
    session.wordAliases = ["최소": "원하다"]
    var accepted: [GlossScore] = []
    for f in fx.frames {
        for e in session.process(Fixtures.frame(f), dt: fx.dt).events {
            if case .wordAccepted(let g) = e { accepted.append(g) }
        }
    }
    #expect(clf.calls > 0 && accepted.count == clf.calls)
    #expect(accepted.allSatisfy { $0.gloss == "원하다" && $0.probability == 0.46 })   // 순위가 더 높은 대체 단어가 먼저
}

/// 앱은 단어 사이 여유를 더 주려고 문장 끝 대기 프레임을 늘린다.
@Test func sentenceEndHoldCanBeLengthened() throws {
    let b = SentenceBuilder(composer: try SentenceComposer.bundled())
    b.sentenceEndHold = RecognitionDefaults.sentenceEndHoldFrames
    b.onWord("진단서")
    for _ in 0..<45 { #expect(!b.tickIdle()) }          // Python 기본(45)에서는 여기서 끝났을 것
    var ended = false
    for _ in 45..<RecognitionDefaults.sentenceEndHoldFrames { ended = b.tickIdle() }
    #expect(ended)
}

public struct GlossScore: Equatable, Sendable {
    public let gloss: String
    public let probability: Double
    public init(gloss: String, probability: Double) { self.gloss = gloss; self.probability = probability }
}

/// 64×356 특징 → 단어 후보(확률 내림차순).
public protocol SignClassifying: AnyObject {
    func classify(_ features: [[Float]]) throws -> [GlossScore]
}

public enum TranslationEvent: Equatable, Sendable {
    case wordStarted
    case wordAccepted(GlossScore)
    case wordRejected(GlossScore)
    case classificationFailed(String)
    case sentence(words: [String], text: String)
}

/// realtime.py auto 모드 전체 흐름: 구간 → 분류 → 확신도 필터(앱 추가) → SentenceBuilder.
/// 한 스레드(카메라 큐)에서만 쓴다.
public final class TranslationSession {
    public let stream: SignStream
    public let builder: SentenceBuilder
    public let classifier: SignClassifying
    public var threshold: Double
    /// 이보다 짧은 구간은 분류하지 않는다(손 내리기·준비 동작 오인식 방지). 기본값은 Python 과 같은 동작.
    /// 앱은 RecognitionDefaults.minSignFrames 를 쓴다.
    public var minClassifyFrames = SignStream.minSegmentFrames
    public private(set) var lastTopK: [GlossScore] = []

    public var pendingWords: [String] { builder.words }
    public var calibrated: Bool { stream.normalizer.calibrated }

    public init(classifier: SignClassifying, composer: SentenceComposer,
                threshold: Double = RecognitionDefaults.confidenceThreshold,
                style: SentenceStyle = .polite, stream: SignStream = SignStream()) {
        self.classifier = classifier
        self.builder = SentenceBuilder(composer: composer, style: style)
        self.threshold = threshold
        self.stream = stream
    }

    public func process(_ frame: Frame, dt: Double) -> (step: StreamStep, events: [TranslationEvent]) {
        let step = stream.push(frame, dt: dt)
        var events: [TranslationEvent] = []
        if step.label == .started { events.append(.wordStarted) }
        if let seg = step.segment, seg.count >= minClassifyFrames {
            do {
                let top = try classifier.classify(Featurizer.featurize(seg))
                lastTopK = top
                if let best = top.first {
                    if best.probability >= threshold {
                        builder.onWord(best.gloss)
                        events.append(.wordAccepted(best))
                    } else {
                        events.append(.wordRejected(best))
                    }
                }
            } catch {
                events.append(.classificationFailed(String(describing: error)))
            }
        }
        if step.isIdle && builder.tickIdle() {
            let (words, text) = builder.finalize()
            events.append(.sentence(words: words, text: text))
        }
        return (step, events)
    }

    /// 모은 단어로 문장을 바로 완성한다 (realtime.py 의 ENTER).
    public func finalizeNow() -> TranslationEvent? {
        guard !builder.words.isEmpty else { return nil }
        let (words, text) = builder.finalize()
        return .sentence(words: words, text: text)
    }

    public func clearWords() { builder.clear() }
}

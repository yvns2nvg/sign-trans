import Foundation

public enum SentenceStyle: String, Sendable {
    case formal = "합쇼체"   // 사과가 답니다
    case polite = "해요체"   // 사과가 달아요
}

public enum RecognitionDefaults {
    /// 1순위 확률이 이보다 낮은 단어는 버린다 (PRD F4-3, Q9).
    public static let confidenceThreshold = 0.5
}

/// kslx/sentence.py compose_sentence 이식. kiwi 대신 미리 계산한 표를 쓴다.
public struct SentenceComposer: Sendable {
    let t: SentenceTables

    public init(tables: SentenceTables) { self.t = tables }
    public static func bundled() throws -> SentenceComposer { SentenceComposer(tables: try .bundled()) }

    public func compose(_ glosses: [String], style: SentenceStyle) -> String {
        var words = glosses.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var past = words.contains { t.pastCues.contains($0) }
        if words.last == t.pastMarker { words.removeLast(); past = true }
        guard !words.isEmpty else { return "" }

        // 표에 없는 단어는 '기타'로 보고 그대로 쓴다 (Python 은 kiwi 로 분석하지만 앱엔 kiwi 가 없다).
        let infos = words.map { t.words[$0] }
        let key = "\(style.rawValue)|\(past ? "past" : "present")"

        let pred: (idx: Int, kind: String, form: String)
        let last = infos[infos.count - 1]
        if let i = infos.lastIndex(where: { $0?.role == "predicate" }),
           let k = infos[i]?.predKind, let f = infos[i]?.forms?[key] {
            pred = (i, k, f)
        } else if let last, last.role == "noun", words.count > 1,
                  let k = last.hadaKind, let f = last.hadaForms?[key] {
            pred = (words.count - 1, k, f)
        } else if let last, last.role == "noun", let f = last.copula?[key] {
            pred = (words.count - 1, "copula", f)
        } else {
            return words.joined(separator: " ")
        }
        let (predIdx, kind, predForm) = pred

        let nounIdx = (0..<predIdx).filter { infos[$0]?.role == "noun" }
        let chosen = particles(nounIdx.map { words[$0] },
                               classes: nounIdx.map { infos[$0]?.nounClass ?? "thing" }, kind: kind)
        var units: [String] = []
        for i in 0..<predIdx {
            if let k = nounIdx.firstIndex(of: i), let info = infos[i] {
                if let p = chosen[k], let s = info.particles?[p] { units.append(s) }
                else { units.append(info.bare ?? words[i]) }
            } else {
                units.append(infos[i]?.plain ?? words[i])
            }
        }
        units.append(predForm)
        return ([units.joined(separator: " ")] + words[(predIdx + 1)...]).joined(separator: " ")
    }

    /// sentence.py _particles 이식. 반환값은 표의 조사 키("은/JX" 등) 또는 nil(조사 없음).
    func particles(_ nouns: [String], classes cls: [String], kind: String) -> [String?] {
        let nPerson = cls.filter { $0 == "person" }.count
        let hasThing = cls.contains("thing")
        let nonTime = cls.filter { $0 != "time" }.count
        var out: [String?] = []
        var topicDone = false
        for (i, (n, c)) in zip(nouns, cls).enumerated() {
            let nxt: String? = i + 1 < cls.count ? cls[i + 1] : nil
            let first = !cls[..<i].contains { $0 != "time" }
            if c == "time" {
                out.append(t.timeE.contains(n) ? "에/JKB" : nil)
            } else if c == "person" && kind == "trans" && !t.firstPerson.contains(n) && nonTime == 1 {
                out.append("을/JKO")
            } else if c == "person" && !topicDone && first {
                out.append("은/JX"); topicDone = true
            } else if c == "person" {
                out.append(kind == "trans" && !hasThing ? "을/JKO" : "과/JKB")
            } else if nxt == c && (c == "thing" || c == "place") {
                out.append("과/JC")
            } else if c == "place" {
                if kind == "motion" || kind == "exist" { out.append("에/JKB") }
                else if kind == "copula" || (kind == "adj" && !topicDone) { out.append("은/JX"); topicDone = true }
                else { out.append("에서/JKB") }
            } else if c == "vehicle" && kind == "motion" && nPerson > 0 {
                out.append("으로/JKB")
            } else if kind == "trans" {
                out.append("을/JKO")
            } else if kind == "copula" && !topicDone {
                out.append("은/JX"); topicDone = true
            } else {
                out.append("이/JKS")
            }
        }
        return out
    }
}

/// 단어가 하나씩 들어오다가 sentenceEndHold 프레임 동안 쉬면 문장을 완성한다.
public final class SentenceBuilder {
    public let composer: SentenceComposer
    public let sentenceEndHold: Int
    public var style: SentenceStyle
    public private(set) var words: [String] = []
    private var idleFrames = 0

    public init(composer: SentenceComposer, sentenceEndHold: Int = 45, style: SentenceStyle = .polite) {
        self.composer = composer; self.sentenceEndHold = sentenceEndHold; self.style = style
    }

    public func onWord(_ gloss: String) { words.append(gloss); idleFrames = 0 }

    /// idle 프레임마다 호출. true 면 finalize() 할 시점.
    public func tickIdle() -> Bool {
        guard !words.isEmpty else { return false }
        idleFrames += 1
        return idleFrames >= sentenceEndHold
    }

    public func finalize() -> (words: [String], sentence: String) {
        let w = words
        let s = composer.compose(w, style: style)
        clear()
        return (w, s)
    }

    public func clear() { words = []; idleFrames = 0 }
}

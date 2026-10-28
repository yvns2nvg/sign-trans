import Testing
@testable import SignCore

struct SentenceCase: Decodable {
    let set: String; let glosses: [String]; let style: String
    let expected: String; let mirrorMatches: Bool
}

@Test func evalSentencesMatchPython() throws {
    struct File: Decodable { let cases: [SentenceCase] }
    let cases = try Fixtures.load("sentence_cases.json", as: File.self).cases
    let composer = try SentenceComposer.bundled()
    var randomChecked = 0
    for c in cases {
        let style = try #require(SentenceStyle(rawValue: c.style))
        let got = composer.compose(c.glosses, style: style)
        if c.set != "random" {
            #expect(got == c.expected, "\(c.glosses) [\(c.style)]")
        } else if c.mirrorMatches {
            #expect(got == c.expected, "random \(c.glosses) [\(c.style)]")
            randomChecked += 1
        }
    }
    #expect(cases.filter { $0.set != "random" }.count == 130)
    print("random cases checked: \(randomChecked)")
}

@Test func demoSentence() throws {
    let composer = try SentenceComposer.bundled()
    #expect(composer.compose(["사과", "달다"], style: .polite) == "사과가 달아요")
}

@Test func unknownGlossDoesNotCrash() throws {
    let composer = try SentenceComposer.bundled()
    #expect(composer.compose(["없는단어", "모르는말"], style: .polite) == "없는단어 모르는말")
}

@Test func emptyAndMarkerOnly() throws {
    let composer = try SentenceComposer.bundled()
    #expect(composer.compose([], style: .polite) == "")
    #expect(composer.compose(["끝"], style: .polite) == "")
    #expect(composer.compose([" ", ""], style: .formal) == "")
}

@Test func builderFinalizesAfterIdle() throws {
    let b = SentenceBuilder(composer: try SentenceComposer.bundled(), sentenceEndHold: 3)
    #expect(!b.tickIdle())            // 단어가 없으면 완성하지 않음
    b.onWord("사과"); b.onWord("달다")
    #expect(!b.tickIdle()); #expect(!b.tickIdle()); #expect(b.tickIdle())
    let (words, sentence) = b.finalize()
    #expect(words == ["사과", "달다"] && sentence == "사과가 달아요" && b.words.isEmpty)
}

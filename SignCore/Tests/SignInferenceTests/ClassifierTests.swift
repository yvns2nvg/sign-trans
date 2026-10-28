import Foundation
import Testing
@testable import SignInference
import SignCore

struct ModelIO: Decodable {
    struct Case: Decodable { let features: [[Float]]; let logits: [Float]; let top1: Int }
    let cases: [Case]
}

func loadModelIO() throws -> ModelIO {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures/model_io.json")
    return try JSONDecoder().decode(ModelIO.self, from: Data(contentsOf: url))
}

@Test func onnxMatchesPyTorchOnMac() throws {
    let clf = try SignClassifier.bundled()
    #expect(clf.labels.count == 1200)
    let io = try loadModelIO()
    #expect(io.cases.count == 20)
    for c in io.cases {
        let l = try clf.logits(c.features)
        #expect(l.indices.max(by: { l[$0] < l[$1] }) == c.top1)
        #expect(zip(l, c.logits).map { abs($0 - $1) }.max()! < 1e-3)
    }
}

@Test func probabilitiesMergedByGloss() throws {
    let clf = try SignClassifier.bundled()
    let top = try clf.classify(try loadModelIO().cases[0].features)
    #expect(top.count == 5)
    #expect(Set(top.map(\.gloss)).count == top.count)                 // 같은 단어는 한 번만
    #expect(zip(top, top.dropFirst()).allSatisfy { $0.probability >= $1.probability })
    let dup = Dictionary(grouping: clf.labels.indices, by: { clf.labels[$0] }).first { $0.value.count > 1 }!
    let merged = SignClassifier.mergeByGloss(probabilities: clf.labels.indices.map { dup.value.contains($0) ? 0.3 : 0.0 },
                                             labels: clf.labels)
    #expect(merged.first?.gloss == dup.key)
    #expect(abs(merged.first!.probability - 0.3 * Double(dup.value.count)) < 1e-9)
}

@Test func wrongShapeThrows() throws {
    let clf = try SignClassifier.bundled()
    #expect(throws: ClassifierError.self) { try clf.logits([[0]]) }
}

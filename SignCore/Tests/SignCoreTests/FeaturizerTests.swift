import Testing
@testable import SignCore

@Test func featurizeMatchesPython() throws {
    struct Case: Decodable { let name: String; let raw: [[[Double]]]; let expected: [[Double]] }
    struct File: Decodable { let t_out: Int; let cases: [Case] }
    let file = try Fixtures.load("featurize.json", as: File.self)
    #expect(Set(file.cases.map(\.name)).isSuperset(of: ["all_zero", "single_frame", "shoulders_missing"]))
    for c in file.cases {
        let got = Featurizer.featurize(c.raw.map(Fixtures.frame), tOut: file.t_out)
        #expect(got.count == 64 && got[0].count == Featurizer.featureDim, "\(c.name)")
        let d = Fixtures.maxAbsDiff(got, c.expected)
        #expect(d < 1e-4, "\(c.name): max diff \(d)")
    }
}

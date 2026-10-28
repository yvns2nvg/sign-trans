import Testing
@testable import SignCore

struct AdapterCase: Decodable {
    let name: String; let width: Double; let height: Double; let use_face: Bool
    let pose: [[Double]]?; let left_hand: [[Double]]?; let right_hand: [[Double]]?; let face: [[Double]]?
    let expected: [[Double]]
}

@Test func adapterMatchesPython() throws {
    struct File: Decodable { let cases: [AdapterCase] }
    let cases = try Fixtures.load("adapter.json", as: File.self).cases
    #expect(cases.count == 8)
    func pts(_ a: [[Double]]?) -> [LandmarkPoint]? { a?.map { LandmarkPoint(x: $0[0], y: $0[1]) } }
    for c in cases {
        let got = MediaPipeAdapter.frame89(pose: pts(c.pose), leftHand: pts(c.left_hand),
                                           rightHand: pts(c.right_hand), face: pts(c.face),
                                           width: c.width, height: c.height, useFace: c.use_face)
        #expect(got.count == 89)
        // Python 은 float32 로 저장하므로 픽셀 좌표 기준 1e-3 허용
        #expect(Fixtures.maxAbsDiff(got, Fixtures.frame(c.expected)) < 1e-3, "\(c.name)")
    }
}

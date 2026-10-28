import Foundation
@testable import SignCore

/// sign-trans/fixtures 의 Python 기준 데이터를 읽는다.
enum Fixtures {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SignCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // SignCore
        .deletingLastPathComponent()   // sign-trans
        .appendingPathComponent("fixtures")

    static func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: dir.appendingPathComponent(name)))
    }

    static func frame(_ a: [[Double]]) -> Frame { a.map { SIMD2($0[0], $0[1]) } }

    static func maxAbsDiff(_ a: Frame, _ b: Frame) -> Double {
        zip(a, b).map { max(abs($0.x - $1.x), abs($0.y - $1.y)) }.max() ?? 0
    }

    static func maxAbsDiff(_ a: [[Float]], _ b: [[Double]]) -> Double {
        zip(a, b).flatMap { zip($0, $1).map { abs(Double($0) - $1) } }.max() ?? 0
    }
}

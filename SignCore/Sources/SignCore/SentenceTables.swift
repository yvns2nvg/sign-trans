import Foundation

/// tools/make_sentence_tables.py 가 만든 표. kiwi 결과를 단어별로 미리 계산해 둔 것.
public struct SentenceTables: Decodable, Sendable {
    public struct WordEntry: Decodable, Sendable {
        let role: String
        let plain: String
        let bare: String?
        let headTag: String?
        let nounClass: String?
        let particles: [String: String]?
        let copula: [String: String]?
        let hadaKind: String?
        let hadaForms: [String: String]?
        let predKind: String?
        let forms: [String: String]?
    }

    let pastCues: Set<String>
    let pastMarker: String
    let timeE: Set<String>
    let firstPerson: Set<String>
    let words: [String: WordEntry]

    public static func bundled() throws -> SentenceTables {
        guard let url = Bundle.module.url(forResource: "sentence_tables", withExtension: "json",
                                          subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(SentenceTables.self, from: Data(contentsOf: url))
    }
}

import Foundation
import OnnxRuntimeBindings
import SignCore

public enum ClassifierError: Error, Equatable {
    case badInputShape(rows: Int, cols: Int)
    case missingOutput
    case missingResource(String)
}

/// sign_c1200.onnx (입력 features (1,64,356), 출력 logits (1,1200)) 래퍼.
/// ORTSession 은 한 스레드(카메라 큐)에서만 쓴다.
public final class SignClassifier: SignClassifying {
    public static let frames = 64
    public let labels: [String]
    private let env: ORTEnv
    private let session: ORTSession

    public init(modelURL: URL, labelsURL: URL) throws {
        env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(1)
        session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)
        labels = try JSONDecoder().decode([String].self, from: Data(contentsOf: labelsURL))
    }

    public static func bundled() throws -> SignClassifier {
        guard let m = Bundle.module.url(forResource: "sign_c1200", withExtension: "onnx", subdirectory: "Resources")
        else { throw ClassifierError.missingResource("sign_c1200.onnx") }
        guard let l = Bundle.module.url(forResource: "labels", withExtension: "json", subdirectory: "Resources")
        else { throw ClassifierError.missingResource("labels.json") }
        return try SignClassifier(modelURL: m, labelsURL: l)
    }

    public func logits(_ features: [[Float]]) throws -> [Float] {
        guard features.count == Self.frames, features.allSatisfy({ $0.count == Featurizer.featureDim }) else {
            throw ClassifierError.badInputShape(rows: features.count, cols: features.first?.count ?? 0)
        }
        let flat = features.flatMap { $0 }
        let data = flat.withUnsafeBufferPointer {
            NSMutableData(bytes: $0.baseAddress!, length: $0.count * MemoryLayout<Float>.stride)
        }
        let input = try ORTValue(tensorData: data, elementType: .float,
                                 shape: [1, NSNumber(value: Self.frames), NSNumber(value: Featurizer.featureDim)])
        let out = try session.run(withInputs: ["features": input], outputNames: ["logits"], runOptions: nil)
        guard let value = out["logits"] else { throw ClassifierError.missingOutput }
        let bytes = try value.tensorData() as Data
        return bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    public func classify(_ features: [[Float]]) throws -> [GlossScore] {
        let l = try logits(features).map(Double.init)
        let m = l.max() ?? 0
        let e = l.map { Foundation.exp($0 - m) }
        let sum = e.reduce(0, +)
        return Array(Self.mergeByGloss(probabilities: e.map { $0 / sum }, labels: labels).prefix(5))
    }

    /// 같은 한글 단어가 여러 클래스 ID에 있으면(1200개 중 고유 1166개) 확률을 합친다.
    static func mergeByGloss(probabilities: [Double], labels: [String]) -> [GlossScore] {
        var byGloss: [String: Double] = [:]
        for (i, p) in probabilities.enumerated() { byGloss[labels[i], default: 0] += p }
        return byGloss.map { GlossScore(gloss: $0.key, probability: $0.value) }
            .sorted { $0.probability > $1.probability }
    }
}

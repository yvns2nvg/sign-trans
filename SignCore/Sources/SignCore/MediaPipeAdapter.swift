/// MediaPipe 정규화 좌표(0~1) 하나.
public struct LandmarkPoint: Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// MediaPipe Holistic 결과 → 89점 프레임. kslx/adapters/mediapipe_adapter.py 이식.
public enum MediaPipeAdapter {
    static let nose = 0, lShoulder = 11, rShoulder = 12, lElbow = 13, rElbow = 14
    static let lWrist = 15, rWrist = 16, lHip = 23, rHip = 24
    static let lEye = 2, rEye = 5, lEar = 7, rEar = 8

    /// 눈썹5+5, 눈6+6, 입12 (FaceMesh 공식 영역 상수에서 서브샘플링한 근사치)
    public static let faceIndices34 = [
        46, 53, 63, 70, 107, 276, 283, 293, 300, 336,
        7, 144, 154, 158, 161, 246, 249, 373, 381, 385, 388, 466,
        0, 37, 61, 82, 88, 178, 191, 291, 311, 318, 375, 415,
    ]

    public static func frame89(pose: [LandmarkPoint]?, leftHand: [LandmarkPoint]?,
                               rightHand: [LandmarkPoint]?, face: [LandmarkPoint]?,
                               width: Double, height: Double, useFace: Bool = true) -> Frame {
        func xy(_ l: [LandmarkPoint], _ i: Int) -> SIMD2<Double> { SIMD2(l[i].x * width, l[i].y * height) }
        func zeros(_ n: Int) -> Frame { Array(repeating: .zero, count: n) }

        var out: Frame = []
        out.reserveCapacity(Layout.nTotal)
        if let p = pose, !p.isEmpty {
            let rS = xy(p, rShoulder), lS = xy(p, lShoulder)
            out += [xy(p, nose), (rS + lS) / 2, rS, xy(p, rElbow), xy(p, rWrist),
                    lS, xy(p, lElbow), xy(p, lWrist), (xy(p, rHip) + xy(p, lHip)) / 2,
                    xy(p, rEye), xy(p, lEye), xy(p, rEar), xy(p, lEar)]
        } else {
            out += zeros(Layout.nPose)
        }
        for hand in [leftHand, rightHand] {
            if let h = hand, !h.isEmpty { out += (0..<Layout.nHand).map { xy(h, $0) } }
            else { out += zeros(Layout.nHand) }
        }
        if useFace, let f = face, !f.isEmpty { out += faceIndices34.map { xy(f, $0) } }
        else { out += zeros(Layout.nFace) }
        return out
    }
}

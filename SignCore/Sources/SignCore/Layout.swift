/// 89점 프레임: pose13 + 왼손21 + 오른손21 + 얼굴34, 픽셀 좌표.
/// kslx/layout.py 와 같은 순서다.
public typealias Frame = [SIMD2<Double>]

public enum Layout {
    public static let nPose = 13
    public static let nHand = 21
    public static let nFace = 34
    public static let nTotal = 89
    public static let neck = 1
    public static let rShoulder = 2
    public static let lShoulder = 5
    public static let leftHand = 13..<34
    public static let rightHand = 34..<55
    public static let face = 55..<89
}

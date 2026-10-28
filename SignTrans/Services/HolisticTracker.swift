import CoreMedia
import MediaPipeTasksVision
import SignCore

/// MediaPipe Holistic (VIDEO 모드, Python realtime.py 와 같은 옵션) → 89점 프레임.
final class HolisticTracker {
    private let landmarker: HolisticLandmarker

    init() throws {
        guard let path = Bundle.main.path(forResource: "holistic_landmarker", ofType: "task") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let o = HolisticLandmarkerOptions()
        o.baseOptions.modelAssetPath = path
        o.runningMode = .video
        o.minPoseDetectionConfidence = 0.5
        o.minHandLandmarksConfidence = 0.3
        landmarker = try HolisticLandmarker(options: o)
    }

    func frame(from buffer: CMSampleBuffer, timestampMs: Int, useFace: Bool) throws -> Frame {
        let image = try MPImage(sampleBuffer: buffer, orientation: .up)
        let r = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestampMs)
        guard let pb = CMSampleBufferGetImageBuffer(buffer) else { throw CocoaError(.coderInvalidValue) }
        let w = Double(CVPixelBufferGetWidth(pb)), h = Double(CVPixelBufferGetHeight(pb))
        func pts(_ l: [NormalizedLandmark]) -> [LandmarkPoint]? {
            l.isEmpty ? nil : l.map { LandmarkPoint(x: Double($0.x), y: Double($0.y)) }
        }
        return MediaPipeAdapter.frame89(pose: pts(r.poseLandmarks), leftHand: pts(r.leftHandLandmarks),
                                        rightHand: pts(r.rightHandLandmarks), face: pts(r.faceLandmarks),
                                        width: w, height: h, useFace: useFace)
    }
}

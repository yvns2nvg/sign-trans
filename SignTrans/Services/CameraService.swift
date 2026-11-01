import AVFoundation

enum CameraStartResult { case running, denied, unavailable }

/// 카메라 한 대. 프레임은 queue(직렬)에서 onFrame 으로 나간다.
final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "camera.frames")
    var onFrame: (CMSampleBuffer) -> Void = { _ in }
    /// 모델에 들어가는 영상의 좌우 반전 (전면 카메라 실측 보정용)
    var mirrorFrames = false
    private var configured = false

    func start(position: AVCaptureDevice.Position, wantFrames: Bool) async -> CameraStartResult {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return .unavailable }
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            if session.canAddInput(input) { session.addInput(input) }
            if wantFrames {
                let out = AVCaptureVideoDataOutput()
                out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                out.alwaysDiscardsLateVideoFrames = true
                out.setSampleBufferDelegate(self, queue: queue)
                if session.canAddOutput(out) { session.addOutput(out) }
                // 세로 화면 그대로의 버퍼를 받는다 (MediaPipe 에 orientation .up 으로 넘김)
                if let c = out.connection(with: .video) {
                    if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
                    // 모델에는 좌우 반전 없는 영상을 넣는다 (Python 웹캠 데모와 같은 조건)
                    if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = mirrorFrames }
                }
            }
            session.commitConfiguration()
            configured = true
        }
        queue.async { [session] in session.startRunning() }
        return .running
    }

    func stop() { queue.async { [session] in session.stopRunning() } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame(sampleBuffer)
    }
}

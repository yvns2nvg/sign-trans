import AVFoundation
import Foundation
import QuartzCore
import SignCore
import SignInference

/// 청인 폰: 카메라 → MediaPipe → TranslationSession → 화면/상대 폰.
/// tracker·session 은 camera.queue 에서만 쓴다.
final class HearingPipeline {
    let camera = CameraService()
    private weak var model: AppModel?
    private var tracker: HolisticTracker?
    private var session: TranslationSession?
    private var monitor = TrackingMonitor()
    private var lastTs: Double?
    private var frames = 0, fpsWindowStart = CACurrentMediaTime(), fps = 0.0
    private var lastInferMs = 0.0
    private var rejectHintUntil = 0.0
    var useFace = true

    init(model: AppModel) { self.model = model }

    func start() {
        Task {
            let result = await camera.start(position: .back, wantFrames: true)
            guard result == .running else {
                #if DEBUG
                camera.queue.async { [self] in   // 카메라가 없어도 모델이 앱 번들에서 불러와지는지 확인
                    do {
                        _ = try HolisticTracker()
                        let clf = try SignClassifier.bundled()
                        print("[pipeline] models loaded: holistic OK, onnx labels \(clf.labels.count)")
                    } catch { print("[pipeline] load error \(error)") }
                }
                #endif
                await MainActor.run {
                    model?.hint = result == .denied ? "수어를 번역하려면 카메라 권한이 필요해요" : "카메라를 쓸 수 없어요"
                    model?.send(.status, status: .cameraOff)
                }
                return
            }
            camera.queue.async { [self] in
                do {
                    if tracker == nil { tracker = try HolisticTracker() }
                    if session == nil {
                        session = TranslationSession(classifier: try SignClassifier.bundled(), composer: try .bundled())
                    }
                } catch {
                    print("[pipeline] load error \(error)")
                    DispatchQueue.main.async { self.model?.hint = "인식 모델을 불러오지 못했어요" }
                }
            }
            camera.onFrame = { [weak self] buf in self?.handle(buf) }
        }
    }

    func stop() {
        camera.stop()
        camera.queue.async { [self] in session?.clearWords(); lastTs = nil }
    }

    /// camera.queue 에서 호출된다.
    private func handle(_ buf: CMSampleBuffer) {
        guard let tracker, let session else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(buf).seconds
        let dt = lastTs.map { t - $0 } ?? (1.0 / 30)
        lastTs = t
        guard let frame = try? tracker.frame(from: buf, timestampMs: Int(t * 1000), useFace: useFace) else { return }
        let t0 = CACurrentMediaTime()
        let (step, events) = session.process(frame, dt: dt)
        if step.segment != nil { lastInferMs = (CACurrentMediaTime() - t0) * 1000 }
        let guidance = monitor.update(frame: frame, calibrated: session.calibrated, dt: dt)
        frames += 1
        if t0 - fpsWindowStart >= 1 { fps = Double(frames) / (t0 - fpsWindowStart); frames = 0; fpsWindowStart = t0 }
        var sentence: String?
        for e in events {
            switch e {
            case .wordRejected: rejectHintUntil = t0 + 1.5
            case .sentence(_, let text): sentence = text
            default: break
            }
        }
        let hint: String? = switch guidance {
        case .calibrating: "상반신과 양 어깨가 보이게 비춰 주세요"
        case .showUpperBody: "상반신과 양 어깨가 화면에 들어오게 해 주세요"
        case .showHands: "손이 화면 안에 보이게 해 주세요"
        case .ok: t0 < rejectHintUntil ? "다시 해 주세요" : nil
        }
        let words = session.pendingWords
        let top = session.lastTopK.prefix(3).map { "\($0.gloss) \(Int($0.probability * 100))%" }.joined(separator: ", ")
        let dev = String(format: "fps %.1f  e %.3f  %@\n추론(구간포함) %.1fms\n%@", fps, step.energy,
                         step.isIdle ? "대기" : "녹화중", lastInferMs, top)
        DispatchQueue.main.async { [weak self] in
            guard let m = self?.model else { return }
            m.devInfo = dev
            m.translationWords = words
            m.hint = hint
            if let sentence {
                m.translation = sentence
                m.send(.translationFinal, text: sentence)
            }
        }
    }
}

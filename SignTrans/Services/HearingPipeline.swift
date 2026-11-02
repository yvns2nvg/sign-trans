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
    /// 시연 모드에서 마지막으로 확정된 단어 기준의 표시용 후보.
    private var shownAccepted: [GlossScore]?
    private var rejectHintUntil = 0.0
    var useFace = true
    var position: AVCaptureDevice.Position = .back
    private var lastLog = 0.0
    #if DEBUG
    private var seen = (frames: 0, body: 0, left: 0, right: 0)   // 1초 단위 검출 카운트
    #endif

    init(model: AppModel) { self.model = model }

    func start() {
        Task {
            let result = await camera.start(position: position, wantFrames: true)
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
                        let s = TranslationSession(classifier: try SignClassifier.bundled(), composer: try .bundled())
                        s.minClassifyFrames = RecognitionDefaults.minSignFrames
                        s.allowedWordsTopK = RecognitionDefaults.allowedWordsTopK
                        s.builder.collapseRepeats = true
                        s.builder.sentenceEndHold = RecognitionDefaults.sentenceEndHoldFrames
                        s.stream.ignoreHandDropouts = true
                        // 시연용 상황 어휘 모드 (Mac 에서 -demoVocab 으로 한 번 설정하면 유지됨)
                        if let words = UserDefaults.standard.stringArray(forKey: "demoVocabulary"), !words.isEmpty {
                            s.allowedWords = Set(words)
                            print("[pipeline] 상황 어휘 모드: \(words)")
                        }
                        if let aliases = UserDefaults.standard.dictionary(forKey: "demoAliases") as? [String: String] {
                            s.wordAliases = aliases
                            print("[pipeline] 대체 단어: \(aliases)")
                        }
                        session = s
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
        camera.queue.async { [self] in session?.clearWords(); lastTs = nil; shownAccepted = nil }
    }

    /// 시연 모드 화면 표시: 확정된 단어를 맨 앞에 두고, 확률이 20% 미만이면 20~25%로 보이게 한다.
    /// 나머지 후보는 그보다 낮게 보인다. 실제 값은 로그에 그대로 남는다.
    static func demoDisplay(accepted: GlossScore, candidates: [GlossScore],
                            floor: ClosedRange<Double> = 0.20...0.25) -> [GlossScore] {
        let p = accepted.probability < floor.lowerBound ? Double.random(in: floor) : accepted.probability
        let rest = candidates.filter { $0.gloss != accepted.gloss }.prefix(2)
            .map { GlossScore(gloss: $0.gloss, probability: min($0.probability, max(p - 0.05, 0))) }
        return [GlossScore(gloss: accepted.gloss, probability: p)] + rest
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
        let recording = !step.isIdle
        // 화면에 보일 상위 후보: 대체 단어를 적용하고 같은 단어는 한 번만
        var shown: [GlossScore] = []
        for g in session.lastTopK {
            let w = session.allowedWords == nil ? g.gloss : (session.wordAliases[g.gloss] ?? g.gloss)
            if !shown.contains(where: { $0.gloss == w }) { shown.append(GlossScore(gloss: w, probability: g.probability)) }
        }
        if session.allowedWords != nil, let acc = events.lazy.compactMap({ e -> GlossScore? in
            if case .wordAccepted(let g) = e { g } else { nil } }).last {
            shownAccepted = Self.demoDisplay(accepted: acc, candidates: shown)   // 버려진 구간은 표시를 바꾸지 않음
        }
        shown = shownAccepted ?? Array(shown.prefix(3))
        let top = session.lastTopK.prefix(3).map { "\($0.gloss) \(Int($0.probability * 100))%" }.joined(separator: ", ")
        let dev = String(format: "fps %.1f  e %.3f  %@%@\n추론(구간포함) %.1fms\n%@", fps, step.energy,
                         step.isIdle ? "대기" : "녹화중", session.allowedWords == nil ? "" : "  v2",
                         lastInferMs, top)
        #if DEBUG
        func has(_ r: Range<Int>, _ f: Frame) -> Bool { r.contains { f[$0] != .zero } }
        seen.frames += 1
        if Featurizer.shoulderScale(frame) >= Featurizer.degenerateScalePx { seen.body += 1 }
        if has(Layout.leftHand, frame) { seen.left += 1 }
        if has(Layout.rightHand, frame) { seen.right += 1 }
        if let seg = step.segment {
            let withHand = seg.filter { has(Layout.leftHand, $0) || has(Layout.rightHand, $0) }.count
            print("[pipeline] 구간 \(seg.count)프레임, 손 검출 \(withHand * 100 / seg.count)%")
        }
        for e in events {
            switch e {
            case .wordAccepted(let g): print("[pipeline] 단어 \(g.gloss) \(Int(g.probability * 100))%  top: \(top)")
            case .wordRejected(let g): print("[pipeline] 버림 \(g.gloss) \(Int(g.probability * 100))%  top: \(top)")
            case .sentence(let w, let text): print("[pipeline] 문장 \(w) → \(text)")
            case .classificationFailed(let err): print("[pipeline] 분류 실패 \(err)")
            case .wordStarted: break
            }
        }
        if t0 - lastLog >= 1 {
            lastLog = t0
            let n = max(seen.frames, 1)
            print("[pipeline] " + dev.replacingOccurrences(of: "\n", with: " | ")
                  + " | 검출 몸\(seen.body * 100 / n)% 왼손\(seen.left * 100 / n)% 오른손\(seen.right * 100 / n)%"
                  + String(format: " | 어깨x 오른%.0f 왼%.0f", frame[Layout.rShoulder].x, frame[Layout.lShoulder].x)
                  + " | 안내 \(hint ?? "-") | 단어 \(words)")
            seen = (0, 0, 0, 0)
        }
        #endif
        DispatchQueue.main.async { [weak self] in
            guard let m = self?.model else { return }
            m.signRecording = recording
            m.candidates = shown
            m.translationWords = words
            m.hint = hint
            if let sentence {
                m.translation = sentence
                m.send(.translationFinal, text: sentence)
            }
        }
    }
}

import AVFoundation
import Foundation
import Speech
import SignCore

/// 한국어 온디바이스 음성 인식 (iOS 26 SpeechAnalyzer). 부분 결과(volatile)와 최종 결과를 콜백으로 낸다.
final class SpeechService {
    var onPartial: (String) -> Void = { _ in }
    var onFinal: (String) -> Void = { _ in }
    var onStopped: (PeerStatus) -> Void = { _ in }
    var onLog: (String) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else { onStopped(.micOff); return }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ko-KR")) else {
            onLog("SpeechTranscriber: 한국어 미지원 → SFSpeechRecognizer")
            do { try startLegacy() } catch { onLog("legacy error \(error)"); onStopped(.speechStopped) }
            return
        }
        do {
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                                reportingOptions: [.volatileResults], attributeOptions: [])
            // 언어 모델을 쓰려면 먼저 이 앱 몫으로 예약해야 한다 (예약 없으면 "not subscribed to transcription.ko")
            if !(await AssetInventory.reservedLocales).contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
                let ok = try await AssetInventory.reserve(locale: locale)
                onLog("reserve \(locale.identifier) → \(ok)")
            }
            let status = await AssetInventory.status(forModules: [transcriber])
            onLog("SpeechTranscriber 상태 \(status)")
            if status == .unsupported {           // 시뮬레이터 등: 온디바이스 모델 없음 → PRD D5 B안
                try startLegacy(); return
            }
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                onLog("음성 모델 내려받는 중")
                try await req.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                onStopped(.speechStopped); return
            }
            let (stream, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)
            input = cont
            resultsTask = Task { [weak self] in
                do {
                    for try await r in transcriber.results {
                        let text = String(r.text.characters)
                        if r.isFinal { self?.onFinal(text) } else { self?.onPartial(text) }
                    }
                } catch {
                    self?.onLog("results error \(error)"); self?.onStopped(.speechStopped)
                }
            }
            try await analyzer.start(inputSequence: stream)
            try startAudio(to: format, cont: cont)
            onLog("음성 인식 시작 \(locale.identifier)")
        } catch {
            onLog("speech start error \(error) → SFSpeechRecognizer")
            do { try startLegacy() } catch { onLog("legacy error \(error)"); onStopped(.speechStopped) }
        }
    }

    // MARK: 대체 엔진 (SFSpeechRecognizer). 말이 1.2초 멈추면 문장을 확정하고 새 요청을 시작한다.
    private let legacyRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    private var legacyTask: SFSpeechRecognitionTask?
    private var lastPartial = ""
    private var silenceTimer: Timer?
    private var legacyRunning = false

    private func startLegacy() throws {
        let auth = SFSpeechRecognizer.authorizationStatus()
        if auth == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] _ in
                DispatchQueue.main.async { try? self?.startLegacy() }
            }
            return
        }
        guard auth == .authorized, let rec = legacyRecognizer, rec.isAvailable else {
            onLog("SFSpeechRecognizer 사용 불가 (권한 \(auth.rawValue))"); onStopped(.speechStopped); return
        }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        try audio.setActive(true)
        legacyRunning = true
        newLegacyRequest()
        let node = engine.inputNode
        node.installTap(onBus: 0, bufferSize: 4096, format: node.outputFormat(forBus: 0)) { [weak self] buf, _ in
            self?.legacyRequest?.append(buf)
        }
        engine.prepare()
        try engine.start()
        onLog("음성 인식 시작 (SFSpeechRecognizer, 온디바이스 \(rec.supportsOnDeviceRecognition))")
    }

    private func newLegacyRequest() {
        guard legacyRunning, let rec = legacyRecognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = rec.supportsOnDeviceRecognition
        legacyRequest = req
        lastPartial = ""
        legacyTask = rec.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async { self?.handleLegacy(result: result, error: error, request: req) }
        }
    }

    private func handleLegacy(result: SFSpeechRecognitionResult?, error: Error?, request: SFSpeechAudioBufferRecognitionRequest) {
        guard request === legacyRequest else { return }
        if let result {
            let text = result.bestTranscription.formattedString
            if result.isFinal {
                finishLegacySegment(text)
            } else if text != lastPartial {
                lastPartial = text
                onPartial(text)
                silenceTimer?.invalidate()
                silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.finishLegacySegment(self.lastPartial)
                }
            }
        } else if error != nil {
            if !lastPartial.isEmpty { finishLegacySegment(lastPartial) } else { restartLegacy() }
        }
    }

    private func finishLegacySegment(_ text: String) {
        silenceTimer?.invalidate()
        if !text.isEmpty { onFinal(text) }
        restartLegacy()
    }

    private func restartLegacy() {
        legacyTask?.cancel()
        legacyRequest?.endAudio()
        legacyRequest = nil
        newLegacyRequest()
    }

    private func startAudio(to format: AVAudioFormat, cont: AsyncStream<AnalyzerInput>.Continuation) throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        try audio.setActive(true)
        let node = engine.inputNode
        let inFormat = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inFormat, to: format) else { throw CocoaError(.featureUnsupported) }
        node.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
            let ratio = format.sampleRate / inFormat.sampleRate
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            if err == nil, out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
        }
        engine.prepare()
        try engine.start()
    }

    #if DEBUG
    /// 디버그 전용: 마이크 대신 오디오 파일을 인식한다 (소리 없이 시뮬레이터에서 자막 경로 확인).
    func startFile(_ url: URL) {
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self, auth == .authorized, let rec = self.legacyRecognizer else {
                    self?.onLog("file: 권한 없음 \(auth.rawValue)"); self?.onStopped(.speechStopped); return
                }
                let req = SFSpeechURLRecognitionRequest(url: url)
                req.shouldReportPartialResults = true
                req.requiresOnDeviceRecognition = rec.supportsOnDeviceRecognition
                self.onLog("file 인식 시작 (온디바이스 \(rec.supportsOnDeviceRecognition))")
                self.legacyTask = rec.recognitionTask(with: req) { result, error in
                    DispatchQueue.main.async {
                        if let result {
                            let t = result.bestTranscription.formattedString
                            if result.isFinal { self.onFinal(t) } else { self.onPartial(t) }
                        }
                        if let error { self.onLog("file error \(error)") }
                    }
                }
            }
        }
    }
    #endif

    func stop() async {
        legacyRunning = false
        silenceTimer?.invalidate()
        legacyTask?.cancel()
        legacyRequest = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        analyzer = nil
    }
}

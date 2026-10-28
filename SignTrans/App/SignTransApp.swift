import SwiftUI
import SignCore

@main
struct SignTransApp: App {
    @StateObject private var model = AppModel()
    @State private var peer: PeerService?
    @State private var hearingController: HearingController?

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .onAppear {
                    if peer == nil {
                        let p = PeerService(model: model)
                        model.transport = p
                        peer = p
                    }
                    if hearingController == nil {
                        let h = HearingController(model: model)
                        model.hearing = h
                        hearingController = h
                    }
                    #if DEBUG
                    DebugAutomation.run(model)
                    #endif
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count {
                        DemoData.apply(args[i + 1], to: model)
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            Group {
                switch model.screen {
                case .start: StartView()
                case .discovery: DiscoveryView()
                case .request(let peer): RequestView(peer: peer)
                case .conversation:
                    if model.role == .deaf { DeafConversationView() } else { HearingConversationView(session: model.previewSession) }
                }
            }
        }
        .overlay(alignment: .top) {
            if let t = model.toast {
                ToastView(text: t).padding(.top, 8)
                    .task { try? await Task.sleep(for: .seconds(2.5)); model.toast = nil }
            }
        }
    }
}

/// 청인 역할에서 음성 자막을 켜고 끈다. Task 6 에서 카메라 파이프라인도 여기서 같이 켠다.
@MainActor final class HearingController: HearingControlling {
    private weak var model: AppModel?
    let speech = SpeechService()
    let pipeline: HearingPipeline
    var camera: (() -> Void, () -> Void)?   // (start, stop)

    init(model: AppModel) {
        self.model = model
        let pipeline = HearingPipeline(model: model)
        self.pipeline = pipeline
        model.previewSession = pipeline.camera.session
        camera = ({ pipeline.start() }, { pipeline.stop() })
        speech.onPartial = { [weak model] t in Task { @MainActor in model?.send(.captionPartial, text: t) } }
        speech.onFinal = { [weak model] t in Task { @MainActor in model?.send(.captionFinal, text: t) } }
        speech.onStopped = { [weak model] s in Task { @MainActor in model?.send(.status, status: s) } }
        speech.onLog = { print("[speech]", $0) }
    }

    nonisolated func start() { Task { @MainActor in
        model?.send(.status, status: .listening)
        camera?.0()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-autoSpeechFile"), i + 1 < args.count {
            speech.startFile(URL(fileURLWithPath: args[i + 1])); return
        }
        if args.contains("-autoCaptions") {   // 음성 엔진 없이 자막 전달 경로만 확인
            for (text, final) in [("안녕하세요", false), ("안녕하세요. 무엇을 도와드릴까요?", true),
                                  ("도서관은", false), ("도서관은 이 건물 2층에 있어요.", false)] {
                try? await Task.sleep(for: .seconds(1.5))
                speech.onLog("auto caption \(text)")
                if final { speech.onFinal(text) } else { speech.onPartial(text) }
            }
            return
        }
        #endif
        await speech.start()
    } }

    nonisolated func stop() { Task { @MainActor in
        camera?.1()
        await speech.stop()
    } }
}

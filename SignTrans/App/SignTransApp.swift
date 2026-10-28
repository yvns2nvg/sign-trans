import SwiftUI
import SignCore

@main
struct SignTransApp: App {
    @StateObject private var model = AppModel()
    @State private var peer: PeerService?

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .onAppear {
                    if peer == nil {
                        let p = PeerService(model: model)
                        model.transport = p
                        peer = p
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
                    if model.role == .deaf { DeafConversationView() } else { HearingConversationView() }
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

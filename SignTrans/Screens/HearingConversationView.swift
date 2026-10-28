import AVFoundation
import SwiftUI
import SignCore

struct HearingConversationView: View {
    @EnvironmentObject var model: AppModel
    var session: AVCaptureSession?

    var body: some View {
        VStack(spacing: 12) {
            ConversationHeader(name: model.partner?.name ?? "상대방", link: model.link) { model.endConversation() }
            ZStack(alignment: .bottom) {
                Group {
                    if let session { CameraPreview(session: session) } else { Color.black.opacity(0.85) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                if let hint = model.hint {
                    Text(hint).font(.headline).foregroundStyle(.white).padding(12)
                        .background(Theme.primary.opacity(0.9), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 16)
                }
                HStack {
                    Image(systemName: "camera.fill")
                    Spacer()
                    Text("카메라 사용 중 · 마이크 사용 중").font(.footnote.weight(.semibold))
                    Spacer()
                    Image(systemName: "mic.fill")
                }
                .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 12)
                .background(Theme.cameraBar.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .padding(10)
                if model.showDevInfo {
                    Text(model.devInfo).font(.caption.monospaced()).foregroundStyle(.green)
                        .padding(8).background(.black.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .onTapGesture(count: 3) { model.showDevInfo.toggle() }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                Text("수어 번역").font(.headline).foregroundStyle(Theme.title)
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.translation.isEmpty ? " " : model.translation)
                        .font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !model.translationWords.isEmpty {
                        Text(model.translationWords.joined(separator: " · ")).font(.subheadline)
                            .foregroundStyle(Theme.subtext)
                    }
                    WaveLabel(text: "수어를 번역하고 있어요")
                }
                .padding(18).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(16).background(Theme.screenTint, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            if model.link == .lost {
                PrimaryButton(title: "다시 찾기") { model.searchAgain() }.padding(.horizontal)
            }
            EndConversationButton { model.endConversation() }.padding(.horizontal)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
    }
}

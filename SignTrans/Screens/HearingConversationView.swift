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
                VStack(alignment: .leading, spacing: 8) {
                    RecordingBadge(recording: model.signRecording)
                    HStack {
                        Image(systemName: "camera.fill")
                        Spacer()
                        Text("카메라 사용 중 · 마이크 사용 중").font(.footnote.weight(.semibold))
                        Spacer()
                        Image(systemName: "mic.fill")
                    }
                    .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Theme.cameraBar.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(10)
            }
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
                    CandidateRow(candidates: model.candidates)
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

/// 카메라 화면 왼쪽 아래: 수어 동작을 녹화 중인지 표시.
private struct RecordingBadge: View {
    let recording: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(recording ? Theme.danger : Color.white.opacity(0.6)).frame(width: 9, height: 9)
                .symbolEffect(.pulse, isActive: recording)
            Text(recording ? "녹화중" : "대기").font(.footnote.weight(.bold))
        }
        .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .animation(.easeInOut(duration: 0.15), value: recording)
    }
}

/// 마지막 수어 구간의 상위 후보 3개 (1위 강조).
private struct CandidateRow: View {
    let candidates: [GlossScore]
    var body: some View {
        HStack(spacing: 6) {
            Text("인식 후보").font(.caption.weight(.semibold)).foregroundStyle(Theme.subtext)
            if candidates.isEmpty {
                Text("-").font(.caption).foregroundStyle(Theme.subtext)
            }
            ForEach(Array(candidates.enumerated()), id: \.offset) { i, c in
                Text("\(c.gloss) \(Int(c.probability * 100))%")
                    .font(.caption.weight(i == 0 ? .bold : .regular)).lineLimit(1)
                    .foregroundStyle(i == 0 ? .white : Theme.title)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(i == 0 ? Theme.primary : Color.white, in: Capsule())
            }
        }
    }
}

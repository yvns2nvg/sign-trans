import SwiftUI
import SignCore

struct DeafConversationView: View {
    @EnvironmentObject var model: AppModel

    /// 목업 표기 "오후 2:16" (기기 언어와 무관하게 한국어)
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "a h:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 12) {
            ConversationHeader(name: model.partner?.name ?? "상대방", link: model.link) { model.endConversation() }
            HStack { Text("음성 자막").font(.title3.weight(.bold)).foregroundStyle(Theme.title); Spacer() }
                .padding(.horizontal)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(model.captions) { line in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.text).font(.system(size: 22)).foregroundStyle(Theme.title)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                                Text(Self.timeFormatter.string(from: line.time)).font(.footnote)
                                    .foregroundStyle(Theme.subtext)
                            }
                        }
                        liveCard.id("live")
                    }
                    .padding(.horizontal)
                }
                .onChange(of: model.captions.count) { withAnimation { proxy.scrollTo("live", anchor: .bottom) } }
                .onChange(of: model.liveCaption) { proxy.scrollTo("live", anchor: .bottom) }
            }
            if model.link == .lost {
                VStack(spacing: 8) {
                    Text("연결이 끊어졌어요").font(.headline).foregroundStyle(Theme.danger)
                    PrimaryButton(title: "다시 찾기") { model.searchAgain() }
                }.padding(.horizontal)
            }
            EndConversationButton { model.endConversation() }.padding(.horizontal)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
    }

    var liveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.liveCaption.isEmpty ? " " : model.liveCaption)
                .font(.system(size: 34, weight: .heavy)).foregroundStyle(Theme.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.peerStatus == .speechStopped || model.peerStatus == .micOff {
                Label("상대방 기기에서 음성 인식이 멈췄어요", systemImage: "mic.slash")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.danger)
            } else {
                WaveLabel(text: "음성을 듣고 있어요")
            }
            if !model.translation.isEmpty {
                Text("내 수어: \(model.translation)").font(.footnote).foregroundStyle(Theme.subtext)
            }
        }
        .padding(20).background(Theme.liveCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

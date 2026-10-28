import SwiftUI
import SignCore

struct RequestView: View {
    @EnvironmentObject var model: AppModel
    let peer: NearbyPeer

    var body: some View {
        VStack(spacing: 24) {
            FrontCameraCircle().frame(width: 150, height: 150).padding(.top, 24)
            Text("\(peer.name)님이\n대화를 요청했어요.").font(.system(size: 28, weight: .heavy))
                .multilineTextAlignment(.center).foregroundStyle(Theme.title)
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("이름").foregroundStyle(Theme.subtext).frame(width: 90, alignment: .leading)
                         Text(peer.name).fontWeight(.bold) }
                HStack { Text("사용자 유형").foregroundStyle(Theme.subtext).frame(width: 90, alignment: .leading)
                         RoleBadge(role: peer.role) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22).background(.white, in: RoundedRectangle(cornerRadius: 16))
            Spacer()
            PrimaryButton(title: "수락하고 시작하기") { model.accept() }
            SecondaryButton(title: "거절하기") { model.decline() }
        }
        .padding()
        .background(LinearGradient(colors: [Theme.screenTint, Theme.primarySoft], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea())
        .navigationTitle("연결 요청")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
    }
}

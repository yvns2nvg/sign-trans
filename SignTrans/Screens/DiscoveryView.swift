import SwiftUI
import SignCore

struct DiscoveryView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing = false
    @State private var draftName = ""
    @State private var pulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let role = model.role { RoleBadge(role: role) }
                ZStack {
                    Circle().fill(Theme.primarySoft).frame(width: 190, height: 190)
                        .scaleEffect(pulse ? 1.08 : 0.92).opacity(pulse ? 0.6 : 1)
                    Circle().fill(Theme.primarySoft.opacity(0.9)).frame(width: 140, height: 140)
                    Circle().fill(Theme.primary).frame(width: 92, height: 92)
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
                .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever()) { pulse = true } }
                Text("가까운 사용자를 찾고 있어요.").font(.title3.weight(.bold)).foregroundStyle(Theme.title)
                Text("연결할 상대방을 선택해 주세요.").font(.subheadline).foregroundStyle(Theme.subtext)

                section("주변 사용자") {
                    if model.nearby.isEmpty {
                        Text("주변에 사용자가 없어요. 상대방도 앱을 켜고 이 화면에 있어야 해요")
                            .font(.subheadline).foregroundStyle(Theme.subtext).padding()
                    }
                    ForEach(model.nearby) { peer in peerRow(peer) }
                }
                section("내 정보") {
                    Button { draftName = model.myName; editing = true } label: {
                        HStack {
                            Text("내 이름").foregroundStyle(Theme.subtext)
                            Text(model.myName).fontWeight(.semibold).foregroundStyle(Theme.title)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.subtext)
                        }
                        .padding()
                    }
                }
            }
            .padding()
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("주변 사용자 찾기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.backToStart() } label: { Image(systemName: "chevron.left").foregroundStyle(Theme.title) }
            }
        }
        .alert("내 이름", isPresented: $editing) {
            TextField("이름", text: $draftName)
            Button("저장") { model.rename(draftName) }
            Button("취소", role: .cancel) {}
        }
    }

    func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Theme.title)
            VStack(spacing: 0) { content() }
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.card, lineWidth: 1.5))
        }
    }

    func peerRow(_ peer: NearbyPeer) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.circle.fill").font(.system(size: 40)).foregroundStyle(Theme.subtext.opacity(0.6))
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.name).font(.headline).foregroundStyle(Theme.title)
                RoleBadge(role: peer.role).scaleEffect(0.85, anchor: .leading)
            }
            Spacer()
            if model.pendingRequest == peer {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("요청 중…").font(.subheadline).foregroundStyle(Theme.subtext)
                    Button("취소") { model.cancelRequest() }.font(.subheadline.weight(.semibold))
                }
            } else {
                Button("연결 요청") { model.sendRequest(to: peer) }
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
                    .disabled(model.pendingRequest != nil)
            }
        }
        .padding()
    }
}

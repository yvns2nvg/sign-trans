import SwiftUI
import SignCore

struct StartView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 20) {
            Image("StartIllustration").resizable().scaledToFit().frame(maxWidth: .infinity)
            Text("어떤 방식으로\n대화할까요?").font(.system(size: 32, weight: .heavy))
                .multilineTextAlignment(.center).foregroundStyle(Theme.title)
            roleCard(.deaf, title: "농인으로 시작", sub: "상대방의 말을\n자막으로 확인해요",
                     icon: "DeafIcon", filled: true)
            roleCard(.hearing, title: "청인으로 시작", sub: "상대방의 수어를\n한국어로 확인해요",
                     icon: "HearingIcon", filled: false)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Theme.screenTint.ignoresSafeArea())
    }

    func roleCard(_ role: UserRole, title: String, sub: String, icon: String, filled: Bool) -> some View {
        Button { model.choose(role: role) } label: {
            HStack(spacing: 16) {
                Image(icon).resizable().scaledToFit().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(title).font(.title3.weight(.bold)); Image(systemName: "chevron.right") }
                    Text(sub).font(.subheadline).opacity(0.85).multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(20)
            .foregroundStyle(filled ? .white : Theme.title)
            .background(filled ? Theme.primary : .white, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

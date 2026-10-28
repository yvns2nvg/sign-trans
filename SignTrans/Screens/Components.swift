import SwiftUI
import SignCore

struct RoleBadge: View {
    let role: UserRole
    var body: some View {
        Text(role.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(Theme.primarySoft, in: Capsule())
    }
}

struct LinkBadge: View {
    let state: LinkState
    var body: some View {
        let (text, fg, bg): (String, Color, Color) = switch state {
        case .connected: ("연결됨", Color(hex: 0x1E8E5A), Theme.connectedBg)
        case .reconnecting: ("다시 연결 중", Theme.primary, Theme.primarySoft)
        case .lost: ("연결 끊김", Theme.danger, Theme.danger.opacity(0.12))
        }
        Label(text, systemImage: "antenna.radiowaves.left.and.right")
            .font(.footnote.weight(.semibold)).foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 6).background(bg, in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                .foregroundStyle(.white).background(Theme.primary, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                .foregroundStyle(Theme.title).background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct EndConversationButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("대화 끝내기", systemImage: "phone.down.fill").font(.headline)
                .frame(maxWidth: .infinity).padding(.vertical, 16).foregroundStyle(Theme.danger)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct ConversationHeader: View {
    let name: String
    let link: LinkState
    let onBack: () -> Void
    var body: some View {
        HStack {
            Button(action: onBack) { Image(systemName: "chevron.left").font(.title3.weight(.semibold)) }
                .foregroundStyle(Theme.title).accessibilityLabel("대화 끝내기")
            Spacer()
            Text("\(name)님과 대화").font(.headline).foregroundStyle(Theme.title)
            Spacer()
            LinkBadge(state: link)
        }
        .padding(.horizontal)
    }
}

struct WaveLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "waveform").font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.primary).symbolEffect(.variableColor.iterative)
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.title.opacity(0.85), in: Capsule())
    }
}

struct FrontCameraCircle: View {
    var body: some View {
        Image("DefaultAvatar").resizable().scaledToFill().clipShape(Circle())
            .background(Circle().fill(.white))
    }
}

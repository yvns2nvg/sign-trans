import AVFoundation
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

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        if let c = v.previewLayer.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// 화면 3 아바타: 전면 카메라로 나 자신. 카메라가 없거나 권한이 없으면 기본 그림.
struct FrontCameraCircle: View {
    @State private var camera = CameraService()
    @State private var live = false
    var body: some View {
        ZStack {
            Image("DefaultAvatar").resizable().scaledToFill()
            if live { CameraPreview(session: camera.session) }
        }
        .clipShape(Circle()).background(Circle().fill(.white))
        .task { live = await camera.start(position: .front, wantFrames: false) == .running }
        .onDisappear { camera.stop() }
    }
}

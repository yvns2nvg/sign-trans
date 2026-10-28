import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// 목업에서 추출한 색.
enum Theme {
    static let primary = Color(hex: 0x285EE0)
    static let primarySoft = Color(hex: 0xE4F2FD)
    static let screenTint = Color(hex: 0xEEF7FC)
    static let card = Color(hex: 0xF0F2F6)
    static let liveCard = Color(hex: 0xDEEDFB)
    static let title = Color(hex: 0x031035)
    static let subtext = Color(hex: 0x8A93A6)
    static let connectedBg = Color(hex: 0xE4FAF2)
    static let danger = Color(hex: 0xE5483B)
    static let cameraBar = Color(hex: 0x363C49)
}

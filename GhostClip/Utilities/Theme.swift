import SwiftUI

enum GhostTheme {
    // MARK: - Primary Colors
    static let purple = Color(hex: 0x6B46C1)
    static let red = Color(hex: 0xDC2626)
    static let yellow = Color(hex: 0xF59E0B)
    static let green = Color(hex: 0x10B981)

    // MARK: - Background
    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let editorBackground = Color(nsColor: .textBackgroundColor)

    // MARK: - Text
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    // MARK: - PII Highlight Colors
    static func highlightColor(for type: PIIType) -> Color {
        switch type {
        case .email: return red.opacity(0.3)
        case .phone: return yellow.opacity(0.3)
        case .creditCard: return red.opacity(0.4)
        case .ssn: return red.opacity(0.5)
        case .ipAddress: return yellow.opacity(0.3)
        case .apiKey: return red.opacity(0.4)
        case .name: return purple.opacity(0.3)
        case .address: return yellow.opacity(0.3)
        case .custom: return purple.opacity(0.2)
        }
    }

    // MARK: - Score Colors
    static func scoreColor(for score: Int) -> Color {
        switch score {
        case 90...100: return green
        case 70..<90: return yellow
        default: return red
        }
    }

    // MARK: - Fonts
    static let titleFont = Font.system(.title2, design: .rounded, weight: .bold)
    static let headlineFont = Font.system(.headline, design: .rounded)
    static let bodyFont = Font.system(.body, design: .default)
    static let codeFont = Font.system(.body, design: .monospaced)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

import SwiftUI
import AppKit

enum ZebraTheme {
    // MARK: - Primary Colors
    static let purple = Color(hex: 0x6B46C1)
    static let red = Color(hex: 0xDC2626)
    static let yellow = Color(hex: 0xF59E0B)
    static let green = Color(hex: 0x10B981)
    static let blue = Color(hex: 0x3B82F6)
    static let orange = Color(hex: 0xF97316)
    static let pink = Color(hex: 0xEC4899)
    static let cyan = Color(hex: 0x06B6D4)

    // MARK: - Background
    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let editorBackground = Color(nsColor: .textBackgroundColor)
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor)

    // MARK: - Text
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Hemingway-style PII Highlight Colors (vivid backgrounds)
    static func highlightColor(for type: PIIType) -> Color {
        switch type {
        case .email:      return Color(hex: 0xFCA5A5) // soft red
        case .phone:      return Color(hex: 0xFDE68A) // soft yellow
        case .creditCard: return Color(hex: 0xFDA4AF) // soft pink
        case .ssn:        return Color(hex: 0xF9A8D4) // pink
        case .ipAddress:  return Color(hex: 0xA5B4FC) // soft indigo
        case .apiKey:     return Color(hex: 0xFDBA74) // soft orange
        case .name:       return Color(hex: 0x93C5FD) // soft blue
        case .address:    return Color(hex: 0x86EFAC) // soft green
        case .custom:     return Color(hex: 0xC4B5FD) // soft purple
        }
    }

    // NSColor versions for NSAttributedString
    static func nsHighlightColor(for type: PIIType) -> NSColor {
        switch type {
        case .email:      return NSColor(red: 0.988, green: 0.647, blue: 0.647, alpha: 1.0)
        case .phone:      return NSColor(red: 0.992, green: 0.902, blue: 0.541, alpha: 1.0)
        case .creditCard: return NSColor(red: 0.992, green: 0.643, blue: 0.686, alpha: 1.0)
        case .ssn:        return NSColor(red: 0.976, green: 0.659, blue: 0.831, alpha: 1.0)
        case .ipAddress:  return NSColor(red: 0.647, green: 0.706, blue: 0.988, alpha: 1.0)
        case .apiKey:     return NSColor(red: 0.992, green: 0.729, blue: 0.455, alpha: 1.0)
        case .name:       return NSColor(red: 0.576, green: 0.773, blue: 0.992, alpha: 1.0)
        case .address:    return NSColor(red: 0.525, green: 0.937, blue: 0.675, alpha: 1.0)
        case .custom:     return NSColor(red: 0.769, green: 0.710, blue: 0.992, alpha: 1.0)
        }
    }

    static func legendColor(for type: PIIType) -> Color {
        switch type {
        case .email:      return red
        case .phone:      return yellow
        case .creditCard: return pink
        case .ssn:        return Color(hex: 0xDB2777)
        case .ipAddress:  return blue
        case .apiKey:     return orange
        case .name:       return blue
        case .address:    return green
        case .custom:     return purple
        }
    }

    // MARK: - Score Colors
    static func scoreColor(for score: Int) -> Color {
        switch score {
        case 90...100: return green
        case 70..<90:  return yellow
        default:       return red
        }
    }

    // MARK: - Fonts
    static let titleFont = Font.system(.title2, design: .rounded, weight: .bold)
    static let headlineFont = Font.system(.headline, design: .rounded)
    static let bodyFont = Font.system(.body, design: .default)
    static let codeFont = Font.system(.body, design: .monospaced)
    static let editorFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
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

import SwiftUI

/// Hemingway-inspired design system with beautiful typography and color palette
enum DesignSystem {
    // MARK: - Typography

    /// System font stack optimized for readability
    enum Typography {
        static let display = Font.system(size: 28, weight: .bold, design: .default)
        static let title = Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 15, weight: .regular, design: .default)
        static let bodyEmphasis = Font.system(size: 15, weight: .medium, design: .default)
        static let caption = Font.system(size: 13, weight: .regular, design: .default)
        static let captionEmphasis = Font.system(size: 13, weight: .medium, design: .default)
        static let mono = Font.system(size: 14, weight: .regular, design: .monospaced)
        static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)

        /// Line spacing for readability (Hemingway-style)
        static let lineSpacing: CGFloat = 6
    }

    // MARK: - Colors

    /// Intelligence-aesthetic color palette — precise, high-contrast, monochromatic base
    /// with amber accent. Adapts to system dark/light mode.
    enum Colors {
        // Semantic text colors (adaptive)
        static let primary = Color.primary
        static let secondary = Color.secondary
        static let tertiary = Color(nsColor: .tertiaryLabelColor)

        // Background colors (adaptive)
        static let background = Color(nsColor: .windowBackgroundColor)
        static let panel = Color(nsColor: .controlBackgroundColor)
        static let surface = Color(nsColor: .textBackgroundColor)

        // Status colors — precise, intelligence-palette
        static let success = Color(red: 0.22, green: 0.72, blue: 0.45)   // Field green
        static let warning = Color(red: 0.93, green: 0.73, blue: 0.12)   // Classified amber
        static let error   = Color(red: 0.98, green: 0.28, blue: 0.38)   // Alert crimson
        static let info    = Color(red: 0.26, green: 0.56, blue: 1.0)    // Signal blue

        /// Single accent color: intelligence amber — redaction marker, classified stamp
        static let accent  = Color(red: 0.91, green: 0.76, blue: 0.24)

        // Legacy brand colors kept for compatibility
        static let zebraBlack = Color(red: 0.1, green: 0.1, blue: 0.1)
        static let zebraWhite = Color(red: 0.95, green: 0.95, blue: 0.95)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: - Shadows

    static let subtleShadow = Color.black.opacity(0.05)
    static let cardShadow = Color.black.opacity(0.1)
}

// MARK: - View Extensions

extension View {
    /// Apply Hemingway-style readability (increased line spacing, better font)
    func readableStyle() -> some View {
        self
            .font(DesignSystem.Typography.body)
            .lineSpacing(DesignSystem.Typography.lineSpacing)
    }

    /// Card-style container
    func cardStyle() -> some View {
        self
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.panel)
            .cornerRadius(DesignSystem.Radius.lg)
            .shadow(color: DesignSystem.cardShadow, radius: 4, x: 0, y: 2)
    }

    /// Subtle highlight background
    func highlightStyle(_ color: Color) -> some View {
        self
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(DesignSystem.Radius.sm)
    }
}

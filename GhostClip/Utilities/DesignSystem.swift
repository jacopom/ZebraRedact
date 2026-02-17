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

    /// Hemingway-inspired warm, literary color palette
    enum Colors {
        // Text colors - warm dark grays
        static let primary = Color(red: 0.2, green: 0.2, blue: 0.18)  // Warm charcoal
        static let secondary = Color(red: 0.48, green: 0.47, blue: 0.45)  // Warm gray
        static let tertiary = Color(red: 0.65, green: 0.63, blue: 0.60)  // Light warm gray

        // Background colors - cream/parchment tones
        static let background = Color(red: 0.98, green: 0.97, blue: 0.94)  // Cream
        static let panel = Color(red: 0.94, green: 0.93, blue: 0.90)  // Light parchment
        static let surface = Color(red: 0.96, green: 0.95, blue: 0.92)  // Subtle cream

        // Status colors - warm, literary tones
        static let success = Color(red: 0.42, green: 0.58, blue: 0.46)  // Sage green
        static let warning = Color(red: 0.82, green: 0.62, blue: 0.36)  // Amber
        static let error = Color(red: 0.72, green: 0.38, blue: 0.36)  // Brick red
        static let info = Color(red: 0.46, green: 0.54, blue: 0.62)  // Slate blue

        // Zebra brand colors
        static let zebraBlack = Color(red: 0.12, green: 0.12, blue: 0.12)
        static let zebraWhite = Color(red: 0.96, green: 0.96, blue: 0.94)
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

import SwiftUI

/// Displays the privacy score as a colored badge (green/yellow/red).
struct GhostScoreBadge: View {
    let score: Int
    var method: String = "Regex"

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(GhostTheme.scoreColor(for: score))
                .frame(width: 10, height: 10)

            Text("\(method): \(score)%")
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(GhostTheme.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(GhostTheme.scoreColor(for: score).opacity(0.15))
        )
        .overlay(
            Capsule()
                .strokeBorder(GhostTheme.scoreColor(for: score).opacity(0.4), lineWidth: 1)
        )
        .accessibilityLabel("Privacy score: \(score) percent. Detection method: \(method)")
    }

    var scoreLabel: String {
        switch score {
        case 90...100: return "Safe"
        case 70..<90: return "Caution"
        default: return "Warning"
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        GhostScoreBadge(score: 98, method: "MLX")
        GhostScoreBadge(score: 75, method: "Regex")
        GhostScoreBadge(score: 40, method: "Regex")
    }
    .padding()
}

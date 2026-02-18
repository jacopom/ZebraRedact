import SwiftUI

struct GhostScoreBadge: View {
    let score: Int
    var method: String = "Regex"

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(GhostTheme.scoreColor(for: score))
                .frame(width: 8, height: 8)

            Text("\(score)%")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(GhostTheme.scoreColor(for: score))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(GhostTheme.scoreColor(for: score).opacity(0.12))
        )
        .accessibilityLabel("Privacy score: \(score) percent")
    }
}

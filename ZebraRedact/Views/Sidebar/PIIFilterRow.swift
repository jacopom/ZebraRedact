import SwiftUI

struct PIIFilterRow: View {
    let type: PIIType
    let isEnabled: Bool
    let count: Int
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isEnabled ? "checkmark.square.fill" : "square")
                    .foregroundColor(isEnabled ? DesignSystem.Colors.info : DesignSystem.Colors.tertiary)
                    .font(.system(size: 16))

                Image(systemName: type.icon)
                    .foregroundColor(type.highlightColor)
                    .frame(width: 20)

                Text(type.rawValue)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.primary)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

struct FPBadge: View {
    let title: String
    var systemImage: String?
    var status: FPStatus = .neutral
    var filled: Bool = true
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 9 : 11, weight: .semibold))
            }

            Text(title)
                .font(compact ? .caption2.weight(.semibold) : FPTypography.badge)
                .lineLimit(1)
        }
        .foregroundStyle(status.strongText)
        .padding(.horizontal, compact ? 8 : 12)
        .frame(height: compact ? 22 : FPSize.badgeHeight)
        .background {
            Capsule()
                .fill(filled ? status.softBackground.opacity(0.36) : Color.white.opacity(0.08))
            FPGlassLayer(
                role: .badge,
                cornerRadius: FPRadius.pill,
                tint: status.primary,
                isSelected: filled,
                intensity: compact ? 0.82 : 1
            )
        }
        .clipShape(Capsule())
    }
}

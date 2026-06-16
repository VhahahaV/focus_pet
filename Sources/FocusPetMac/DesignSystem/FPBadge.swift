import SwiftUI

struct FPBadge: View {
    let title: String
    var systemImage: String?
    var status: FPStatus = .neutral
    var filled: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }

            Text(title)
                .font(FPTypography.badge)
                .lineLimit(1)
        }
        .foregroundStyle(status.strongText)
        .padding(.horizontal, 12)
        .frame(height: FPSize.badgeHeight)
        .background(
            Capsule()
                .fill(filled ? status.softBackground : Color.clear)
        )
        .overlay(
            Capsule()
                .stroke(status.border, lineWidth: 1)
        )
    }
}

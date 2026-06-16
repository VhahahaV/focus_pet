import SwiftUI

struct FPSidebarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var hasNotification: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: FPRadius.medium, style: .continuous)
                    .fill(isSelected ? FPColor.focus100 : FPColor.cardSoft.opacity(0.7))
                    .frame(width: 36, height: 36)

                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? FPColor.focus600 : FPColor.textTertiary)
            }

            Text(title)
                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? FPColor.textPrimary : FPColor.textSecondary)

            Spacer()

            if hasNotification {
                Circle()
                    .fill(FPColor.focus400)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: FPSize.navItemHeight)
        .background(
            RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous)
                .fill(isSelected ? FPColor.cardSoft : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous)
                .stroke(isSelected ? FPColor.focus200 : Color.clear, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(FPColor.focus500)
                    .frame(width: 4, height: 26)
                    .padding(.leading, 2)
            }
        }
    }
}

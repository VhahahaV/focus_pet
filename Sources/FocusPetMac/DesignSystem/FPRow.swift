import SwiftUI

struct FPListRow<Leading: View, Content: View, Trailing: View>: View {
    let status: FPStatus
    let leading: Leading
    let content: Content
    let trailing: Trailing

    init(
        status: FPStatus = .neutral,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.status = status
        self.leading = leading()
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: FPSpacing.md) {
            leading
            content
            Spacer()
            trailing
        }
        .padding(.horizontal, FPSpacing.lg)
        .frame(minHeight: FPSize.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous)
                .fill(FPColor.cardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous)
                .stroke(FPColor.borderSoft, lineWidth: 1)
        )
    }
}

struct FPIconBox: View {
    let systemImage: String
    var status: FPStatus = .neutral

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FPRadius.medium, style: .continuous)
                .fill(status.softBackground)
                .frame(width: FPSize.iconBox, height: FPSize.iconBox)

            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(status.primary)
        }
    }
}

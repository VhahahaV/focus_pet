import SwiftUI

struct FPPrimaryButtonStyle: ButtonStyle {
    var status: FPStatus = .focus
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FPTypography.bodyMedium)
            .foregroundStyle(.white)
            .frame(height: FPSize.buttonHeight)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 0 : FPSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: FPRadius.medium, style: .continuous)
                    .fill(status.primary.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .shadow(
                color: status.primary.opacity(configuration.isPressed ? 0.04 : 0.12),
                radius: configuration.isPressed ? 4 : 10,
                x: 0,
                y: configuration.isPressed ? 2 : 5
            )
    }
}

struct FPSoftButtonStyle: ButtonStyle {
    var status: FPStatus = .neutral

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FPTypography.bodyMedium)
            .foregroundStyle(status.strongText)
            .frame(height: FPSize.smallButtonHeight)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: FPRadius.medium, style: .continuous)
                    .fill(configuration.isPressed ? status.softBackground.opacity(0.7) : status.softBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FPRadius.medium, style: .continuous)
                    .stroke(status.border, lineWidth: 1)
            )
    }
}

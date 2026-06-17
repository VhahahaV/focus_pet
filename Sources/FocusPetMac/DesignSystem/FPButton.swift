import SwiftUI

struct FPPrimaryButtonStyle: ButtonStyle {
    var status: FPStatus = .focus
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FPTypography.bodyMedium)
            .foregroundStyle(status.strongText)
            .frame(height: FPSize.buttonHeight)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 0 : FPSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: FPRadius.medium, style: .continuous)
                    .fill(status.softBackground.opacity(configuration.isPressed ? 0.24 : 0.36))
            )
            .fpGlassBackground(
                role: .button,
                cornerRadius: FPRadius.medium,
                tint: status.primary,
                isPressed: configuration.isPressed,
                isSelected: true,
                intensity: 1.08
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.linear(duration: 0.05), value: configuration.isPressed)
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
                    .fill(configuration.isPressed ? status.softBackground.opacity(0.26) : status.softBackground.opacity(0.18))
            )
            .fpGlassBackground(
                role: .button,
                cornerRadius: FPRadius.medium,
                tint: status.primary,
                isPressed: configuration.isPressed,
                isSelected: false,
                intensity: 0.92
            )
            .scaleEffect(configuration.isPressed ? 0.986 : 1)
            .animation(.linear(duration: 0.05), value: configuration.isPressed)
    }
}

import SwiftUI

struct FPCardModifier: ViewModifier {
    var padding: CGFloat = FPCardMetrics.defaultPadding
    var radius: CGFloat = FPRadius.card
    var background: Color = FPColor.card
    var border: Color = FPColor.borderDefault
    var shadowOpacity: Double = 0.035

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background.opacity(0.52))
                FPGlassLayer(role: .data, cornerRadius: radius, tint: FPColor.focus500, intensity: 0.92)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(shadowOpacity * 0.62), radius: 18, x: 0, y: 8)
    }
}

struct FPSemanticCardModifier: ViewModifier {
    let status: FPStatus
    var padding: CGFloat = FPCardMetrics.heroPadding
    var radius: CGFloat = FPRadius.hero

    func body(content: Content) -> some View {
        content
            .padding(.leading, FPCardMetrics.semanticContentLeadingReserve)
            .padding(padding)
            .background(
                ZStack(alignment: .leading) {
                    FPGlassLayer(
                        role: .data,
                        cornerRadius: radius,
                        tint: status.primary,
                        isSelected: true,
                        intensity: 1.02
                    )

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    status.softBackground.opacity(0.46),
                                    FPColor.card.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Capsule()
                        .fill(status.primary)
                        .frame(width: FPCardMetrics.semanticStripWidth)
                        .padding(.vertical, FPCardMetrics.semanticStripVerticalInset)
                        .padding(.leading, FPCardMetrics.semanticStripLeadingInset)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(status.border, lineWidth: 1)
            )
            .shadow(color: status.primary.opacity(0.06), radius: 22, x: 0, y: 12)
    }
}

struct FPInsetCardModifier: ViewModifier {
    var status: FPStatus = .neutral
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, FPSpacing.lg)
            .padding(.vertical, FPSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous)
                    .fill(isSelected ? status.softBackground.opacity(0.32) : FPColor.cardSoft.opacity(0.30))
                FPGlassLayer(
                    role: .control,
                    cornerRadius: FPRadius.large,
                    tint: status.primary,
                    isSelected: isSelected,
                    intensity: 0.78
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous)
                    .stroke(isSelected ? status.border : FPColor.borderSoft, lineWidth: 1)
            )
    }
}

extension View {
    func fpCard(
        padding: CGFloat = FPCardMetrics.defaultPadding,
        radius: CGFloat = FPRadius.card,
        background: Color = FPColor.card,
        border: Color = FPColor.borderDefault
    ) -> some View {
        modifier(FPCardModifier(padding: padding, radius: radius, background: background, border: border))
    }

    func fpSemanticCard(
        status: FPStatus,
        padding: CGFloat = FPCardMetrics.heroPadding,
        radius: CGFloat = FPRadius.hero
    ) -> some View {
        modifier(FPSemanticCardModifier(status: status, padding: padding, radius: radius))
    }

    func fpInsetCard(status: FPStatus = .neutral, isSelected: Bool = false) -> some View {
        modifier(FPInsetCardModifier(status: status, isSelected: isSelected))
    }
}

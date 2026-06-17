import SwiftUI

enum FPGlassLayerRole: Equatable {
    case data
    case control
    case badge
    case button
    case hero
    case stage
    case menu
}

struct FPGlassLayer: View {
    var role: FPGlassLayerRole = .control
    var cornerRadius: CGFloat = FPRadius.large
    var tint: Color = FPColor.focus500
    var isPressed = false
    var isSelected = false
    var intensity: Double = 1
    var motionPhase: CGFloat = 0.5
    var motionStrength: Double = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape
                .fill(baseGradient)

            if materialOpacity > 0 {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(materialOpacity)
            }

            if tintOverlayOpacity > 0 {
                shape
                    .fill(tintGradient)
                    .opacity(tintOverlayOpacity)
            }

            shape
                .fill(specularGradient)
                .opacity(specularOpacity)

            if motionStrength > 0 {
                FPLiquidGlassSweep(
                    cornerRadius: cornerRadius,
                    tint: tint,
                    phase: motionPhase,
                    strength: motionStrength * normalizedIntensity
                )
            }
        }
        .overlay {
            shape
                .strokeBorder(rimGradient, lineWidth: rimWidth)
        }
        .overlay(alignment: .topLeading) {
            shape
                .stroke(Color.white.opacity(0.24 * normalizedIntensity), lineWidth: 0.7)
                .padding(1)
        }
        .overlay(alignment: .bottomTrailing) {
            shape
                .stroke(tint.opacity(bottomEdgeOpacity), lineWidth: 0.8)
                .padding(1)
        }
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        .modifier(FPConditionalCompositingGroup(enabled: motionStrength > 0))
        .opacity(isPressed ? 0.88 : 1)
    }

    private var normalizedIntensity: Double {
        max(0, min(1.4, intensity))
    }

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(baseTopOpacity),
                Color.white.opacity(baseMiddleOpacity),
                FPColor.cardSoft.opacity(baseBottomOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var tintGradient: LinearGradient {
        LinearGradient(
            colors: [
                tint.opacity(0.48),
                tint.opacity(0.12),
                Color.white.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var specularGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.82),
                Color.white.opacity(0.24),
                Color.white.opacity(0.02),
                tint.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var rimGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(rimHighlightOpacity),
                tint.opacity(rimTintOpacity),
                FPColor.borderStrong.opacity(rimShadowOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var baseTopOpacity: Double {
        switch role {
        case .data:
            return 0.93
        case .control:
            return 0.66
        case .badge:
            return isSelected ? 0.72 : 0.54
        case .button:
            return isSelected ? 0.78 : 0.62
        case .hero:
            return 0.82
        case .stage:
            return 0.70
        case .menu:
            return 0.76
        }
    }

    private var baseMiddleOpacity: Double {
        switch role {
        case .data:
            return 0.82
        case .control:
            return 0.42
        case .badge:
            return isSelected ? 0.44 : 0.28
        case .button:
            return isSelected ? 0.48 : 0.34
        case .hero:
            return 0.60
        case .stage:
            return 0.42
        case .menu:
            return 0.50
        }
    }

    private var baseBottomOpacity: Double {
        switch role {
        case .data:
            return 0.78
        case .control:
            return 0.30
        case .badge:
            return 0.22
        case .button:
            return isSelected ? 0.34 : 0.24
        case .hero:
            return 0.42
        case .stage:
            return 0.28
        case .menu:
            return 0.42
        }
    }

    private var materialOpacity: Double {
        let base: Double
        switch role {
        case .data:
            base = 0.04
        case .control:
            base = 0.18
        case .badge:
            base = 0
        case .button:
            base = 0.12
        case .hero:
            base = 0.24
        case .stage:
            base = 0.30
        case .menu:
            base = 0.42
        }
        return base * normalizedIntensity
    }

    private var tintOverlayOpacity: Double {
        let base: Double
        switch role {
        case .data:
            base = isSelected ? 0.08 : 0.04
        case .control:
            base = isSelected ? 0.18 : 0.08
        case .badge:
            base = isSelected ? 0.22 : 0.06
        case .button:
            base = isSelected ? 0.24 : 0.10
        case .hero:
            base = 0.18
        case .stage:
            base = 0.20
        case .menu:
            base = 0.12
        }
        return base * normalizedIntensity
    }

    private var specularOpacity: Double {
        switch role {
        case .data:
            return 0.34 * normalizedIntensity
        case .control, .badge, .button:
            return 0.58 * normalizedIntensity
        case .hero:
            return 0.50 * normalizedIntensity
        case .stage:
            return 0.42 * normalizedIntensity
        case .menu:
            return 0.62 * normalizedIntensity
        }
    }

    private var rimWidth: CGFloat {
        switch role {
        case .badge:
            return 0.9
        case .button, .control:
            return 1
        case .stage, .hero, .menu:
            return 1.2
        case .data:
            return 1
        }
    }

    private var rimHighlightOpacity: Double {
        switch role {
        case .data:
            return 0.64
        case .menu:
            return 0.76
        default:
            return 0.70
        }
    }

    private var rimTintOpacity: Double {
        switch role {
        case .data:
            return 0.16
        case .stage:
            return 0.34
        case .hero:
            return 0.28
        default:
            return isSelected ? 0.32 : 0.22
        }
    }

    private var rimShadowOpacity: Double {
        switch role {
        case .data:
            return 0.58
        case .menu:
            return 0.42
        default:
            return 0.34
        }
    }

    private var bottomEdgeOpacity: Double {
        switch role {
        case .data:
            return 0.04
        case .stage:
            return 0.20
        case .menu:
            return 0.10
        default:
            return 0.08
        }
    }

    private var shadowColor: Color {
        switch role {
        case .data:
            return Color.black.opacity(0.045)
        case .stage:
            return tint.opacity(0.18)
        case .menu:
            return Color.black.opacity(0.14)
        default:
            return tint.opacity(isSelected ? 0.13 : 0.08)
        }
    }

    private var shadowRadius: CGFloat {
        switch role {
        case .badge:
            return 4
        case .button:
            return isPressed ? 4 : 9
        case .control:
            return 10
        case .data:
            return 18
        case .hero:
            return 26
        case .stage:
            return 24
        case .menu:
            return 28
        }
    }

    private var shadowY: CGFloat {
        switch role {
        case .badge:
            return 1
        case .button:
            return isPressed ? 2 : 5
        case .control:
            return 6
        case .data:
            return 10
        case .hero, .stage:
            return 14
        case .menu:
            return 18
        }
    }
}

private struct FPConditionalCompositingGroup: ViewModifier {
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.compositingGroup()
        } else {
            content
        }
    }
}

private struct FPLiquidGlassSweep: View {
    var cornerRadius: CGFloat
    var tint: Color
    var phase: CGFloat
    var strength: Double

    var body: some View {
        GeometryReader { proxy in
            let bandWidth = max(42, proxy.size.width * 0.28)
            let bandHeight = max(proxy.size.height * 2.2, 120)
            let travel = proxy.size.width + proxy.size.height + bandWidth * 2
            let xOffset = (phase - 0.5) * travel

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.58 * strength),
                            tint.opacity(0.22 * strength),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: bandWidth, height: bandHeight)
                .rotationEffect(.degrees(-18))
                .offset(x: xOffset, y: -proxy.size.height * 0.32)
                .blendMode(.screen)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}

extension View {
    func fpGlassBackground(
        role: FPGlassLayerRole = .control,
        cornerRadius: CGFloat = FPRadius.large,
        tint: Color = FPColor.focus500,
        isPressed: Bool = false,
        isSelected: Bool = false,
        intensity: Double = 1,
        motionPhase: CGFloat = 0.5,
        motionStrength: Double = 0
    ) -> some View {
        background {
            FPGlassLayer(
                role: role,
                cornerRadius: cornerRadius,
                tint: tint,
                isPressed: isPressed,
                isSelected: isSelected,
                intensity: intensity,
                motionPhase: motionPhase,
                motionStrength: motionStrength
            )
        }
    }
}

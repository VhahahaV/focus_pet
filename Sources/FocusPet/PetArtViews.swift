import FocusPetCore
import SwiftUI

struct PetFigureView: View {
    var state: UserState
    var animated: Bool

    @State private var breathe = false
    @State private var wiggle = false

    private var style: PetMoodStyle {
        PetMoodStyle(state: state)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let unit = size / 200

            ZStack {
                PetGlowView(style: style)
                    .frame(width: 174 * unit, height: 154 * unit)
                    .offset(x: 4 * unit, y: 16 * unit)

                Ellipse()
                    .fill(.black.opacity(0.16))
                    .frame(width: 128 * unit, height: 18 * unit)
                    .blur(radius: 2 * unit)
                    .offset(x: 2 * unit, y: 76 * unit)

                DinoTailShape()
                    .fill(style.tail)
                    .overlay {
                        DinoTailShape()
                            .stroke(style.line.opacity(0.22), lineWidth: 2 * unit)
                    }
                    .frame(width: 72 * unit, height: 60 * unit)
                    .rotationEffect(.degrees(animated && wiggle ? 8 : -4), anchor: .trailing)
                    .offset(x: -56 * unit, y: 23 * unit)

                DinoBodyView(style: style, unit: unit)
                    .frame(width: 112 * unit, height: 118 * unit)
                    .offset(x: -6 * unit, y: 25 * unit)

                DinoHeadView(style: style, state: state, animated: animated, wiggle: wiggle, unit: unit)
                    .frame(width: 118 * unit, height: 106 * unit)
                    .offset(x: 22 * unit, y: -30 * unit)

                DinoSpinesView(style: style, unit: unit)
                    .frame(width: 88 * unit, height: 48 * unit)
                    .rotationEffect(.degrees(-7))
                    .offset(x: -28 * unit, y: -35 * unit)

                DinoAccessoryView(state: state, style: style, animated: animated, wiggle: wiggle, unit: unit)
                    .frame(width: 82 * unit, height: 58 * unit)
                    .offset(style.accessoryOffset(unit: unit, wiggle: wiggle))
            }
            .frame(width: size, height: size)
            .scaleEffect(animated && breathe ? 1.018 : 0.992)
            .rotationEffect(.degrees(style.bodyTilt(wiggle: wiggle)))
            .animation(animated ? .easeInOut(duration: 1.45).repeatForever(autoreverses: true) : .default, value: breathe)
            .animation(animated ? .easeInOut(duration: 0.86).repeatForever(autoreverses: true) : .default, value: wiggle)
            .onAppear {
                breathe = true
                wiggle = true
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text("Focus Pet \(state.title)"))
    }
}

struct PetSpeechBubble: View {
    var message: String
    var compact = true

    var body: some View {
        Text(message)
            .font(compact ? .caption.weight(.medium) : .callout.weight(.medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(compact ? 3 : 2)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, compact ? 8 : 10)
            .frame(maxWidth: compact ? 205 : 250)
            .background {
                SpeechBubbleShape()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
            }
    }
}

private struct DinoHeadView: View {
    var style: PetMoodStyle
    var state: UserState
    var animated: Bool
    var wiggle: Bool
    var unit: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42 * unit, style: .continuous)
                .fill(style.body)
                .overlay(alignment: .bottomTrailing) {
                    Ellipse()
                        .fill(style.belly.opacity(0.92))
                        .frame(width: 58 * unit, height: 34 * unit)
                        .offset(x: -6 * unit, y: -8 * unit)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 42 * unit, style: .continuous)
                        .stroke(style.line.opacity(0.2), lineWidth: 2 * unit)
                }
                .shadow(color: style.shadow, radius: 16 * unit, y: 9 * unit)

            HStack(spacing: 30 * unit) {
                DinoEyeView(style: style, sleeping: state == .away, unit: unit)
                DinoEyeView(style: style, sleeping: state == .away, unit: unit)
            }
            .offset(x: 10 * unit, y: -10 * unit)

            Circle()
                .fill(style.cheek)
                .frame(width: 12 * unit, height: 12 * unit)
                .offset(x: -21 * unit, y: 11 * unit)
                .opacity(style.showCheeks ? 1 : 0)

            Circle()
                .fill(style.cheek)
                .frame(width: 12 * unit, height: 12 * unit)
                .offset(x: 48 * unit, y: 10 * unit)
                .opacity(style.showCheeks ? 1 : 0)

            DinoMouthView(style: style, unit: unit)
                .frame(width: 42 * unit, height: 28 * unit)
                .offset(x: 15 * unit, y: 17 * unit)

            if state == .distracted {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 18 * unit, weight: .heavy))
                    .foregroundStyle(style.accent)
                    .offset(x: 57 * unit, y: -43 * unit)
                    .scaleEffect(animated && wiggle ? 1.18 : 0.92)
            }
        }
    }
}

private struct DinoBodyView: View {
    var style: PetMoodStyle
    var unit: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44 * unit, style: .continuous)
                .fill(style.body)
                .overlay(alignment: .bottom) {
                    Ellipse()
                        .fill(style.belly)
                        .frame(width: 68 * unit, height: 78 * unit)
                        .offset(y: -4 * unit)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 44 * unit, style: .continuous)
                        .stroke(style.line.opacity(0.2), lineWidth: 2 * unit)
                }

            DinoArmShape()
                .stroke(style.line.opacity(0.65), style: StrokeStyle(lineWidth: 8 * unit, lineCap: .round))
                .frame(width: 40 * unit, height: 42 * unit)
                .offset(x: -42 * unit, y: -3 * unit)

            DinoArmShape()
                .stroke(style.line.opacity(0.65), style: StrokeStyle(lineWidth: 8 * unit, lineCap: .round))
                .frame(width: 40 * unit, height: 42 * unit)
                .scaleEffect(x: -1)
                .offset(x: 40 * unit, y: -3 * unit)

            HStack(spacing: 30 * unit) {
                DinoFootView(style: style, unit: unit)
                DinoFootView(style: style, unit: unit)
            }
            .offset(y: 57 * unit)
        }
    }
}

private struct DinoEyeView: View {
    var style: PetMoodStyle
    var sleeping: Bool
    var unit: CGFloat

    var body: some View {
        ZStack {
            if sleeping {
                Capsule()
                    .fill(style.line.opacity(0.78))
                    .frame(width: 24 * unit, height: 4.5 * unit)
                    .rotationEffect(.degrees(-4))
            } else {
                Circle()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 24 * unit, height: 25 * unit)
                    .overlay {
                        Circle()
                            .fill(style.line)
                            .frame(width: 9.5 * unit, height: 9.5 * unit)
                            .offset(style.eyeOffset(unit: unit))
                    }
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(Color.white.opacity(0.86))
                            .frame(width: 5 * unit, height: 5 * unit)
                            .offset(x: 6 * unit, y: 5 * unit)
                    }
            }
        }
    }
}

private struct DinoMouthView: View {
    var style: PetMoodStyle
    var unit: CGFloat

    var body: some View {
        switch style.mouth {
        case .softSmile:
            SmileShape(depth: 0.42)
                .stroke(style.line.opacity(0.78), style: StrokeStyle(lineWidth: 3.4 * unit, lineCap: .round))
        case .smallConcern:
            SmileShape(depth: -0.16)
                .stroke(style.line.opacity(0.78), style: StrokeStyle(lineWidth: 3.4 * unit, lineCap: .round))
        case .open:
            Ellipse()
                .fill(style.line.opacity(0.82))
                .frame(width: 15 * unit, height: 20 * unit)
                .overlay(alignment: .bottom) {
                    Ellipse()
                        .fill(style.cheek.opacity(0.9))
                        .frame(width: 10 * unit, height: 6 * unit)
                        .offset(y: -3 * unit)
                }
        case .sleep:
            Text("z")
                .font(.system(size: 18 * unit, weight: .heavy, design: .rounded))
                .foregroundStyle(style.line.opacity(0.74))
                .rotationEffect(.degrees(-8))
        }
    }
}

private struct DinoFootView: View {
    var style: PetMoodStyle
    var unit: CGFloat

    var body: some View {
        Capsule()
            .fill(style.foot)
            .frame(width: 36 * unit, height: 16 * unit)
            .overlay(alignment: .trailing) {
                HStack(spacing: 2 * unit) {
                    Circle().fill(style.line.opacity(0.5))
                    Circle().fill(style.line.opacity(0.5))
                }
                .frame(width: 12 * unit, height: 5 * unit)
                .offset(x: -5 * unit)
            }
    }
}

private struct DinoSpinesView: View {
    var style: PetMoodStyle
    var unit: CGFloat

    var body: some View {
        HStack(spacing: -1 * unit) {
            ForEach(0..<5, id: \.self) { index in
                TriangleShape()
                    .fill(index.isMultiple(of: 2) ? style.accent : style.secondaryAccent)
                    .frame(width: (15 + CGFloat(index % 2) * 4) * unit, height: (20 + CGFloat(index % 2) * 3) * unit)
                    .rotationEffect(.degrees(-10 + Double(index) * 2))
            }
        }
        .shadow(color: style.shadow.opacity(0.5), radius: 5 * unit, y: 2 * unit)
    }
}

private struct DinoAccessoryView: View {
    var state: UserState
    var style: PetMoodStyle
    var animated: Bool
    var wiggle: Bool
    var unit: CGFloat

    var body: some View {
        ZStack {
            switch state {
            case .focused:
                BookAccessory(style: style, unit: unit)
            case .distracted:
                TapAccessory(style: style, animated: animated, wiggle: wiggle, unit: unit)
            case .away:
                SleepAccessory(style: style, animated: animated, wiggle: wiggle, unit: unit)
            }
        }
    }
}

private struct BookAccessory: View {
    var style: PetMoodStyle
    var unit: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
                .fill(style.accessoryFill)
                .frame(width: 58 * unit, height: 42 * unit)
                .rotationEffect(.degrees(-5))
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 2 * unit)
                }
                .shadow(color: .black.opacity(0.13), radius: 5 * unit, y: 3 * unit)

            Image(systemName: "book.closed.fill")
                .font(.system(size: 20 * unit, weight: .semibold))
                .foregroundStyle(style.line.opacity(0.68))
        }
    }
}

private struct TapAccessory: View {
    var style: PetMoodStyle
    var animated: Bool
    var wiggle: Bool
    var unit: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(style.accent.opacity(0.65), lineWidth: 2.4 * unit)
                .frame(width: animated && wiggle ? 42 * unit : 30 * unit)
                .opacity(animated && wiggle ? 0.25 : 0.75)

            Image(systemName: "hand.tap.fill")
                .font(.system(size: 28 * unit, weight: .bold))
                .foregroundStyle(style.accent)
                .rotationEffect(.degrees(animated && wiggle ? -12 : 6))
        }
    }
}

private struct NeckAccessory: View {
    var style: PetMoodStyle
    var unit: CGFloat

    var body: some View {
        ZStack {
            Capsule()
                .fill(style.accessoryFill)
                .frame(width: 62 * unit, height: 23 * unit)
                .rotationEffect(.degrees(6))
                .shadow(color: .black.opacity(0.12), radius: 4 * unit, y: 2 * unit)

            Image(systemName: "arrow.up")
                .font(.system(size: 24 * unit, weight: .heavy))
                .foregroundStyle(style.line.opacity(0.72))
                .offset(y: -18 * unit)
        }
    }
}

private struct SleepAccessory: View {
    var style: PetMoodStyle
    var animated: Bool
    var wiggle: Bool
    var unit: CGFloat

    var body: some View {
        HStack(spacing: 2 * unit) {
            Text("Z")
                .font(.system(size: 17 * unit, weight: .heavy, design: .rounded))
            Text("z")
                .font(.system(size: 13 * unit, weight: .heavy, design: .rounded))
                .offset(y: animated && wiggle ? -9 * unit : -3 * unit)
        }
        .foregroundStyle(style.accent)
        .offset(x: 20 * unit, y: -20 * unit)
    }
}

private struct EntertainmentAccessory: View {
    var style: PetMoodStyle
    var animated: Bool
    var wiggle: Bool
    var unit: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9 * unit, style: .continuous)
                .fill(style.accessoryFill)
                .frame(width: 44 * unit, height: 42 * unit)
                .rotationEffect(.degrees(animated && wiggle ? 7 : -5))

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 23 * unit, weight: .bold))
                .foregroundStyle(style.line.opacity(0.72))
        }
    }
}

private struct RestAccessory: View {
    var style: PetMoodStyle
    var unit: CGFloat

    var body: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 28 * unit, weight: .bold))
            .foregroundStyle(style.accessoryFill)
            .shadow(color: .black.opacity(0.12), radius: 4 * unit, y: 2 * unit)
    }
}

private struct SparkAccessory: View {
    var style: PetMoodStyle
    var animated: Bool
    var wiggle: Bool
    var unit: CGFloat

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: animated && wiggle ? 30 * unit : 24 * unit, weight: .bold))
            .foregroundStyle(style.accent)
    }
}

private struct PetGlowView: View {
    var style: PetMoodStyle

    var body: some View {
        ZStack {
            Ellipse()
                .fill(style.accent.opacity(0.24))
                .blur(radius: 16)
            Ellipse()
                .fill(style.secondaryAccent.opacity(0.16))
                .blur(radius: 8)
                .scaleEffect(0.72)
        }
    }
}

private struct PetMoodStyle {
    var state: UserState

    var body: Color {
        switch state {
        case .focused:
            Color(red: 0.38, green: 0.78, blue: 0.56)
        case .distracted:
            Color(red: 0.96, green: 0.48, blue: 0.36)
        case .away:
            Color(red: 0.50, green: 0.56, blue: 0.68)
        }
    }

    var belly: Color {
        switch state {
        case .away:
            Color(red: 0.75, green: 0.78, blue: 0.86)
        case .distracted:
            Color(red: 1.00, green: 0.73, blue: 0.58)
        case .focused:
            Color(red: 0.94, green: 0.96, blue: 0.74)
        }
    }

    var tail: Color {
        body.opacity(state == .away ? 0.82 : 0.95)
    }

    var foot: Color {
        body.opacity(0.72)
    }

    var line: Color {
        Color(red: 0.14, green: 0.18, blue: 0.20)
    }

    var accent: Color {
        switch state {
        case .focused:
            Color(red: 0.12, green: 0.58, blue: 0.42)
        case .distracted:
            Color(red: 0.78, green: 0.18, blue: 0.22)
        case .away:
            Color(red: 0.34, green: 0.39, blue: 0.58)
        }
    }

    var secondaryAccent: Color {
        switch state {
        case .distracted:
            Color(red: 1.00, green: 0.78, blue: 0.26)
        case .away:
            Color(red: 0.74, green: 0.78, blue: 0.90)
        case .focused:
            Color(red: 0.91, green: 0.95, blue: 0.42)
        }
    }

    var cheek: Color {
        Color(red: 1.0, green: 0.45, blue: 0.48).opacity(state == .away ? 0 : 0.76)
    }

    var shadow: Color {
        accent.opacity(0.26)
    }

    var accessoryFill: Color {
        switch state {
        case .focused:
            Color(red: 0.98, green: 0.86, blue: 0.42)
        case .distracted:
            Color(red: 1.0, green: 0.84, blue: 0.32)
        case .away:
            Color(red: 0.93, green: 0.96, blue: 0.78)
        }
    }

    var mouth: PetMouth {
        switch state {
        case .focused:
            .softSmile
        case .distracted:
            .smallConcern
        case .away:
            .sleep
        }
    }

    var showCheeks: Bool {
        state != .away
    }

    func eyeOffset(unit: CGFloat) -> CGSize {
        switch state {
        case .distracted:
            CGSize(width: 3.8 * unit, height: -1.5 * unit)
        case .focused, .away:
            CGSize(width: 0, height: 0)
        }
    }

    func accessoryOffset(unit: CGFloat, wiggle: Bool) -> CGSize {
        switch state {
        case .focused:
            CGSize(width: -5 * unit, height: 36 * unit)
        case .distracted:
            CGSize(width: 58 * unit, height: 4 * unit + (wiggle ? -4 * unit : 2 * unit))
        case .away:
            CGSize(width: 34 * unit, height: -42 * unit)
        }
    }

    func bodyTilt(wiggle: Bool) -> Double {
        switch state {
        case .distracted:
            return wiggle ? -2.5 : 2
        case .focused, .away:
            return 0
        }
    }
}

private enum PetMouth {
    case softSmile
    case smallConcern
    case open
    case sleep
}

private struct DinoTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY * 0.78))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.12),
            control1: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY - rect.height * 0.03)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY * 0.82),
            control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY * 0.72),
            control2: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct DinoArmShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.14))
        path.addCurve(
            to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.maxY * 0.82),
            control1: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.height * 0.35),
            control2: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.height * 0.72)
        )
        return path
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SmileShape: Shape {
    var depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX + rect.width * 0.18, y: rect.midY)
        let end = CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.midY)
        let control = CGPoint(x: rect.midX, y: rect.midY + rect.height * depth)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

private struct SpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: rect)
        let tail = Path { tailPath in
            let x = rect.midX
            tailPath.move(to: CGPoint(x: x - 10, y: rect.minY + 2))
            tailPath.addLine(to: CGPoint(x: x, y: rect.minY - 9))
            tailPath.addLine(to: CGPoint(x: x + 10, y: rect.minY + 2))
            tailPath.closeSubpath()
        }
        path.addPath(tail)
        return path
    }
}

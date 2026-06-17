import FocusPetCore
import SwiftUI

public struct FocusPetCurrentStatusWidgetView: View {
    public var snapshot: FocusPetWidgetSnapshot

    public init(snapshot: FocusPetWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetLabel("当前状态", tint: stateTint)
                .padding(.bottom, 15)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stateHeadline)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(stateTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)

                Text("已稳定 \(FocusPetWidgetFormatters.shortDuration(snapshot.stableDurationSeconds))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(FocusPetWidgetPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 14)

            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    microItem(symbol: "keyboard", text: "\(FocusPetFormatters.compactCount(snapshot.keyboardCount)) 键")
                    microItem(symbol: "cursorarrow.click", text: "\(FocusPetFormatters.compactCount(snapshot.pointerCount)) 鼠")
                }
                durationStrip
            }
        }
        .padding(12)
        .frame(width: 170, height: 170, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            stateTint.opacity(0.16),
                            Color.white.opacity(0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(stateTint.opacity(0.16))
                        .frame(width: 72, height: 72)
                        .blur(radius: 4)
                        .offset(x: 16, y: -18)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.64), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
    }

    private var stateTint: Color {
        FocusPetWidgetPalette.color(for: snapshot.currentState)
    }

    private var stateHeadline: String {
        switch snapshot.currentState {
        case .focus: "专注中"
        case .distracted: "走神中"
        case .breakTime: "休息中"
        case .away: "暂离中"
        }
    }

    private var durationStrip: some View {
        HStack(spacing: 8) {
            durationChip(title: "专", seconds: snapshot.focusSeconds, tint: FocusPetWidgetPalette.focus)
            durationChip(title: "走", seconds: snapshot.distractedSeconds, tint: FocusPetWidgetPalette.distracted)
            durationChip(title: "休", seconds: snapshot.breakSeconds, tint: FocusPetWidgetPalette.rest)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.54), lineWidth: 1)
        }
    }

    private func microItem(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FocusPetWidgetPalette.focusStrong)
                .frame(width: 13)
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(FocusPetWidgetPalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.54), lineWidth: 1)
        }
    }

    private func durationChip(title: String, seconds: Int, tint: Color) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .foregroundStyle(tint)
            Text(FocusPetWidgetFormatters.microDuration(seconds))
                .foregroundStyle(FocusPetWidgetPalette.secondaryText)
        }
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.70)
        .frame(maxWidth: .infinity)
    }
}

public struct FocusPetRecentRhythmWidgetView: View {
    public var snapshot: FocusPetWidgetSnapshot
    private var showsWindowSwitcher: Bool
    @State private var activeWindowHours: Int

    public init(snapshot: FocusPetWidgetSnapshot, selectedWindowHours: Int = 4, showsWindowSwitcher: Bool = true) {
        self.snapshot = snapshot
        self.showsWindowSwitcher = showsWindowSwitcher
        _activeWindowHours = State(initialValue: selectedWindowHours)
    }

    public var body: some View {
        let rhythm = snapshot.rhythm(windowHours: activeWindowHours) ?? FocusPetWidgetRhythmSnapshot.empty(hours: activeWindowHours)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            FocusPetWidgetPalette.focus.opacity(0.12),
                            Color.white.opacity(0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    widgetLabel("最近节奏", tint: FocusPetWidgetPalette.focus)
                    Spacer()
                    rhythmSwitch
                }
                .padding(.bottom, 14)

                HStack(alignment: .center, spacing: 14) {
                    rhythmDonut(rhythm)
                        .frame(width: 92, height: 92)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("近 \(rhythm.windowHours) 小时\(rhythmCaption(rhythm))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(FocusPetWidgetPalette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                            rhythmMetric("专注", seconds: rhythm.focusSeconds)
                            rhythmMetric("走神", seconds: rhythm.distractedSeconds)
                            rhythmMetric("休息", seconds: rhythm.breakSeconds)
                            rhythmMetric("暂离", seconds: rhythm.awaySeconds)
                        }

                        rhythmTimeline(rhythm)
                            .frame(height: 10)
                            .padding(.top, 1)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 360, height: 170)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.64), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
    }

    @ViewBuilder
    private var rhythmSwitch: some View {
        if showsWindowSwitcher {
            HStack(spacing: 2) {
                ForEach(FocusPetWidgetSnapshotBuilder.supportedRecentRhythmHours, id: \.self) { hours in
                    Button {
                        activeWindowHours = hours
                    } label: {
                        rhythmWindowLabel(hours: hours, isActive: hours == activeWindowHours)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.54), lineWidth: 1)
            }
        } else {
            rhythmWindowLabel(hours: activeWindowHours, isActive: true)
                .padding(3)
                .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.54), lineWidth: 1)
                }
        }
    }

    private func rhythmWindowLabel(hours: Int, isActive: Bool) -> some View {
        Text("\(hours)h")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(isActive ? Color.white : FocusPetWidgetPalette.secondaryText)
            .frame(width: 32, height: 19)
            .background(
                isActive ? FocusPetWidgetPalette.focusStrong : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }

    private func rhythmCaption(_ rhythm: FocusPetWidgetRhythmSnapshot) -> String {
        if rhythm.focusRatio >= 0.7 { return "稳定" }
        if rhythm.focusRatio >= 0.5 { return "有波动" }
        return "偏离较多"
    }

    private func rhythmDonut(_ rhythm: FocusPetWidgetRhythmSnapshot) -> some View {
        ZStack {
            Circle()
                .stroke(FocusPetWidgetPalette.away.opacity(0.24), lineWidth: 17)
            donutArc(ratio: ratio(rhythm.focusSeconds, total: rhythm.totalSeconds), start: 0, color: FocusPetWidgetPalette.focus)
            donutArc(ratio: ratio(rhythm.distractedSeconds, total: rhythm.totalSeconds), start: ratio(rhythm.focusSeconds, total: rhythm.totalSeconds), color: FocusPetWidgetPalette.distracted)
            donutArc(
                ratio: ratio(rhythm.breakSeconds, total: rhythm.totalSeconds),
                start: ratio(rhythm.focusSeconds + rhythm.distractedSeconds, total: rhythm.totalSeconds),
                color: FocusPetWidgetPalette.rest
            )
            Text(FocusPetFormatters.percentage(rhythm.focusRatio))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(FocusPetWidgetPalette.focusStrong)
        }
    }

    private func donutArc(ratio: Double, start: Double, color: Color) -> some View {
        Circle()
            .trim(from: start, to: min(1, start + max(0, ratio)))
            .stroke(color, style: StrokeStyle(lineWidth: 17, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }

    private func rhythmMetric(_ title: String, seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(FocusPetWidgetFormatters.shortDuration(seconds))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(FocusPetWidgetPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(FocusPetWidgetPalette.secondaryText)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.48), lineWidth: 1)
        }
    }

    private func rhythmTimeline(_ rhythm: FocusPetWidgetRhythmSnapshot) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(FocusPetWidgetPalette.away.opacity(0.22))
                ForEach(rhythm.timelineRanges) { range in
                    Capsule()
                        .fill(FocusPetWidgetPalette.color(for: range.state))
                        .frame(width: max(3, proxy.size.width * range.width), height: proxy.size.height)
                        .offset(x: proxy.size.width * range.startProgress)
                }
            }
        }
        .clipShape(Capsule())
    }

    private func ratio(_ seconds: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(seconds) / Double(total)
    }
}

private func widgetLabel(_ title: String, tint: Color) -> some View {
    HStack(spacing: 5) {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .shadow(color: tint.opacity(0.24), radius: 0, x: 0, y: 0)
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(FocusPetWidgetPalette.secondaryText)
    }
}

private enum FocusPetWidgetPalette {
    static let text = Color(red: 0.14, green: 0.20, blue: 0.28)
    static let secondaryText = Color(red: 0.37, green: 0.44, blue: 0.53)
    static let focus = Color(red: 0.35, green: 0.65, blue: 0.97)
    static let focusStrong = Color(red: 0.18, green: 0.49, blue: 0.86)
    static let distracted = Color(red: 0.95, green: 0.70, blue: 0.36)
    static let distractedStrong = Color(red: 0.79, green: 0.52, blue: 0.13)
    static let rest = Color(red: 0.41, green: 0.75, blue: 0.55)
    static let away = Color(red: 0.60, green: 0.66, blue: 0.72)

    static func color(for state: FocusPetCore.FocusState) -> Color {
        switch state {
        case .focus: focus
        case .distracted: distracted
        case .breakTime: rest
        case .away: away
        }
    }
}

private enum FocusPetWidgetFormatters {
    static func shortDuration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 {
            return "\(seconds)秒"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)分"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        if remaining == 0 {
            return "\(hours)小时"
        }
        return "\(hours)小时\(remaining)分"
    }

    static func microDuration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        if remaining == 0 {
            return "\(hours)h"
        }
        return String(format: "%dh%02d", hours, remaining)
    }
}

private extension FocusPetWidgetRhythmSnapshot {
    static func empty(hours: Int) -> FocusPetWidgetRhythmSnapshot {
        FocusPetWidgetRhythmSnapshot(
            windowHours: hours,
            focusSeconds: 0,
            distractedSeconds: 0,
            breakSeconds: 0,
            awaySeconds: 0,
            keyboardCount: 0,
            pointerCount: 0,
            contextSwitchCount: 0,
            timelineRanges: []
        )
    }
}

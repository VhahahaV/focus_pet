import FocusPetWidgets
import SwiftUI
import WidgetKit

private enum FocusPetWidgetKind {
    static let currentStatus = "com.focuspet.FocusPet.widgets.current-status"
    static let recentRhythm = "com.focuspet.FocusPet.widgets.recent-rhythm"
}

private struct FocusPetWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: FocusPetWidgetSnapshot
}

private struct FocusPetWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusPetWidgetEntry {
        FocusPetWidgetEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusPetWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusPetWidgetEntry>) -> Void) {
        let currentEntry = entry()
        let nextRefresh = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [currentEntry], policy: .after(nextRefresh)))
    }

    private func entry(now: Date = Date()) -> FocusPetWidgetEntry {
        let snapshot = FocusPetWidgetSnapshotStore().load() ?? .sample(now: now)
        return FocusPetWidgetEntry(date: now, snapshot: snapshot)
    }
}

private struct FocusPetCurrentStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FocusPetWidgetKind.currentStatus, provider: FocusPetWidgetProvider()) { entry in
            FocusPetCurrentStatusWidgetView(snapshot: entry.snapshot)
                .focusPetWidgetContainerBackground()
        }
        .configurationDisplayName("Focus Pet 当前状态")
        .description("查看当前专注状态、稳定时长和今日输入节奏。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct FocusPetRecentRhythmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FocusPetWidgetKind.recentRhythm, provider: FocusPetWidgetProvider()) { entry in
            FocusPetRecentRhythmWidgetView(
                snapshot: entry.snapshot,
                selectedWindowHours: 4,
                showsWindowSwitcher: false
            )
            .focusPetWidgetContainerBackground()
        }
        .configurationDisplayName("Focus Pet 最近节奏")
        .description("查看最近四小时的专注、走神、休息和暂离比例。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

@main
private struct FocusPetWidgetBundle: WidgetBundle {
    var body: some Widget {
        FocusPetCurrentStatusWidget()
        FocusPetRecentRhythmWidget()
    }
}

private extension View {
    func focusPetWidgetContainerBackground() -> some View {
        containerBackground(for: .widget) {
            Color.clear
        }
    }
}

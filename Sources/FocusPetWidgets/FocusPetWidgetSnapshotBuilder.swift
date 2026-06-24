import FocusPetCore
import Foundation

public enum FocusPetWidgetSnapshotBuilder {
    public static let supportedRecentRhythmHours = [4, 8, 12]

    public static func makeSnapshot(
        now: Date = Date(),
        currentDecision: StateDecision,
        currentSnapshot: ActivitySnapshot,
        summary: DailySummary,
        inputActivity: [InputActivityBucket],
        stateSegments: [StateSegment],
        appUsage: [AppUsageSegment],
        reminderPauseUntil: Date?,
        petIntentTitle: String,
        selectedPetPackID: String
    ) -> FocusPetWidgetSnapshot {
        let workload = InputWorkloadSummary(dayContaining: now, inputActivity: inputActivity)
        let rhythms = supportedRecentRhythmHours.map { hours in
            makeRhythm(
                hours: hours,
                now: now,
                stateSegments: stateSegments,
                appUsage: appUsage,
                inputActivity: inputActivity
            )
        }

        return FocusPetWidgetSnapshot(
            generatedAt: now,
            currentState: currentDecision.state,
            stableDurationSeconds: Int(currentDecision.stableDuration.rounded()),
            currentAppName: currentSnapshot.appName,
            currentCategory: currentSnapshot.category,
            focusSeconds: summary.focusSeconds,
            distractedSeconds: summary.distractedSeconds,
            breakSeconds: summary.breakSeconds,
            awaySeconds: summary.awaySeconds,
            keyboardCount: workload.estimatedTypedCharacters,
            pointerCount: workload.pointerActionCount,
            contextSwitchCount: workload.contextSwitchCount,
            recentRhythms: rhythms,
            reminderPauseUntil: reminderPauseUntil,
            petIntentTitle: petIntentTitle,
            selectedPetPackID: selectedPetPackID
        )
    }

    private static func makeRhythm(
        hours: Int,
        now: Date,
        stateSegments: [StateSegment],
        appUsage: [AppUsageSegment],
        inputActivity: [InputActivityBucket]
    ) -> FocusPetWidgetRhythmSnapshot {
        let timeline = InputTimelineSnapshot(
            windowSeconds: TimeInterval(hours * 60 * 60),
            stateSegments: stateSegments,
            appUsage: appUsage,
            inputActivity: inputActivity,
            now: now,
            includeAwayState: false,
            includeAppSegments: false
        )
        return FocusPetWidgetRhythmSnapshot(
            windowHours: hours,
            focusSeconds: timeline.stateDurations[.focus, default: 0],
            distractedSeconds: timeline.stateDurations[.distracted, default: 0],
            breakSeconds: timeline.stateDurations[.breakTime, default: 0],
            awaySeconds: timeline.stateDurations[.away, default: 0],
            keyboardCount: timeline.keyboardCount,
            pointerCount: timeline.pointerCount,
            contextSwitchCount: timeline.switchCount,
            timelineRanges: compactedRhythmRanges(from: timeline.stateRanges)
        )
    }

    private static func compactedRhythmRanges(
        from ranges: [InputTimelineStateRange]
    ) -> [FocusPetWidgetRhythmRange] {
        let visibleRanges = ranges.filter {
            $0.state != .away && $0.endProgress > $0.startProgress
        }
        let totalWidth = visibleRanges.reduce(0) { $0 + $1.width }
        guard totalWidth > 0 else { return [] }

        var cursor = 0.0
        var result: [FocusPetWidgetRhythmRange] = []
        for range in visibleRanges {
            let nextCursor = min(1, cursor + range.width / totalWidth)
            if let lastIndex = result.indices.last,
               result[lastIndex].state == range.state {
                result[lastIndex].endProgress = nextCursor
            } else {
                result.append(
                    FocusPetWidgetRhythmRange(
                        state: range.state,
                        startProgress: cursor,
                        endProgress: nextCursor
                    )
                )
            }
            cursor = nextCursor
        }

        if let lastIndex = result.indices.last {
            result[lastIndex].endProgress = 1
        }
        return result
    }
}

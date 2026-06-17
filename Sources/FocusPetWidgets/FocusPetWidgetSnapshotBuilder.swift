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
            includeAwayState: true,
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
            timelineRanges: timeline.stateRanges.map {
                FocusPetWidgetRhythmRange(
                    state: $0.state,
                    startProgress: $0.startProgress,
                    endProgress: $0.endProgress
                )
            }
        )
    }
}

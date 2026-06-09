import Darwin
import Foundation
import FocusPetCore

@main
enum FocusPetCoreChecks {
    static func main() {
        checkWorkAppWithScreenGazeBecomesFocused()
        checkNoFaceForLongEnoughBecomesAway()
        checkDownwardHeadForLongEnoughBecomesLookingDown()
        checkRuleTriggersAfterMatchingDurationAndOutsideCooldown()
        checkRuleDoesNotTriggerDuringCooldown()
        checkPausedDetectionSuppressesRules()
        checkDailyReportAggregatesStructuredStateEvents()
        print("FocusPetCoreChecks passed")
    }

    private static func checkWorkAppWithScreenGazeBecomesFocused() {
        let engine = StateFusionEngine()
        let observation = StateObservation(
            timestamp: Date(timeIntervalSince1970: 100),
            facePresent: true,
            gazeState: .screen,
            headPitchDegrees: 4,
            frontAppName: "Cursor",
            context: .work,
            lastInputSeconds: 8,
            stableDurationSeconds: 12
        )

        let state = engine.fuse(observation)

        expect(state.userState == .focused, "work screen gaze should become focused")
        expect(state.context == .work, "focused state should keep work context")
        expect(state.confidence > 0.8, "focused confidence should be high")
        expect(state.reason == ["front_app_is_work", "gaze_on_screen", "face_present"], "focused reason should be explainable")
    }

    private static func checkNoFaceForLongEnoughBecomesAway() {
        let engine = StateFusionEngine()
        let observation = StateObservation(
            timestamp: Date(timeIntervalSince1970: 140),
            facePresent: false,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: nil,
            context: .neutral,
            lastInputSeconds: 90,
            stableDurationSeconds: 20
        )

        let state = engine.fuse(observation)

        expect(state.userState == .away, "missing face over threshold should become away")
        expect(state.reason == ["face_missing_over_15s"], "away reason should be explainable")
    }

    private static func checkDownwardHeadForLongEnoughBecomesLookingDown() {
        let engine = StateFusionEngine()
        let observation = StateObservation(
            timestamp: Date(timeIntervalSince1970: 180),
            facePresent: true,
            gazeState: .down,
            headPitchDegrees: 31,
            frontAppName: "Preview",
            context: .work,
            lastInputSeconds: 16,
            stableDurationSeconds: 75
        )

        let state = engine.fuse(observation)

        expect(state.userState == .lookingDown, "downward head over threshold should become lookingDown")
        expect(state.reason == ["head_pitch_down_over_60s"], "lookingDown reason should be explainable")
    }

    private static func checkRuleTriggersAfterMatchingDurationAndOutsideCooldown() {
        let rule = FocusRule.workDistraction
        let state = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 1_000),
            userState: .offScreen,
            context: .work,
            confidence: 0.82,
            reason: ["gaze_off_screen_over_20s"],
            stableDurationSeconds: 32
        )

        let decisions = RuleEngine().evaluate(
            rules: [rule],
            state: state,
            now: Date(timeIntervalSince1970: 1_000),
            lastTriggeredAtByRuleID: [:],
            isPaused: false
        )

        expect(decisions.count == 1, "matching rule should trigger once")
        expect(decisions.first?.ruleID == rule.id, "decision should preserve rule id")
        expect(decisions.first?.action.message == "刚才可能走神了，要回到当前任务吗？", "decision should preserve action message")
    }

    private static func checkRuleDoesNotTriggerDuringCooldown() {
        let rule = FocusRule.workDistraction
        let state = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 1_120),
            userState: .possiblyDistracted,
            context: .work,
            confidence: 0.82,
            reason: ["gaze_off_screen_over_20s"],
            stableDurationSeconds: 48
        )

        let decisions = RuleEngine().evaluate(
            rules: [rule],
            state: state,
            now: Date(timeIntervalSince1970: 1_120),
            lastTriggeredAtByRuleID: [rule.id: Date(timeIntervalSince1970: 1_000)],
            isPaused: false
        )

        expect(decisions.isEmpty, "cooldown should suppress matching rule")
    }

    private static func checkPausedDetectionSuppressesRules() {
        let rule = FocusRule.postureReminder
        let state = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 2_000),
            userState: .lookingDown,
            context: .work,
            confidence: 0.9,
            reason: ["head_pitch_down_over_60s"],
            stableDurationSeconds: 180
        )

        let decisions = RuleEngine().evaluate(
            rules: [rule],
            state: state,
            now: Date(timeIntervalSince1970: 2_000),
            lastTriggeredAtByRuleID: [:],
            isPaused: true
        )

        expect(decisions.isEmpty, "paused detection should suppress all reminders")
    }

    private static func checkDailyReportAggregatesStructuredStateEvents() {
        let events = [
            StateEvent(
                id: "focus-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 1_800),
                userState: .focused,
                context: .work,
                confidence: 0.9,
                reason: ["gaze_on_screen"]
            ),
            StateEvent(
                id: "down-1",
                startTime: Date(timeIntervalSince1970: 1_800),
                endTime: Date(timeIntervalSince1970: 1_920),
                userState: .lookingDown,
                context: .work,
                confidence: 0.86,
                reason: ["head_pitch_down_over_60s"]
            ),
            StateEvent(
                id: "entertainment-1",
                startTime: Date(timeIntervalSince1970: 1_920),
                endTime: Date(timeIntervalSince1970: 2_520),
                userState: .entertainment,
                context: .entertainment,
                confidence: 0.92,
                reason: ["front_app_is_entertainment"]
            ),
            StateEvent(
                id: "away-1",
                startTime: Date(timeIntervalSince1970: 2_520),
                endTime: Date(timeIntervalSince1970: 2_580),
                userState: .away,
                context: .neutral,
                confidence: 0.78,
                reason: ["face_missing_over_15s"]
            )
        ]

        let report = ReportGenerator().makeDailySummary(
            for: Date(timeIntervalSince1970: 0),
            events: events,
            reminderCount: 3,
            petEnergy: 18
        )

        expect(report.totalActiveSeconds == 2_580, "total active seconds should aggregate all events")
        expect(report.focusSeconds == 1_800, "focus seconds should include focused events")
        expect(report.entertainmentSeconds == 600, "entertainment seconds should include entertainment context")
        expect(report.offScreenCount == 1, "off screen count should include away events")
        expect(report.lookingDownSeconds == 120, "looking down seconds should aggregate lookingDown events")
        expect(report.longestFocusSeconds == 1_800, "longest focus should track max continuous focus event")
        expect(report.summaryText.contains("最长连续专注 30 分钟"), "summary should mention longest focus")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}

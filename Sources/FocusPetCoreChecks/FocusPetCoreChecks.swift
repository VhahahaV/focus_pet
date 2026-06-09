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
        checkModelFreeLiveObservationMarksVisionUnknown()
        checkLiveFallbackCanUseWorkInputWithoutPretendingVision()
        checkLowConfidenceUnknownVisualsDoNotTriggerRules()
        checkDailyReportSeparatesDemoEventsFromLiveMetrics()
        checkFaceHeuristicsMarksMissingFace()
        checkFaceHeuristicsMarksCenteredFaceAsScreen()
        checkFaceHeuristicsMarksYawAsOffScreen()
        checkFaceHeuristicsMarksPitchAsDown()
        checkLiveObservationUsesLatestFaceDetection()
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

    private static func checkModelFreeLiveObservationMarksVisionUnknown() {
        let builder = LiveObservationBuilder(faceDetector: ModelFreeFaceStateDetector())
        let observation = builder.makeObservation(
            input: LiveObservationInput(
                timestamp: Date(timeIntervalSince1970: 3_000),
                frontAppName: "Cursor",
                frontAppBundleID: nil,
                context: .work,
                lastInputSeconds: 4,
                cameraAuthorization: .authorized,
                cameraRunning: true,
                latestFrame: CameraFrameMetadata(timestamp: Date(timeIntervalSince1970: 3_000), sequenceNumber: 12)
            ),
            stableDurationSeconds: 9
        )

        expect(observation.sourceKind == .live, "live builder should mark observations as live")
        expect(observation.facePresence == .unknown, "model-free detector should not claim face presence")
        expect(observation.gazeState == .unknown, "model-free detector should not claim gaze")
        expect(observation.headPitchDegrees == 0, "model-free detector should not claim head pose")
    }

    private static func checkLiveFallbackCanUseWorkInputWithoutPretendingVision() {
        let engine = StateFusionEngine()
        let observation = StateObservation(
            timestamp: Date(timeIntervalSince1970: 3_100),
            sourceKind: .live,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "Cursor",
            context: .work,
            lastInputSeconds: 5,
            stableDurationSeconds: 45
        )

        let state = engine.fuse(observation)

        expect(state.userState == .focused, "live fallback should infer focused from active work input")
        expect(state.reason.contains("vision_unknown"), "live fallback should disclose unknown vision")
        expect(state.reason.contains("recent_input_in_work_context"), "live fallback should explain input-based focus")
    }

    private static func checkLowConfidenceUnknownVisualsDoNotTriggerRules() {
        let state = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 3_200),
            userState: .unknown,
            context: .work,
            confidence: 0.5,
            reason: ["vision_unknown", "input_idle"],
            stableDurationSeconds: 600
        )

        let decisions = RuleEngine().evaluate(
            rules: FocusRule.defaults,
            state: state,
            now: Date(timeIntervalSince1970: 3_200),
            lastTriggeredAtByRuleID: [:],
            isPaused: false
        )

        expect(decisions.isEmpty, "low-confidence unknown visuals should not trigger reminders")
    }

    private static func checkDailyReportSeparatesDemoEventsFromLiveMetrics() {
        let liveFocus = StateEvent(
            id: "live-focus",
            sourceKind: .live,
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 600),
            userState: .focused,
            context: .work,
            confidence: 0.72,
            reason: ["recent_input_in_work_context", "vision_unknown"]
        )
        let demoEntertainment = StateEvent(
            id: "demo-entertainment",
            sourceKind: .demo,
            startTime: Date(timeIntervalSince1970: 600),
            endTime: Date(timeIntervalSince1970: 1_800),
            userState: .entertainment,
            context: .entertainment,
            confidence: 0.92,
            reason: ["manual_demo_entertainment"]
        )

        let report = ReportGenerator().makeDailySummary(
            for: Date(timeIntervalSince1970: 0),
            events: [liveFocus, demoEntertainment],
            reminderCount: 0,
            petEnergy: 3
        )

        expect(report.focusSeconds == 600, "live focus should count in daily metrics")
        expect(report.entertainmentSeconds == 0, "demo entertainment should not inflate live report metrics")
        expect(report.liveEventCount == 1, "report should count live events separately")
        expect(report.demoEventCount == 1, "report should count demo events separately")
    }

    private static func checkFaceHeuristicsMarksMissingFace() {
        let result = FaceStateHeuristics().result(from: nil)

        expect(result.facePresence == .missing, "missing face geometry should report missing face")
        expect(result.gazeState == .unknown, "missing face geometry should keep gaze unknown")
        expect(result.confidence >= 0.7, "missing face geometry should be a confident absence")
    }

    private static func checkFaceHeuristicsMarksCenteredFaceAsScreen() {
        let result = FaceStateHeuristics().result(from: FaceGeometrySnapshot(
            yawDegrees: 3,
            pitchDegrees: 2,
            rollDegrees: 1,
            boundingBoxCenterY: 0.56,
            confidence: 0.8
        ))

        expect(result.facePresence == .present, "centered face should be present")
        expect(result.gazeState == .screen, "centered face should be coarse screen gaze")
        expect(result.headPitchDegrees == 2, "head pitch should preserve detector pitch")
    }

    private static func checkFaceHeuristicsMarksYawAsOffScreen() {
        let result = FaceStateHeuristics().result(from: FaceGeometrySnapshot(
            yawDegrees: 31,
            pitchDegrees: 4,
            rollDegrees: 0,
            boundingBoxCenterY: 0.55,
            confidence: 0.84
        ))

        expect(result.facePresence == .present, "yaw face should be present")
        expect(result.gazeState == .offScreen, "large yaw should become off-screen gaze")
        expect(result.reason == "yaw_over_threshold", "yaw off-screen should explain threshold")
    }

    private static func checkFaceHeuristicsMarksPitchAsDown() {
        let result = FaceStateHeuristics().result(from: FaceGeometrySnapshot(
            yawDegrees: 4,
            pitchDegrees: 30,
            rollDegrees: 0,
            boundingBoxCenterY: 0.48,
            confidence: 0.83
        ))

        expect(result.facePresence == .present, "pitch face should be present")
        expect(result.gazeState == .down, "large pitch should become down gaze")
        expect(result.headPitchDegrees == 30, "head pitch should preserve downward pitch")
    }

    private static func checkLiveObservationUsesLatestFaceDetection() {
        let builder = LiveObservationBuilder(faceDetector: ModelFreeFaceStateDetector())
        let observation = builder.makeObservation(
            input: LiveObservationInput(
                timestamp: Date(timeIntervalSince1970: 4_000),
                frontAppName: "Cursor",
                frontAppBundleID: nil,
                context: .work,
                lastInputSeconds: 2,
                cameraAuthorization: .authorized,
                cameraRunning: true,
                latestFrame: CameraFrameMetadata(timestamp: Date(timeIntervalSince1970: 4_000), sequenceNumber: 42),
                latestFaceDetection: FaceDetectionResult(
                    facePresence: .present,
                    gazeState: .screen,
                    headPitchDegrees: 5,
                    confidence: 0.82,
                    reason: "face_centered"
                )
            ),
            stableDurationSeconds: 12
        )

        expect(observation.facePresence == .present, "live observation should use latest face detection")
        expect(observation.gazeState == .screen, "live observation should use latest detected gaze")
        expect(observation.headPitchDegrees == 5, "live observation should use latest detected pitch")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}

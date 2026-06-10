import FocusPetCore
import Foundation

struct FocusPetCoreTestCompileProbe {
    func eventAccumulatorDoesNotBackfillStableDuration() -> Bool {
        let accumulator = StateEventAccumulator()
        let first = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 100),
            userState: .focused,
            context: .work,
            confidence: 0.8,
            reason: ["focused"],
            stableDurationSeconds: 0
        )
        let second = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 103),
            userState: .focused,
            context: .work,
            confidence: 0.82,
            reason: ["focused"],
            stableDurationSeconds: 600
        )

        let events = accumulator.recording(
            state: second,
            sourceKind: .live,
            in: accumulator.recording(state: first, sourceKind: .live, in: [])
        )

        return events.count == 1 && events[0].durationSeconds == 6
    }

    func reportMergesOverlappingLiveEvents() -> Bool {
        let events = [
            StateEvent(
                id: "focus-1",
                sourceKind: .live,
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 600),
                userState: .focused,
                context: .work,
                confidence: 0.8,
                reason: ["focused"]
            ),
            StateEvent(
                id: "focus-2",
                sourceKind: .live,
                startTime: Date(timeIntervalSince1970: 3),
                endTime: Date(timeIntervalSince1970: 603),
                userState: .focused,
                context: .work,
                confidence: 0.8,
                reason: ["focused"]
            )
        ]

        let report = ReportGenerator().makeDailySummary(
            for: Date(timeIntervalSince1970: 0),
            events: events,
            reminderCount: 0,
            petEnergy: nil
        )

        return report.focusSeconds == 603 && report.totalActiveSeconds == 603
    }

    func reportDoesNotMergeFocusAcrossDistractedEvent() -> Bool {
        let events = [
            StateEvent(
                id: "focus-1",
                sourceKind: .live,
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 10),
                userState: .focused,
                context: .work,
                confidence: 0.8,
                reason: ["focused"]
            ),
            StateEvent(
                id: "distracted-1",
                sourceKind: .live,
                startTime: Date(timeIntervalSince1970: 10),
                endTime: Date(timeIntervalSince1970: 20),
                userState: .distracted,
                context: .work,
                confidence: 0.8,
                reason: ["distracted"]
            ),
            StateEvent(
                id: "focus-2",
                sourceKind: .live,
                startTime: Date(timeIntervalSince1970: 20),
                endTime: Date(timeIntervalSince1970: 30),
                userState: .focused,
                context: .work,
                confidence: 0.8,
                reason: ["focused"]
            )
        ]

        let report = ReportGenerator().makeDailySummary(
            for: Date(timeIntervalSince1970: 0),
            events: events,
            reminderCount: 0,
            petEnergy: nil
        )

        return report.focusSeconds == 20
            && report.distractedSeconds == 10
            && report.longestFocusSeconds == 10
            && report.totalActiveSeconds == 30
    }

    func ruleEngineIgnoresDemoSource() -> Bool {
        let state = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 1_000),
            userState: .distracted,
            context: .work,
            confidence: 0.82,
            reason: ["manual_demo_distracted"],
            stableDurationSeconds: 120
        )

        let decisions = RuleEngine().evaluate(
            rules: [FocusRule.distractionReminder],
            state: state,
            sourceKind: .demo,
            now: Date(timeIntervalSince1970: 1_000),
            lastTriggeredAtByRuleID: [:],
            isPaused: false
        )

        return decisions.isEmpty
    }

    func meetingVeryLongIdleWithoutCameraBecomesAway() -> Bool {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 2_000),
            sourceKind: .live,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "Zoom",
            context: .meeting,
            lastInputSeconds: 900,
            stableDurationSeconds: 900,
            localActivity: LocalActivitySnapshot(
                lastInputSeconds: 900,
                lastKeyboardSeconds: 900,
                lastMouseSeconds: 900,
                lastScrollSeconds: 900,
                lastAppSwitchSeconds: 1_000,
                frontAppStableSeconds: 1_000,
                windowTitleStableSeconds: 1_000
            )
        ))

        return state.userState == .away && state.reason.contains("meeting_idle_over_10m")
    }
}

private let runFocusPetCoreRegressionProbe: Void = {
    let probe = FocusPetCoreTestCompileProbe()
    precondition(
        probe.eventAccumulatorDoesNotBackfillStableDuration(),
        "event accumulator should not backfill stable duration"
    )
    precondition(
        probe.reportMergesOverlappingLiveEvents(),
        "report should merge overlapping live events"
    )
    precondition(
        probe.reportDoesNotMergeFocusAcrossDistractedEvent(),
        "report should not merge focus through a distracted event"
    )
    precondition(
        probe.ruleEngineIgnoresDemoSource(),
        "rule engine should ignore demo observations"
    )
    precondition(
        probe.meetingVeryLongIdleWithoutCameraBecomesAway(),
        "very long meeting idle without camera should become away"
    )
}()

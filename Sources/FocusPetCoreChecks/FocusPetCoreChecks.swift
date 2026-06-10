import Darwin
import Foundation
import FocusPetCore

@main
enum FocusPetCoreChecks {
    static func main() {
        checkOnlyThreeUserStatesRemain()
        checkScreenGazeAlwaysBecomesFocused()
        checkRecentWorkInputWithUnknownVisionBecomesFocused()
        checkOffScreenGazeBecomesDistracted()
        checkDownwardHeadBecomesDistracted()
        checkEntertainmentContextBecomesDistracted()
        checkWorkKeyboardActivityBecomesHighConfidenceFocused()
        checkIdleWorkActivityBecomesRuleEligibleDistracted()
        checkMeetingIdleStaysFocusedWithoutCamera()
        checkMeetingVeryLongIdleBecomesAwayWithoutCamera()
        checkMeetingOffScreenVisionBecomesDistracted()
        checkNeutralMouseActivityStaysFocusedWithLowerConfidence()
        checkShortMissingFaceWithRecentInputStaysFocused()
        checkMissingFaceBecomesAway()
        checkLongIdleUnknownVisionBecomesAway()
        checkLegacyStatesDecodeIntoThreeStateModel()
        checkAppSettingsDecodesLegacyPetDefaults()
        checkPetBehaviorMapsFocusedEntertainmentDistractedAndAway()
        checkPetBehaviorMapsAwayReturnToWelcomeBack()
        checkPetActionSchedulerAppliesFiveMinuteNudgeCooldown()
        checkPetPackResolvesAliasesAndFallbacks()
        checkPetPackDecodesManifestAliases()
        checkPetPackValidatorReportsErrorsAndWarnings()
        checkRuleTriggersForDistractedState()
        checkRuleDoesNotTriggerDuringCooldown()
        checkRuleIgnoresDemoSource()
        checkPausedDetectionSuppressesRules()
        checkDailyReportAggregatesThreeStateMetrics()
        checkDailyReportMergesSampledFocusFragments()
        checkDailyReportDoesNotMergeAcrossInterveningState()
        checkDailyReportMergesSampledAwayFragments()
        checkDailyReportMergesOverlappingLiveEvents()
        checkDailyReportSeparatesDemoEventsFromLiveMetrics()
        checkEventAccumulatorMergesTenSecondTicks()
        checkStabilityTrackerTracksActivityTierWithoutFrontAppNoise()
        checkAppClassifierUsesBrowserWindowTitle()
        checkAppClassifierDetailedScoresBrowserEntertainment()
        checkDataRetentionReclaimsBoundedLocalData()
        checkFaceDiagnosticEntryStoresVisionFields()
        checkFaceHeuristicsMarksMissingFace()
        checkFaceHeuristicsKeepsUnknownWhenPoseUnavailable()
        checkFaceHeuristicsMarksCenteredFaceAsScreen()
        checkFaceHeuristicsMarksYawAsOffScreen()
        checkFaceHeuristicsMarksPitchAsDown()
        checkLiveObservationUsesLatestFaceDetection()
        checkLiveObservationIgnoresStaleFaceDetection()
        checkLiveObservationIgnoresLowConfidenceFaceDetection()
        print("FocusPetCoreChecks passed")
    }

    private static func checkOnlyThreeUserStatesRemain() {
        expect(UserState.allCases == [.focused, .distracted, .away], "user state model should only expose focused, distracted, and away")
    }

    private static func checkScreenGazeAlwaysBecomesFocused() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 100),
            sourceKind: .live,
            facePresence: .present,
            gazeState: .screen,
            headPitchDegrees: 2,
            frontAppName: "YouTube",
            context: .entertainment,
            lastInputSeconds: 80,
            stableDurationSeconds: 60
        ))

        expect(state.userState == .focused, "screen gaze should be focused even when app context looks distracting")
        expect(state.reason.contains("gaze_on_screen"), "focused screen gaze should expose gaze_on_screen reason")
    }

    private static func checkRecentWorkInputWithUnknownVisionBecomesFocused() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 110),
            sourceKind: .live,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "Cursor",
            context: .work,
            lastInputSeconds: 5,
            stableDurationSeconds: 45
        ))

        expect(state.userState == .focused, "recent work input with unknown vision should fall back to focused")
        expect(state.reason.contains("vision_unconfirmed"), "fallback focus should disclose unconfirmed vision")
    }

    private static func checkOffScreenGazeBecomesDistracted() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 130),
            sourceKind: .live,
            facePresence: .present,
            gazeState: .offScreen,
            headPitchDegrees: 4,
            frontAppName: "Cursor",
            context: .work,
            lastInputSeconds: 8,
            stableDurationSeconds: 12
        ))

        expect(state.userState == .distracted, "off-screen gaze should become distracted")
        expect(state.reason.contains("gaze_off_screen_over_threshold"), "off-screen distraction should be explainable")
    }

    private static func checkDownwardHeadBecomesDistracted() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 150),
            sourceKind: .live,
            facePresence: .present,
            gazeState: .down,
            headPitchDegrees: 31,
            frontAppName: "Preview",
            context: .work,
            lastInputSeconds: 16,
            stableDurationSeconds: 18
        ))

        expect(state.userState == .distracted, "downward head should become distracted")
        expect(state.reason.contains("head_down_over_threshold"), "downward distraction should be explainable")
    }

    private static func checkEntertainmentContextBecomesDistracted() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 170),
            sourceKind: .live,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "YouTube",
            context: .entertainment,
            lastInputSeconds: 3,
            stableDurationSeconds: 35
        ))

        expect(state.userState == .distracted, "entertainment context should become distracted after threshold")
        expect(state.reason.contains("front_app_is_entertainment"), "entertainment distraction should be explainable")
    }

    private static func checkWorkKeyboardActivityBecomesHighConfidenceFocused() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 175),
            sourceKind: .live,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "Cursor",
            context: .work,
            lastInputSeconds: 4,
            stableDurationSeconds: 45,
            localActivity: LocalActivitySnapshot(
                lastInputSeconds: 4,
                lastKeyboardSeconds: 4,
                lastMouseSeconds: 60,
                lastScrollSeconds: 120,
                lastAppSwitchSeconds: 240,
                frontAppStableSeconds: 300,
                windowTitleStableSeconds: 180
            )
        ))

        expect(state.userState == .focused, "keyboard activity in a stable work app should be focused")
        expect(state.confidence >= 0.78, "work keyboard activity should have enough confidence to drive reminders and reporting")
        expect(state.reason.contains("work_keyboard_activity"), "work keyboard focus should expose local behavior reason")
    }

    private static func checkIdleWorkActivityBecomesRuleEligibleDistracted() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 176),
            sourceKind: .live,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "Cursor",
            context: .work,
            lastInputSeconds: 90,
            stableDurationSeconds: 90,
            localActivity: LocalActivitySnapshot(
                lastInputSeconds: 90,
                lastKeyboardSeconds: 90,
                lastMouseSeconds: 90,
                lastScrollSeconds: 90,
                lastAppSwitchSeconds: 360,
                frontAppStableSeconds: 420,
                windowTitleStableSeconds: 420
            )
        ))

        expect(state.userState == .distracted, "idle work activity should become distracted before away")
        expect(state.confidence >= 0.65, "idle work distraction should be rule-eligible")
        expect(state.reason.contains("local_idle_over_60s"), "idle distraction should expose local idle reason")
    }

    private static func checkMeetingIdleStaysFocusedWithoutCamera() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 177),
            sourceKind: .live,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "Zoom",
            context: .meeting,
            lastInputSeconds: 480,
            stableDurationSeconds: 480,
            localActivity: LocalActivitySnapshot(
                lastInputSeconds: 480,
                lastKeyboardSeconds: 480,
                lastMouseSeconds: 480,
                lastScrollSeconds: 480,
                lastAppSwitchSeconds: 600,
                frontAppStableSeconds: 600,
                windowTitleStableSeconds: 600
            )
        ))

        expect(state.userState == .focused, "meeting apps should not be treated as away just because there is no input")
        expect(state.confidence >= 0.7, "stable meeting context should be a confident focus state")
        expect(state.reason.contains("meeting_context_without_input"), "meeting focus should expose local context reason")
    }

    private static func checkMeetingVeryLongIdleBecomesAwayWithoutCamera() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 177),
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

        expect(state.userState == .away, "very long meeting idle without camera should become away")
        expect(state.reason.contains("meeting_idle_over_10m"), "meeting idle away should expose the bounded meeting reason")
    }

    private static func checkMeetingOffScreenVisionBecomesDistracted() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 177),
            sourceKind: .live,
            facePresence: .present,
            gazeState: .offScreen,
            headPitchDegrees: 2,
            frontAppName: "Zoom",
            context: .meeting,
            lastInputSeconds: 120,
            stableDurationSeconds: 30,
            localActivity: LocalActivitySnapshot(
                lastInputSeconds: 120,
                lastKeyboardSeconds: 120,
                lastMouseSeconds: 120,
                lastScrollSeconds: 120,
                lastAppSwitchSeconds: 600,
                frontAppStableSeconds: 600,
                windowTitleStableSeconds: 600
            )
        ))

        expect(state.userState == .distracted, "meeting context should not override confirmed off-screen vision")
        expect(state.reason.contains("gaze_off_screen_over_threshold"), "meeting visual distraction should stay explainable")
    }

    private static func checkNeutralMouseActivityStaysFocusedWithLowerConfidence() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 178),
            sourceKind: .live,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "Unknown",
            context: .neutral,
            lastInputSeconds: 6,
            stableDurationSeconds: 20,
            localActivity: LocalActivitySnapshot(
                lastInputSeconds: 6,
                lastKeyboardSeconds: 90,
                lastMouseSeconds: 6,
                lastScrollSeconds: 35,
                lastAppSwitchSeconds: 12,
                frontAppStableSeconds: 12,
                windowTitleStableSeconds: 12
            )
        ))

        expect(state.userState == .focused, "recent neutral mouse activity should stay focused but not become high-confidence work")
        expect(state.confidence < 0.75, "neutral mouse activity should stay lower confidence than stable work typing")
        expect(state.reason.contains("recent_local_activity"), "neutral focus should expose local activity reason")
    }

    private static func checkShortMissingFaceWithRecentInputStaysFocused() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 180),
            sourceKind: .live,
            facePresence: .missing,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "Cursor",
            context: .work,
            lastInputSeconds: 5,
            stableDurationSeconds: 20
        ))

        expect(state.userState == .focused, "short camera face-missing glitches should not immediately become away")
        expect(state.reason.contains("recent_input"), "short missing face should fall back to local activity")
    }

    private static func checkMissingFaceBecomesAway() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 190),
            sourceKind: .live,
            facePresence: .missing,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: nil,
            context: .neutral,
            lastInputSeconds: 90,
            stableDurationSeconds: 50
        ))

        expect(state.userState == .away, "sustained missing face over threshold should become away")
        expect(state.reason == ["face_missing_sustained"], "away reason should describe sustained missing face")
    }

    private static func checkLongIdleUnknownVisionBecomesAway() {
        let state = StateFusionEngine().fuse(StateObservation(
            timestamp: Date(timeIntervalSince1970: 210),
            sourceKind: .live,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: "Finder",
            context: .neutral,
            lastInputSeconds: 210,
            stableDurationSeconds: 80
        ))

        expect(state.userState == .away, "long idle with unknown vision should become away")
    }

    private static func checkLegacyStatesDecodeIntoThreeStateModel() {
        let decoder = JSONDecoder()
        let oldResting = try? decoder.decode(UserState.self, from: "\"resting\"".data(using: .utf8)!)
        let oldLookingDown = try? decoder.decode(UserState.self, from: "\"lookingDown\"".data(using: .utf8)!)
        let oldMeeting = try? decoder.decode(UserState.self, from: "\"meeting\"".data(using: .utf8)!)

        expect(oldResting == .focused, "legacy resting should migrate to focused")
        expect(oldMeeting == .focused, "legacy meeting should migrate to focused")
        expect(oldLookingDown == .distracted, "legacy lookingDown should migrate to distracted")
    }

    private static func checkAppSettingsDecodesLegacyPetDefaults() {
        let legacyJSON = """
        {
          "hasCompletedOnboarding": true,
          "runtimeMode": "live",
          "isPaused": false,
          "pauseUntil": null,
          "petOpacity": 0.94,
          "petScale": 1.0,
          "petAnimationEnabled": true,
          "soundEnabled": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let settings = try? decoder.decode(AppSettings.self, from: legacyJSON) else {
            expect(false, "legacy settings should decode")
            return
        }

        expect(settings.petSize == 128, "legacy settings should default pet size")
        expect(settings.petHidden == false, "legacy settings should default pet visibility")
        expect(settings.petHiddenUntil == nil, "legacy settings should default no timed hide")
        expect(settings.petPlacementMode == .dockAttached, "legacy settings should default Dock placement")
        expect(settings.petManualOriginX == nil, "legacy settings should default no manual x")
        expect(settings.petManualOriginY == nil, "legacy settings should default no manual y")
        expect(settings.petHoverMenuEnabled == true, "legacy settings should default hover menu enabled")
        expect(settings.cameraSamplingEnabled == false, "legacy settings should default camera sampling disabled for low-power mode")
        expect(
            settings.selectedPetPackID == PetPackDefaults.luoXiaoHeiLocalID,
            "legacy settings should default selected pet pack to Luo XiaoHei when available"
        )
    }

    private static func checkPetBehaviorMapsFocusedEntertainmentDistractedAndAway() {
        let controller = PetBehaviorController()
        let now = Date(timeIntervalSince1970: 2_000)
        let focused = FusedUserState(
            timestamp: now,
            userState: .focused,
            context: .work,
            confidence: 0.8,
            reason: ["focused"],
            stableDurationSeconds: 10
        )
        let entertainment = FusedUserState(
            timestamp: now,
            userState: .distracted,
            context: .entertainment,
            confidence: 0.85,
            reason: ["front_app_is_entertainment"],
            stableDurationSeconds: 90
        )
        let distracted = FusedUserState(
            timestamp: now,
            userState: .distracted,
            context: .work,
            confidence: 0.85,
            reason: ["off_screen"],
            stableDurationSeconds: 45
        )
        let away = FusedUserState(
            timestamp: now,
            userState: .away,
            context: .neutral,
            confidence: 0.8,
            reason: ["face_missing"],
            stableDurationSeconds: 200
        )

        expect(controller.behavior(for: focused, previousState: nil, latestReminder: nil) == .sleeping, "focused should map to sleeping")
        expect(controller.behavior(for: entertainment, previousState: focused, latestReminder: nil) == .nudgeEntertainment, "entertainment distraction should map to entertainment nudge")
        expect(controller.behavior(for: distracted, previousState: focused, latestReminder: nil) == .nudgeDistracted, "work distraction should map to distracted nudge")
        expect(controller.behavior(for: away, previousState: focused, latestReminder: nil) == .sleeping, "away should map to sleeping")
    }

    private static func checkPetBehaviorMapsAwayReturnToWelcomeBack() {
        let controller = PetBehaviorController()
        let now = Date(timeIntervalSince1970: 2_100)
        let away = FusedUserState(
            timestamp: now.addingTimeInterval(-30),
            userState: .away,
            context: .neutral,
            confidence: 0.7,
            reason: ["face_missing"],
            stableDurationSeconds: 30
        )
        let returned = FusedUserState(
            timestamp: now,
            userState: .focused,
            context: .work,
            confidence: 0.82,
            reason: ["focused"],
            stableDurationSeconds: 3
        )

        expect(controller.behavior(for: returned, previousState: away, latestReminder: nil) == .welcomeBack, "away return should map to welcome back")
    }

    private static func checkPetActionSchedulerAppliesFiveMinuteNudgeCooldown() {
        var scheduler = PetActionScheduler()
        let start = Date(timeIntervalSince1970: 3_000)

        let first = scheduler.nextAction(behavior: .nudgeDistracted, now: start)
        let cooled = scheduler.nextAction(behavior: .nudgeDistracted, now: start.addingTimeInterval(60))
        let afterCooldown = scheduler.nextAction(behavior: .nudgeDistracted, now: start.addingTimeInterval(301))

        expect(first == .nudgeDistracted, "first distracted nudge should play")
        expect(cooled == .idle, "distracted nudge should cool down")
        expect(afterCooldown == .nudgeDistracted, "distracted nudge should resume after cooldown")
    }

    private static func checkPetPackResolvesAliasesAndFallbacks() {
        let aliasPack = PetPack(
            schemaVersion: 1,
            id: "alias_pack",
            name: "Alias Pack",
            source: .userImported,
            distribution: .localOnly,
            style: nil,
            license: nil,
            defaultSize: PetPackSize(width: 128, height: 128),
            defaultScale: 1,
            anchor: .dockAttached,
            hitBox: nil,
            animations: [
                .idle: PetAnimationSpec(folder: "idle", fps: 6, loop: true, frameCount: nil),
                .shakeHead: PetAnimationSpec(folder: "shake", fps: 8, loop: false, frameCount: nil)
            ],
            actionAliases: [.nudgeDistracted: .shakeHead]
        )
        expect(aliasPack.animationKey(for: .nudgeDistracted) == .shakeHead, "pet pack should resolve explicit aliases before idle")

        let sleepingPack = PetPack(
            schemaVersion: 1,
            id: "sleeping_pack",
            name: "Sleeping Pack",
            source: .userImported,
            distribution: .localOnly,
            style: nil,
            license: nil,
            defaultSize: PetPackSize(width: 128, height: 128),
            defaultScale: 1,
            anchor: .dockAttached,
            hitBox: nil,
            animations: [.sleeping: PetAnimationSpec(folder: "sleeping", fps: 4, loop: true, frameCount: nil)],
            actionAliases: [:]
        )
        expect(sleepingPack.animationKey(for: .welcomeBack) == .sleeping, "pet pack should fall back to sleeping when idle is missing")
    }

    private static func checkPetPackDecodesManifestAliases() {
        let data = """
        {
          "schemaVersion": 1,
          "id": "legacy_keys",
          "name": "Legacy Keys",
          "animations": {
            "sleep": {"folder": "sleeping", "fps": 4, "loop": true},
            "nudge_distracted": {"folder": "nudge_distracted", "fps": 8, "loop": false}
          },
          "actionAliases": {
            "welcome_back": "sleep"
          }
        }
        """.data(using: .utf8)!

        guard let pack = try? JSONDecoder().decode(PetPack.self, from: data) else {
            expect(false, "pet pack should decode legacy snake-case manifest keys")
            return
        }

        expect(pack.animations[.sleeping]?.folder == "sleeping", "sleep key should decode to sleeping")
        expect(pack.animations[.nudgeDistracted]?.folder == "nudge_distracted", "snake-case nudge should decode to standard key")
        expect(pack.actionAliases[.welcomeBack] == .sleeping, "alias values should decode through manifest key mapper")
    }

    private static func checkPetPackValidatorReportsErrorsAndWarnings() {
        let missingRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: missingRoot) }

        let missingResult = PetPackValidator().validate(rootURL: missingRoot)
        expect(!missingResult.isValid, "validator should reject missing pet.json")
        expect(missingResult.errors.contains(.missingManifest), "missing manifest should be reported")

        let validRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: validRoot) }
        let idleURL = validRoot.appendingPathComponent("idle", isDirectory: true)
        try? FileManager.default.createDirectory(at: idleURL, withIntermediateDirectories: true)
        try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: idleURL.appendingPathComponent("000.png"))

        let manifest = """
        {
          "schemaVersion": 1,
          "id": "warning_pack",
          "name": "Warning Pack",
          "source": "userImported",
          "distribution": "localOnly",
          "license": {"type": "unknown"},
          "defaultSize": {"width": 128, "height": 128},
          "defaultScale": 1.0,
          "anchor": "dockAttached",
          "animations": {
            "idle": {"folder": "idle", "fps": 8, "loop": true}
          }
        }
        """.data(using: .utf8)!
        try? manifest.write(to: validRoot.appendingPathComponent("pet.json"))

        let warningResult = PetPackValidator().validate(rootURL: validRoot)
        expect(warningResult.isValid, "validator should allow warning-only packs with playable frames")
        expect(warningResult.warnings.contains(.missingPreview), "validator should warn about missing preview")
        expect(warningResult.warnings.contains(.unknownLicense), "validator should warn about unknown license")
    }

    private static func checkRuleTriggersForDistractedState() {
        let rule = FocusRule.distractionReminder
        let state = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 1_000),
            userState: .distracted,
            context: .work,
            confidence: 0.82,
            reason: ["gaze_off_screen_over_threshold"],
            stableDurationSeconds: 24
        )

        let decisions = RuleEngine().evaluate(
            rules: [rule],
            state: state,
            now: Date(timeIntervalSince1970: 1_000),
            lastTriggeredAtByRuleID: [:],
            isPaused: false
        )

        expect(decisions.count == 1, "matching distracted rule should trigger once")
        expect(decisions.first?.ruleID == rule.id, "decision should preserve rule id")
    }

    private static func checkRuleDoesNotTriggerDuringCooldown() {
        let rule = FocusRule.distractionReminder
        let state = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 1_120),
            userState: .distracted,
            context: .work,
            confidence: 0.82,
            reason: ["gaze_off_screen_over_threshold"],
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

    private static func checkRuleIgnoresDemoSource() {
        let state = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 1_200),
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
            now: Date(timeIntervalSince1970: 1_200),
            lastTriggeredAtByRuleID: [:],
            isPaused: false
        )

        expect(decisions.isEmpty, "demo observations should not trigger real reminders")
    }

    private static func checkPausedDetectionSuppressesRules() {
        let state = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 2_000),
            userState: .distracted,
            context: .work,
            confidence: 0.9,
            reason: ["head_down_over_threshold"],
            stableDurationSeconds: 180
        )

        let decisions = RuleEngine().evaluate(
            rules: [FocusRule.distractionReminder],
            state: state,
            now: Date(timeIntervalSince1970: 2_000),
            lastTriggeredAtByRuleID: [:],
            isPaused: true
        )

        expect(decisions.isEmpty, "paused detection should suppress all reminders")
    }

    private static func checkDailyReportAggregatesThreeStateMetrics() {
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
                id: "distracted-1",
                startTime: Date(timeIntervalSince1970: 1_800),
                endTime: Date(timeIntervalSince1970: 1_920),
                userState: .distracted,
                context: .work,
                confidence: 0.86,
                reason: ["head_down_over_threshold"]
            ),
            StateEvent(
                id: "away-1",
                startTime: Date(timeIntervalSince1970: 1_920),
                endTime: Date(timeIntervalSince1970: 1_980),
                userState: .away,
                context: .neutral,
                confidence: 0.78,
                reason: ["face_missing_over_10s"]
            )
        ]

        let report = ReportGenerator().makeDailySummary(
            for: Date(timeIntervalSince1970: 0),
            events: events,
            reminderCount: 2,
            petEnergy: 18
        )

        expect(report.totalActiveSeconds == 1_980, "total active seconds should aggregate all live events")
        expect(report.focusSeconds == 1_800, "focus seconds should include focused events")
        expect(report.distractedSeconds == 120, "distracted seconds should include distracted events")
        expect(report.awayCount == 1, "away count should include away event intervals")
        expect(report.longestFocusSeconds == 1_800, "longest focus should track max continuous focus event")
        expect(report.summaryText.contains("走神 2 分钟"), "summary should mention distracted minutes")
    }

    private static func checkDailyReportMergesSampledFocusFragments() {
        let events = [
            event("focus-1", 0, 3, .focused),
            event("focus-2", 10, 13, .focused),
            event("focus-3", 20, 23, .focused),
            event("focus-4", 30, 33, .focused)
        ]

        let report = ReportGenerator().makeDailySummary(
            for: Date(timeIntervalSince1970: 0),
            events: events,
            reminderCount: 0,
            petEnergy: nil
        )

        expect(report.focusSeconds == 33, "sampled focus fragments should merge across the state loop gap")
        expect(report.longestFocusSeconds == 33, "longest focus should use merged sampled fragments")
        expect(report.liveEventCount == 1, "sampled fragments should count as one live session in the report")
    }

    private static func checkDailyReportDoesNotMergeAcrossInterveningState() {
        let events = [
            event("focus-1", 0, 10, .focused),
            event("distracted-1", 10, 20, .distracted),
            event("focus-2", 20, 30, .focused)
        ]

        let report = ReportGenerator().makeDailySummary(
            for: Date(timeIntervalSince1970: 0),
            events: events,
            reminderCount: 0,
            petEnergy: nil
        )

        expect(report.totalActiveSeconds == 30, "timeline should preserve total wall time")
        expect(report.focusSeconds == 20, "focus fragments should not merge through a distracted interval")
        expect(report.distractedSeconds == 10, "intervening distraction should keep its own duration")
        expect(report.longestFocusSeconds == 10, "longest focus should stop at intervening states")
        expect(report.liveEventCount == 3, "timeline should keep separate state segments")
    }

    private static func checkDailyReportMergesSampledAwayFragments() {
        let events = [
            event("away-1", 0, 3, .away),
            event("away-2", 10, 13, .away),
            event("focus-1", 40, 43, .focused),
            event("away-3", 60, 63, .away)
        ]

        let report = ReportGenerator().makeDailySummary(
            for: Date(timeIntervalSince1970: 0),
            events: events,
            reminderCount: 0,
            petEnergy: nil
        )

        expect(report.awayCount == 2, "sampled away fragments in one absence should count as one away session")
    }

    private static func checkDailyReportMergesOverlappingLiveEvents() {
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

        expect(report.focusSeconds == 603, "overlapping focus events should be counted as one merged interval")
        expect(report.totalActiveSeconds == 603, "overlapping live events should not inflate total active time")
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
        let demoDistracted = StateEvent(
            id: "demo-distracted",
            sourceKind: .demo,
            startTime: Date(timeIntervalSince1970: 600),
            endTime: Date(timeIntervalSince1970: 1_800),
            userState: .distracted,
            context: .work,
            confidence: 0.92,
            reason: ["manual_demo_distracted"]
        )

        let report = ReportGenerator().makeDailySummary(
            for: Date(timeIntervalSince1970: 0),
            events: [liveFocus, demoDistracted],
            reminderCount: 0,
            petEnergy: 3
        )

        expect(report.focusSeconds == 600, "live focus should count in daily metrics")
        expect(report.distractedSeconds == 0, "demo distraction should not inflate live report metrics")
        expect(report.liveEventCount == 1, "report should count live events separately")
        expect(report.demoEventCount == 1, "report should count demo events separately")
    }

    private static func checkEventAccumulatorMergesTenSecondTicks() {
        let accumulator = StateEventAccumulator(defaultTickSeconds: 10, mergeGapSeconds: 15)
        let first = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 100),
            userState: .focused,
            context: .work,
            confidence: 0.8,
            reason: ["focused"],
            stableDurationSeconds: 0
        )
        let second = FusedUserState(
            timestamp: Date(timeIntervalSince1970: 110),
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

        expect(events.count == 1, "same state ticks should merge across the 10 second state loop")
        expect(events[0].durationSeconds == 20, "merged 10 second ticks should represent continuous wall time")
    }

    private static func checkStabilityTrackerTracksActivityTierWithoutFrontAppNoise() {
        var tracker = ObservationStabilityTracker()
        let first = StateObservation(
            timestamp: Date(timeIntervalSince1970: 100),
            sourceKind: .live,
            facePresence: .present,
            gazeState: .offScreen,
            headPitchDegrees: 0,
            frontAppName: "Cursor",
            context: .work,
            lastInputSeconds: 2,
            stableDurationSeconds: 0,
            localActivity: LocalActivitySnapshot(
                lastInputSeconds: 2,
                lastKeyboardSeconds: 2,
                lastMouseSeconds: 30,
                lastScrollSeconds: 90,
                lastAppSwitchSeconds: 300,
                frontAppStableSeconds: 300,
                windowTitleStableSeconds: 300
            )
        )
        let second = StateObservation(
            timestamp: Date(timeIntervalSince1970: 130),
            sourceKind: .live,
            facePresence: .present,
            gazeState: .offScreen,
            headPitchDegrees: 0,
            frontAppName: "Xcode",
            context: .work,
            lastInputSeconds: 8,
            stableDurationSeconds: 0,
            localActivity: LocalActivitySnapshot(
                lastInputSeconds: 8,
                lastKeyboardSeconds: 8,
                lastMouseSeconds: 60,
                lastScrollSeconds: 120,
                lastAppSwitchSeconds: 0,
                frontAppStableSeconds: 0,
                windowTitleStableSeconds: 0
            )
        )
        let third = StateObservation(
            timestamp: Date(timeIntervalSince1970: 160),
            sourceKind: .live,
            facePresence: .present,
            gazeState: .offScreen,
            headPitchDegrees: 0,
            frontAppName: "Xcode",
            context: .work,
            lastInputSeconds: 90,
            stableDurationSeconds: 0,
            localActivity: LocalActivitySnapshot(
                lastInputSeconds: 90,
                lastKeyboardSeconds: 90,
                lastMouseSeconds: 90,
                lastScrollSeconds: 90,
                lastAppSwitchSeconds: 30,
                frontAppStableSeconds: 30,
                windowTitleStableSeconds: 30
            )
        )

        _ = tracker.observationWithUpdatedStability(first)
        let unchangedTier = tracker.observationWithUpdatedStability(second)
        let idleTier = tracker.observationWithUpdatedStability(third)

        expect(unchangedTier.stableDurationSeconds == 30, "front app noise should not reset stability while activity tier is unchanged")
        expect(idleTier.stableDurationSeconds == 0, "local activity tier changes should reset stability")
    }

    private static func checkAppClassifierUsesBrowserWindowTitle() {
        let classifier = AppContextClassifier()

        let entertainment = classifier.classify(
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube - Focus music"
        )
        let meeting = classifier.classify(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            windowTitle: "Weekly sync - meet.google.com"
        )

        expect(entertainment == .entertainment, "browser window title should classify entertainment pages")
        expect(meeting == .meeting, "browser window title should classify meeting pages")
    }

    private static func checkAppClassifierDetailedScoresBrowserEntertainment() {
        let classifier = AppContextClassifier()
        let classification = classifier.classifyDetailed(
            appName: "Microsoft Edge",
            bundleID: "com.microsoft.edgemac",
            windowTitle: "YouTube - 现实桌面节奏大师"
        )

        expect(classification.context == .entertainment, "detailed classifier should classify browser entertainment pages")
        expect(classification.entertainmentScore > classification.workScore, "entertainment page score should outrank generic browser work score")
        expect(classification.confidence >= 0.8, "window-title entertainment matches should be confident")
        expect(classification.reason.contains("title_match:youtube"), "detailed classifier should expose matched title reason")
    }

    private static func checkDataRetentionReclaimsBoundedLocalData() {
        let now = Date(timeIntervalSince1970: 10_000)
        let policy = DataRetentionPolicy(
            maxStateEvents: 2,
            maxReminders: 1,
            maxFaceDiagnostics: 2,
            maxEventAgeSeconds: 1_000,
            maxReminderAgeSeconds: 1_000,
            maxFaceDiagnosticAgeSeconds: 1_000
        )
        let reclaimed = LocalDataReclaimer(policy: policy).reclaim(
            stateEvents: [
                event("old", 0, 10, .focused),
                event("new-1", 9_100, 9_110, .focused),
                event("new-2", 9_120, 9_130, .distracted)
            ],
            reminders: [
                reminder("old-reminder", at: 1_000),
                reminder("new-reminder", at: 9_900)
            ],
            faceDiagnostics: [
                diagnostic("old-log", at: 1_000),
                diagnostic("new-log-1", at: 9_900),
                diagnostic("new-log-2", at: 9_910)
            ],
            now: now
        )

        expect(reclaimed.stateEvents.map(\.id) == ["new-1", "new-2"], "state event retention should remove old records and respect count cap")
        expect(reclaimed.reminders.map(\.id) == ["new-reminder"], "reminder retention should remove old records and respect count cap")
        expect(reclaimed.faceDiagnostics.map(\.id) == ["new-log-1", "new-log-2"], "face diagnostic retention should remove old records and respect count cap")
        expect(reclaimed.report.totalRemoved == 3, "retention report should count removed records")
    }

    private static func checkFaceDiagnosticEntryStoresVisionFields() {
        let entry = diagnostic("face-log", at: 4_000)

        expect(entry.frameSequenceNumber == 42, "face diagnostic should keep frame number")
        expect(entry.facePresence == .present, "face diagnostic should keep face presence")
        expect(entry.gazeState == .screen, "face diagnostic should keep gaze state")
        expect(entry.fusedState == .focused, "face diagnostic should keep fused state")
        expect(entry.reason.contains("face_centered"), "face diagnostic should keep detector reason")
    }

    private static func checkFaceHeuristicsMarksMissingFace() {
        let result = FaceStateHeuristics().result(from: nil)

        expect(result.facePresence == .missing, "missing face geometry should report missing face")
        expect(result.gazeState == .unknown, "missing face geometry should keep gaze unknown")
        expect(result.confidence >= 0.7, "missing face geometry should be a confident absence")
    }

    private static func checkFaceHeuristicsKeepsUnknownWhenPoseUnavailable() {
        let result = FaceStateHeuristics().result(from: FaceGeometrySnapshot(
            yawDegrees: nil,
            pitchDegrees: nil,
            rollDegrees: nil,
            boundingBoxCenterY: 0.3,
            confidence: 0.8
        ))

        expect(result.facePresence == .present, "face detection should still report present face")
        expect(result.gazeState == .unknown, "missing head pose should not be converted from bounding box position")
        expect(result.reason == "head_pose_unavailable", "pose unavailable reason should be explicit")
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

    private static func checkLiveObservationIgnoresStaleFaceDetection() {
        let builder = LiveObservationBuilder(faceDetector: ModelFreeFaceStateDetector())
        let observation = builder.makeObservation(
            input: LiveObservationInput(
                timestamp: Date(timeIntervalSince1970: 4_100),
                frontAppName: "Cursor",
                frontAppBundleID: nil,
                context: .work,
                lastInputSeconds: 2,
                cameraAuthorization: .authorized,
                cameraRunning: true,
                latestFrame: CameraFrameMetadata(timestamp: Date(timeIntervalSince1970: 4_000), sequenceNumber: 42),
                latestFaceDetection: FaceDetectionResult(
                    facePresence: .missing,
                    gazeState: .unknown,
                    headPitchDegrees: 0,
                    confidence: 0.78,
                    reason: "no_face_detected"
                )
            ),
            stableDurationSeconds: 20
        )

        expect(observation.facePresence == .unknown, "stale camera detection should not affect live observation")
        expect(observation.gazeState == .unknown, "stale camera gaze should be ignored")
    }

    private static func checkLiveObservationIgnoresLowConfidenceFaceDetection() {
        let builder = LiveObservationBuilder(faceDetector: ModelFreeFaceStateDetector())
        let observation = builder.makeObservation(
            input: LiveObservationInput(
                timestamp: Date(timeIntervalSince1970: 4_200),
                frontAppName: "Cursor",
                frontAppBundleID: nil,
                context: .work,
                lastInputSeconds: 2,
                cameraAuthorization: .authorized,
                cameraRunning: true,
                latestFrame: CameraFrameMetadata(timestamp: Date(timeIntervalSince1970: 4_200), sequenceNumber: 43),
                latestFaceDetection: FaceDetectionResult(
                    facePresence: .present,
                    gazeState: .offScreen,
                    headPitchDegrees: 0,
                    confidence: 0.42,
                    reason: "low_face_confidence"
                )
            ),
            stableDurationSeconds: 20
        )

        expect(observation.facePresence == .unknown, "low-confidence camera detection should not override local activity")
        expect(observation.gazeState == .unknown, "low-confidence gaze should be ignored")
    }

    private static func event(_ id: String, _ start: TimeInterval, _ end: TimeInterval, _ state: UserState) -> StateEvent {
        StateEvent(
            id: id,
            sourceKind: .live,
            startTime: Date(timeIntervalSince1970: start),
            endTime: Date(timeIntervalSince1970: end),
            userState: state,
            context: state == .focused ? .work : .neutral,
            confidence: 0.8,
            reason: [state.rawValue]
        )
    }

    private static func reminder(_ id: String, at timestamp: TimeInterval) -> ReminderDecision {
        ReminderDecision(
            id: id,
            ruleID: FocusRule.distractionReminder.id,
            sourceKind: .live,
            triggeredAt: Date(timeIntervalSince1970: timestamp),
            userState: .distracted,
            action: FocusRule.distractionReminder.action
        )
    }

    private static func diagnostic(_ id: String, at timestamp: TimeInterval) -> FaceDiagnosticEntry {
        FaceDiagnosticEntry(
            id: id,
            timestamp: Date(timeIntervalSince1970: timestamp),
            phase: .fusion,
            frameSequenceNumber: 42,
            facePresence: .present,
            gazeState: .screen,
            headPitchDegrees: 5,
            visionConfidence: 0.82,
            fusedState: .focused,
            context: .work,
            stableDurationSeconds: 12,
            reason: ["face_centered", "gaze_on_screen"]
        )
    }

    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}

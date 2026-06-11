import FocusPetCore
import FocusPetRenderer
import FocusPetResources
import Foundation

@main
enum FocusPetCoreChecks {
    static func main() {
        checkFourStateModel()
        checkStatePriority()
        checkDistractedThreshold()
        checkFrequentSwitching()
        checkInputIdleBecomesDistracted()
        checkScreenLockBecomesAway()
        checkLongInputIdleBecomesAway()
        checkIncrementalAwayRecordingMergesWithoutDuplication()
        checkNudgePolicy()
        checkOldNudgeDoesNotOverridePetState()
        checkFocusAmbientActionsCycle()
        checkPrivacy()
        checkCategoryOnlyPrivacy()
        checkSummary()
        checkFocusSessionReporting()
        checkGroupedRules()
        checkPetFallback()
        checkLocalLuoXiaoHeiActions()
        checkPetHoverPresentation()
        checkPetNonLoopFramesDoNotFreeze()
        checkPetSettingsCompatibility()
        print("FocusPetCoreChecks passed")
    }

    private static func checkFourStateModel() {
        expect(FocusState.allCases == [.focus, .distracted, .breakTime, .away], "state model should expose focus, distracted, break, away")
    }

    private static func checkStatePriority() {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 900),
            appName: "Sleep",
            bundleID: nil,
            windowTitle: nil,
            category: .ignore,
            idleSeconds: 900,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 900,
            isFocusSessionActive: true,
            isBreakActive: true,
            isSystemSleeping: true,
            source: [.systemSleep]
        )
        expect(StateEngine().evaluate(snapshot, previousStableState: .breakTime).state == .away, "system sleep should be the only automatic away state and outrank break")
    }

    private static func checkDistractedThreshold() {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 600),
            appName: "Chrome",
            bundleID: "chrome",
            windowTitle: "YouTube",
            category: .entertainment,
            idleSeconds: 2,
            switchCountLast5Min: 1,
            switchCountLast15Min: 2,
            activeCategoryDuration: 600,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        expect(decision.state == .distracted, "entertainment over threshold should be distracted")
    }

    private static func checkFrequentSwitching() {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 300),
            appName: "Finder",
            bundleID: "finder",
            windowTitle: nil,
            category: .neutral,
            idleSeconds: 1,
            switchCountLast5Min: 13,
            switchCountLast15Min: 20,
            activeCategoryDuration: 60,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        expect(StateEngine().evaluate(snapshot, previousStableState: .focus).state == .distracted, "frequent app switching should be distracted")
    }

    private static func checkInputIdleBecomesDistracted() {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 61),
            appName: "Cursor",
            bundleID: "cursor",
            windowTitle: "Project",
            category: .work,
            idleSeconds: 61,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 61,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        expect(decision.state == .distracted && decision.reason.contains(.inputIdleDistracted), "1+ minute without input should be distracted, not away")
    }

    private static func checkScreenLockBecomesAway() {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 300),
            appName: "Locked Screen",
            bundleID: nil,
            windowTitle: nil,
            category: .ignore,
            idleSeconds: 300,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 300,
            isFocusSessionActive: false,
            isBreakActive: false,
            isScreenLocked: true,
            source: [.screenLock]
        )
        let decision = StateEngine().evaluate(snapshot, previousStableState: .distracted)
        expect(decision.state == .away && decision.reason.contains(.screenLocked), "screen lock should be away and outrank distracted")
    }

    private static func checkLongInputIdleBecomesAway() {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 601),
            appName: "Cursor",
            bundleID: "cursor",
            windowTitle: "Project",
            category: .work,
            idleSeconds: 601,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 601,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let decision = StateEngine().evaluate(snapshot, previousStableState: .distracted)
        expect(decision.state == .away && decision.reason.contains(.longInputIdleAway), "10+ minutes without input should be away, not distracted")
    }

    private static func checkIncrementalAwayRecordingMergesWithoutDuplication() {
        let start = Date(timeIntervalSince1970: 0)
        let firstSnapshot = ActivitySnapshot(
            timestamp: start.addingTimeInterval(10),
            appName: "Locked Screen",
            bundleID: nil,
            windowTitle: nil,
            category: .ignore,
            idleSeconds: 10,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 10,
            isFocusSessionActive: false,
            isBreakActive: false,
            isScreenLocked: true,
            source: [.screenLock]
        )
        let secondSnapshot = ActivitySnapshot(
            timestamp: start.addingTimeInterval(15),
            appName: "Locked Screen",
            bundleID: nil,
            windowTitle: nil,
            category: .ignore,
            idleSeconds: 15,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 15,
            isFocusSessionActive: false,
            isBreakActive: false,
            isScreenLocked: true,
            source: [.screenLock]
        )
        let engine = StateEngine()
        let firstDecision = engine.evaluate(firstSnapshot, previousStableState: .distracted)
        let secondDecision = engine.evaluate(secondSnapshot, previousStableState: .away)
        var segments: [StateSegment] = []
        segments = TimeTracker(tickSeconds: 10).record(decision: firstDecision, snapshot: firstSnapshot, segments: segments)
        segments = TimeTracker(tickSeconds: 5).record(decision: secondDecision, snapshot: secondSnapshot, segments: segments)

        expect(
            segments.count == 1
                && segments[0].state == .away
                && segments[0].appName == "Locked Screen"
                && segments[0].durationSeconds == 15,
            "incremental screen-lock away recording should merge without duplicated time"
        )
    }

    private static func checkNudgePolicy() {
        let state = FocusStateSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_500),
            state: .focus,
            category: .work,
            stableDuration: 1_500,
            appName: "Cursor",
            bundleID: "cursor"
        )
        let event = NudgePolicy().nudge(for: state, previousState: .focus, now: state.timestamp, lastTriggeredAt: [:])
        expect(event?.reason == .longFocusRest && event?.petAction == .stretch, "25 minute focus should trigger rest nudge")
    }

    private static func checkOldNudgeDoesNotOverridePetState() {
        let oldNudge = NudgeEvent(
            time: Date(timeIntervalSince1970: 0),
            reason: .longFocusRest,
            state: .focus,
            appName: "Cursor",
            category: .work,
            petAction: .stretch,
            cooldownSeconds: 600,
            message: "已经专注一阵子了，要休息一下吗？"
        )

        let action = PetBehaviorPolicy().action(
            for: .away,
            previousState: .focus,
            latestNudge: oldNudge,
            now: Date(timeIntervalSince1970: 3_600)
        )
        expect(action == .sleep, "old nudge actions should expire and let the current pet state drive animation")
    }

    private static func checkFocusAmbientActionsCycle() {
        let policy = PetBehaviorPolicy()
        let actions = [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 90)
        ].map {
            policy.action(for: .focus, previousState: .focus, latestNudge: nil, now: $0)
        }

        expect(actions.contains(.blink), "stable focus should include a low-cost blink action")
        expect(actions.contains(.breath), "stable focus should include a low-cost breathing action")
        expect(actions.contains(.stretch), "stable focus should occasionally stretch")
    }

    private static func checkPrivacy() {
        let sanitized = WindowTitlePrivacy.default.sanitize("Secret Draft - YouTube")
        expect(sanitized.rawTitle == nil && sanitized.titleStored == false, "raw title should not be stored by default")
    }

    private static func checkCategoryOnlyPrivacy() {
        let sanitized = WindowTitlePrivacy(storeOnlyCategoryResult: true).sanitize("Secret Draft - YouTube")
        expect(
            sanitized.rawTitle == nil
                && sanitized.titleDisplay == nil
                && sanitized.titleHash == nil
                && sanitized.titleStored == false,
            "category-only privacy should not store title metadata"
        )
    }

    private static func checkSummary() {
        let start = Date(timeIntervalSince1970: 0)
        let segments = [
            StateSegment(start: start, end: start.addingTimeInterval(60), state: .focus, appName: "Cursor", bundleID: "cursor", category: .work, titleStored: false, titleDisplay: nil, source: [.frontmostApplication]),
            StateSegment(start: start.addingTimeInterval(60), end: start.addingTimeInterval(120), state: .breakTime, appName: "Break", bundleID: nil, category: .ignore, titleStored: false, titleDisplay: nil, source: [.breakSession])
        ]
        let summary = DailySummaryBuilder().summary(for: start, segments: segments, appUsage: [], focusSessions: [], breakSessions: [], nudges: [])
        expect(summary.focusSeconds == 60 && summary.breakSeconds == 60, "summary should aggregate focus and break")
        expect(summary.categorySeconds(.work) == 60 && summary.categorySeconds(.ignore) == 60, "summary should aggregate category usage")
    }

    private static func checkFocusSessionReporting() {
        let session = FocusSession(
            taskName: "Write",
            start: Date(timeIntervalSince1970: 0),
            targetDurationSeconds: 1_500,
            effectiveFocusSeconds: 900,
            distractedSeconds: 120,
            awaySeconds: 60,
            switchCount: 4,
            interruptionCount: 2,
            mainAppName: "Cursor"
        )
        expect(abs(session.completionRatio - 0.6) < 0.001, "focus session should expose completion ratio")
        expect(session.interruptionCount == 2 && session.mainAppName == "Cursor", "focus session should expose interruption count and main app")
    }

    private static func checkGroupedRules() {
        let rules = [
            ClassificationRule(matchKind: .appName, pattern: "DeepWork", category: .work, priority: 200),
            ClassificationRule(matchKind: .appName, pattern: "Arcade", category: .entertainment, priority: 200),
            ClassificationRule(matchKind: .appName, pattern: "Keychain", category: .ignore, priority: 200),
            ClassificationRule(matchKind: .windowTitle, pattern: "Research Brief", category: .work, priority: 200),
            ClassificationRule(matchKind: .windowTitle, pattern: "Shorts", category: .entertainment, priority: 200)
        ]
        let classifier = ActivityClassifier(rules: rules)
        expect(classifier.classify(appName: "DeepWork Studio", bundleID: nil, windowTitle: nil) == .work, "work app rules should classify work")
        expect(classifier.classify(appName: "Arcade Box", bundleID: nil, windowTitle: nil) == .entertainment, "entertainment app rules should classify entertainment")
        expect(classifier.classify(appName: "Keychain Access", bundleID: nil, windowTitle: nil) == .ignore, "ignore app rules should classify ignore")
        expect(classifier.classify(appName: "Browser", bundleID: nil, windowTitle: "Research Brief Draft") == .work, "work keyword rules should classify work")
        expect(classifier.classify(appName: "Browser", bundleID: nil, windowTitle: "Shorts - Video") == .entertainment, "entertainment keyword rules should classify entertainment")
    }

    private static func checkPetFallback() {
        let pack = PetPackCatalog.fallbackPack
        expect(PetActionResolver().animationKey(for: .nudgeStrong, in: pack) == .nudgeGentle, "strong nudge should fall back to gentle nudge")
    }

    private static func checkLocalLuoXiaoHeiActions() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("external_generated_packs/LuoXiaoHeiLocal", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("pet.json").path),
              let record = PetPackCatalog().record(at: root, isBundled: false) else {
            return
        }

        let nativeActions = Set(record.pack.animations.keys)
        let expectedNativeActions: Set<PetAction> = [.idle, .distractedLook, .nudgeStrong, .welcomeBack, .stretch, .breakRelax, .run]
        expect(expectedNativeActions.isSubset(of: nativeActions), "local Luo Xiaohei pack should keep one native action per distinct animation group")
        expect(!nativeActions.contains(.screenTransfer), "local Luo Xiaohei pack should not duplicate screenTransfer as a native animation")
        expect(!nativeActions.contains(.mouseSummon), "local Luo Xiaohei pack should not duplicate mouseSummon as a native animation")
        expect(!nativeActions.contains(.breakEnd), "local Luo Xiaohei pack should not duplicate breakEnd as a native animation")

        for action in [PetAction.dragged, .landing, .screenTransfer, .mouseSummon, .breakEnd, .sleep, .breath] {
            let resolved = PetActionResolver().animationKey(for: action, in: record.pack)
            expect(resolved != nil, "local Luo Xiaohei pack should resolve \(action.rawValue) through fallback")
            expect(!record.frameURLs(for: action).isEmpty, "local Luo Xiaohei \(action.rawValue) fallback frames should be available")
        }
    }

    private static func checkPetHoverPresentation() {
        let normalFrame = URL(fileURLWithPath: "/tmp/focus-pet-normal.png")
        let hoverFrame = URL(fileURLWithPath: "/tmp/focus-pet-hover.png")
        let renderState = PetRenderState(
            focusState: .focus,
            action: .focusStable,
            message: nil,
            hoverMessage: "专注 · Cursor",
            hoverStatusEnabled: true,
            size: 150,
            opacity: 0.94,
            animationEnabled: true,
            packName: "Focus Dino",
            frameURLs: [normalFrame],
            framesPerSecond: 6,
            loops: true,
            hoverAction: .welcomeBack,
            hoverFrameURLs: [hoverFrame],
            hoverFramesPerSecond: 8,
            hoverLoops: false
        )

        expect(renderState.displayAction(isHovering: false) == .focusStable, "normal presentation should keep the base pet action")
        expect(renderState.displayAction(isHovering: true) == .welcomeBack, "hover presentation should switch to the hover action locally")
        expect(renderState.displayFrameURLs(isHovering: true) == [hoverFrame], "hover presentation should use hover frames without rebuilding the render state")
        expect(renderState.displayFramesPerSecond(isHovering: true) == 8, "hover presentation should use hover FPS")
        expect(renderState.displayLoops(isHovering: true) == false, "hover presentation should use hover loop setting")
    }

    private static func checkPetNonLoopFramesDoNotFreeze() {
        let first = URL(fileURLWithPath: "/tmp/focus-pet-0.png")
        let second = URL(fileURLWithPath: "/tmp/focus-pet-1.png")
        let renderState = PetRenderState(
            focusState: .focus,
            action: .welcomeBack,
            message: nil,
            size: 150,
            opacity: 0.94,
            animationEnabled: true,
            packName: "Focus Dino",
            frameURLs: [first, second],
            framesPerSecond: 1,
            loops: false,
            animationStartedAt: Date(timeIntervalSince1970: 0)
        )

        expect(
            renderState.frameURL(at: Date(timeIntervalSince1970: 3), isHovering: false) == second,
            "non-loop sprite actions should keep cycling instead of freezing on the last frame"
        )
    }

    private static func checkPetSettingsCompatibility() {
        let legacyJSON = """
        {
          "opacity": 0.8,
          "size": 144,
          "animationEnabled": true,
          "hidden": false,
          "selectedPackID": "luo_xiaohei_local"
        }
        """
        guard let data = legacyJSON.data(using: .utf8),
              let settings = try? JSONDecoder().decode(PetSettings.self, from: data) else {
            expect(false, "pet settings should decode legacy JSON")
            return
        }

        expect(settings.placement == .bottomRight, "legacy pet settings should default to bottom-right placement")
        expect(settings.hoverStatusEnabled, "legacy pet settings should default to hover status enabled")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FocusPetCoreChecks failed: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }
}

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
        checkDefaultDistractedThresholds()
        checkFrequentSwitchingIsIgnored()
        checkInputIdleBecomesDistracted()
        checkRecentInputRecoversFromDistracted()
        checkScreenLockBecomesAway()
        checkLongInputIdleBecomesAway()
        checkLongIdleReclassificationBackfillsAway()
        checkIncrementalAwayRecordingMergesWithoutDuplication()
        checkNudgePolicy()
        checkOldNudgeDoesNotOverridePetState()
        checkFocusAmbientActionsCycle()
        checkPrivacy()
        checkCategoryOnlyPrivacy()
        checkSummary()
        checkFocusSessionReporting()
        checkGroupedRules()
        checkNeutralIsLegacyOnly()
        checkCatalogCoverage()
        checkExpandedCatalogRepresentativeCoverage()
        checkBrowserWebsitePriority()
        checkUserRulesOverrideCatalog()
        checkStoredBuiltInsAreFiltered()
        checkPetFallback()
        checkLocalPetPackActions()
        checkPetHoverPresentation()
        checkPetNonLoopFramesDoNotFreeze()
        checkPetSettingsCompatibility()
        checkAppSettingsCompatibility()
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

    private static func checkDefaultDistractedThresholds() {
        let idleSnapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 60),
            appName: "Cursor",
            bundleID: "cursor",
            windowTitle: "Focus Pet",
            category: .work,
            idleSeconds: 60,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 60,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let idleDecision = StateEngine().evaluate(idleSnapshot, previousStableState: .focus)
        expect(idleDecision.state == .focus, "1 minute without input should stay focused")

        let entertainmentSnapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 45),
            appName: "Chrome",
            bundleID: "chrome",
            windowTitle: "YouTube",
            category: .entertainment,
            idleSeconds: 2,
            switchCountLast5Min: 1,
            switchCountLast15Min: 2,
            activeCategoryDuration: 45,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let entertainmentDecision = StateEngine().evaluate(entertainmentSnapshot, previousStableState: .focus)
        expect(entertainmentDecision.state == .focus, "45 seconds entertainment should stay in grace")

        let distractedSnapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 60),
            appName: "Chrome",
            bundleID: "chrome",
            windowTitle: "YouTube",
            category: .entertainment,
            idleSeconds: 2,
            switchCountLast5Min: 1,
            switchCountLast15Min: 2,
            activeCategoryDuration: 60,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let distractedDecision = StateEngine().evaluate(distractedSnapshot, previousStableState: .focus)
        expect(distractedDecision.state == .distracted, "60 seconds entertainment should be distracted")
    }

    private static func checkFrequentSwitchingIsIgnored() {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 300),
            appName: "Finder",
            bundleID: "finder",
            windowTitle: nil,
            category: .neutral,
            idleSeconds: 1,
            switchCountLast5Min: 7,
            switchCountLast15Min: 12,
            activeCategoryDuration: 60,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        expect(decision.state == .focus && !decision.reason.contains(.frequentSwitching), "app switching alone should not be distracted")
    }

    private static func checkInputIdleBecomesDistracted() {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 180),
            appName: "Cursor",
            bundleID: "cursor",
            windowTitle: "Project",
            category: .work,
            idleSeconds: 180,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 180,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        expect(decision.state == .distracted && decision.reason.contains(.inputIdleDistracted), "3 minutes without input should be distracted, not away")
    }

    private static func checkRecentInputRecoversFromDistracted() {
        let neutralSnapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 70),
            appName: "Finder",
            bundleID: "finder",
            windowTitle: nil,
            category: .neutral,
            idleSeconds: 1,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 10,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let recovered = StateEngine().evaluate(neutralSnapshot, previousStableState: .distracted)
        expect(
            recovered.state == .focus && recovered.reason.contains(.recentInputRecovery),
            "recent input in a non-entertainment context should recover from distracted"
        )

        let entertainmentSnapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 80),
            appName: "Chrome",
            bundleID: "chrome",
            windowTitle: "YouTube",
            category: .entertainment,
            idleSeconds: 1,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 10,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        let stillDistracted = StateEngine().evaluate(entertainmentSnapshot, previousStableState: .distracted)
        expect(stillDistracted.state == .distracted, "recent input should not hide an active entertainment context")
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

    private static func checkLongIdleReclassificationBackfillsAway() {
        let start = Date(timeIntervalSince1970: 0)
        let segments = [
            StateSegment(
                start: start,
                end: start.addingTimeInterval(60),
                state: .focus,
                appName: "Cursor",
                bundleID: "cursor",
                category: .work,
                titleStored: false,
                titleDisplay: nil,
                source: [.frontmostApplication]
            ),
            StateSegment(
                start: start.addingTimeInterval(60),
                end: start.addingTimeInterval(600),
                state: .distracted,
                appName: "Cursor",
                bundleID: "cursor",
                category: .work,
                titleStored: false,
                titleDisplay: nil,
                source: [.idleTime]
            ),
            StateSegment(
                start: start.addingTimeInterval(600),
                end: start.addingTimeInterval(610),
                state: .away,
                appName: "Cursor",
                bundleID: "cursor",
                category: .work,
                titleStored: false,
                titleDisplay: nil,
                source: [.idleTime]
            )
        ]

        let result = TimeTracker().reclassify(
            segments: segments,
            from: start,
            to: start.addingTimeInterval(610),
            matching: [.focus, .distracted],
            as: .away,
            addingSource: .idleTime
        )

        expect(
            result.reclassifiedSeconds[.focus, default: 0] == 60
                && result.reclassifiedSeconds[.distracted, default: 0] == 540
                && result.segments.count == 1
                && result.segments[0].state == .away
                && result.segments[0].durationSeconds == 610,
            "long idle backfill should convert the already-recorded no-input window to away"
        )
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
        expect(event?.reason == .longFocusRest && event?.petIntent == .focusRestHint, "25 minute focus should trigger rest nudge intent")
    }

    private static func checkOldNudgeDoesNotOverridePetState() {
        let intent = PetBehaviorPolicy().intentKind(
            for: .away,
            previousState: .focus,
            now: Date(timeIntervalSince1970: 3_600)
        )
        expect(intent == .sleep, "old nudge actions should expire and let the current pet state drive intent")
    }

    private static func checkFocusAmbientActionsCycle() {
        let policy = PetBehaviorPolicy()
        let intents = [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 90)
        ].map {
            policy.intentKind(for: .focus, previousState: .focus, now: $0)
        }

        expect(intents.allSatisfy { $0 == .quietCompanion }, "stable focus should stay on the quiet companion intent")
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
        expect(summary.appUsage.map(\.appName) == ["Cursor"], "ignored apps should be excluded from app usage ranking")
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

    private static func checkNeutralIsLegacyOnly() {
        expect(
            ActivityCategory.userFacingClassificationCases == [.work, .entertainment, .ignore]
                && !ActivityCategory.userFacingClassificationCases.contains(.neutral),
            "neutral should not be user-facing"
        )
        expect(
            ActivityClassifier().classify(appName: "Unknown App", bundleID: "example.unknown", windowTitle: nil) == .ignore,
            "unknown apps should not create new neutral activity"
        )
    }

    private static func checkCatalogCoverage() {
        let categoryCounts = Dictionary(grouping: ActivityClassifier.defaultRules, by: { $0.category }).mapValues(\.count)
        expect(ActivityClassifier.catalogEntries.count >= 35, "catalog should be split into broad maintainable groups")
        expect(ActivityClassifier.defaultRules.count >= 1_200, "catalog should expand into a broad built-in rule set")
        expect((categoryCounts[.work] ?? 0) >= 650, "catalog should cover mainstream work tools and sites")
        expect((categoryCounts[.entertainment] ?? 0) >= 400, "catalog should cover mainstream distracting tools and sites")
        expect((categoryCounts[.ignore] ?? 0) >= 150, "catalog should cover system and background utilities")
        expect(ActivityClassifier.defaultRules.allSatisfy { $0.category != .neutral }, "catalog should not produce neutral rules")
    }

    private static func checkExpandedCatalogRepresentativeCoverage() {
        let classifier = ActivityClassifier()
        expect(
            classifier.classify(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Amazon Web Services Console") == .work,
            "AWS should stay work despite Amazon shopping rules"
        )
        expect(
            classifier.classify(appName: "Google Chrome", bundleID: "com.google.Chrome", windowTitle: "Amazon - Online Shopping") == .entertainment,
            "shopping sites should be distracting"
        )
        expect(
            classifier.classify(appName: "Google Chrome", bundleID: "com.google.Chrome", windowTitle: "Coursera Machine Learning") == .work,
            "course platforms should be work"
        )
        expect(
            classifier.classify(appName: "Xcode", bundleID: nil, windowTitle: nil) == .work,
            "short social names should not interfere with Xcode"
        )
        expect(
            classifier.classify(appName: "X", bundleID: nil, windowTitle: nil) == .ignore,
            "single-letter app names should not drive classification"
        )
        expect(
            classifier.classify(appName: "Discord", bundleID: nil, windowTitle: nil) == .entertainment,
            "social chat apps should be covered"
        )
        expect(
            classifier.classify(appName: "CleanShot X", bundleID: nil, windowTitle: nil) == .ignore,
            "utility apps should be ignored"
        )
    }

    private static func checkBrowserWebsitePriority() {
        let classifier = ActivityClassifier()
        expect(
            classifier.classify(appName: "Google Chrome", bundleID: "com.google.Chrome", windowTitle: "YouTube - Home") == .entertainment,
            "website/title rules should outrank browser app defaults"
        )
        expect(
            classifier.classify(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "GitHub Pull Request") == .work,
            "work website/title rules should outrank browser app defaults"
        )
        expect(
            classifier.classify(appName: "Microsoft Edge", bundleID: "com.microsoft.edgemac", windowTitle: "New Tab") == .ignore,
            "browser apps without a matching site should not actively decide focus"
        )
    }

    private static func checkUserRulesOverrideCatalog() {
        let classifier = ActivityClassifier(rules: [
            ClassificationRule(matchKind: .windowTitle, pattern: "YouTube", category: .work, priority: 1)
        ])
        expect(
            classifier.classify(appName: "Google Chrome", bundleID: "com.google.Chrome", windowTitle: "YouTube - Course") == .work,
            "user exceptions should override built-in catalog rules"
        )
    }

    private static func checkStoredBuiltInsAreFiltered() {
        expect(
            ActivityClassifier.userRules(fromStored: ActivityClassifier.defaultRules).isEmpty,
            "stored built-in defaults should not be shown as user exceptions"
        )
    }

    private static func checkPetFallback() {
        let pack = PetPackCatalog.fallbackPack
        expect(PetActionResolver().animationKey(for: .nudgeStrong, in: pack) == .nudgeGentle, "strong nudge should fall back to gentle nudge")
    }

    private static func checkLocalPetPackActions() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("external_generated_packs", isDirectory: true)
        let records = PetPackCatalog().availablePacks(userRootURL: root)
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        guard let luo = recordsByID[PetPackCatalog.localLuoXiaoHeiPackID],
              let xiaodai = recordsByID[PetPackCatalog.localXiaoDaiPackID],
              let pixel = recordsByID[PetPackCatalog.localPixelCatMemePackID] else {
            return
        }

        expect(luo.validation.isValid, "local Luo Xiaohei pack should validate")
        expect(xiaodai.validation.isValid, "local XiaoDai pack should validate")
        expect(pixel.validation.isValid, "local Pixel Cat Meme pack should validate")
        expect(luo.previewSourceActions.count == 7, "Luo Xiaohei should expose original GIF action names")
        expect(xiaodai.previewSourceActions.count == 23, "XiaoDai should expose original act_conf action names")
        expect(pixel.previewSourceActions.count == 22, "Pixel Cat should expose original act_conf action names")
        expect(xiaodai.sourceAction(id: "patpat1") != nil, "XiaoDai should keep original patpat1 action name")
        expect(pixel.sourceAction(id: "yb") != nil, "Pixel Cat should keep original yb action name")

        expect(luo.pack.animations[.run] == nil, "Luo Xiaohei should not pretend food/rest assets are run movement")
        expect(luo.pack.animations[.screenTransfer] == nil, "Luo Xiaohei should not duplicate screen transfer without a matching source action")
        expect(luo.pack.animations[.breakRelax]?.folder == "guitar", "Luo Xiaohei break should use the original guitar action")
        expect(luo.pack.animations[.breakEnd]?.folder == "eat_drumstick", "Luo Xiaohei break end should use the original food action")

        expect(xiaodai.pack.animations[.focusStart]?.folder == "focus", "XiaoDai work should map to the source focus action")
        expect(xiaodai.pack.animations[.distractedLook]?.folder == "disturbed", "XiaoDai distracted state should map to disturbed")
        expect(xiaodai.pack.animations[.screenTransfer]?.folder == "screen_transfer", "XiaoDai screen transfer should map to edge behavior")

        expect(pixel.pack.animations[.focusStart]?.folder == "work", "Pixel Cat work should map to the source work action")
        expect(pixel.pack.animations[.nudgeStrong]?.folder == "nudge_strong", "Pixel Cat strong nudge should map to ybfist")
        expect(pixel.pack.animations[.mouseSummon]?.folder == "mouse_summon", "Pixel Cat mouse summon should map to feed interaction")

        for record in [luo, xiaodai, pixel] {
            for action in [PetAction.idle, .focusStart, .breath, .distractedLook, .nudgeGentle, .nudgeStrong, .breakRelax, .sleep, .welcomeBack, .run, .screenTransfer, .mouseSummon] {
                expect(!record.frameURLs(for: action).isEmpty, "\(record.id) should resolve \(action.rawValue) frames")
            }
        }

        for action in [PetAction.focusStart, .sleep, .nudgeGentle, .nudgeStrong, .breakRelax, .breakEnd, .welcomeBack, .landing, .mouseSummon] {
            expect(pixel.audioURL(for: action) != nil, "Pixel Cat should resolve audio for \(action.rawValue)")
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

        expect(renderState.displayIntent(isHovering: false) == .quietCompanion, "normal presentation should keep the base pet intent")
        expect(renderState.displayIntent(isHovering: true) == .welcomeBack, "hover presentation should switch to the hover intent locally")
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
        expect(settings.idleSourceActionIDByPack.isEmpty, "legacy pet settings should default to no custom idle source action")
        expect(settings.intentSourceActionIDByPack.isEmpty, "legacy pet settings should default to no custom intent mappings")
    }

    private static func checkAppSettingsCompatibility() {
        let legacyJSON = """
        {
          "hasCompletedOnboarding": true,
          "focusTargetMinutes": 25,
          "breakMinutes": 5,
          "autoStartBreak": true
        }
        """
        guard let data = legacyJSON.data(using: .utf8),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            expect(false, "app settings should decode legacy JSON")
            return
        }

        expect(settings.judgment.inputIdleDistractedSeconds == 180, "legacy app settings should default input idle threshold")
        expect(settings.judgment.entertainmentDistractedSeconds == 60, "legacy app settings should default entertainment threshold")
        expect(settings.judgment.focusRecoverySeconds == 10, "legacy app settings should default focus recovery threshold")
        expect(settings.judgment.idleAwaySeconds == 600, "legacy app settings should default idle away threshold")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FocusPetCoreChecks failed: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }
}

import FocusPetCore
import FocusPetStorage
import Foundation

struct FocusPetMVPProbe {
    func cursorWorkForAnHourIsFocus() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 3_600),
            appName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92",
            windowTitle: "Focus Pet project",
            category: .work,
            idleSeconds: 12,
            switchCountLast5Min: 2,
            switchCountLast15Min: 5,
            activeCategoryDuration: 3_600,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        return StateEngine().evaluate(snapshot, previousStableState: .focus).state == .focus
    }

    func youtubeForTenMinutesIsDistracted() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 600),
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube",
            category: .entertainment,
            idleSeconds: 6,
            switchCountLast5Min: 1,
            switchCountLast15Min: 3,
            activeCategoryDuration: 600,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        return decision.state == .distracted && decision.reason.contains(.entertainmentStable)
    }

    func manualBreakOutranksEntertainment() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 700),
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube",
            category: .entertainment,
            idleSeconds: 20,
            switchCountLast5Min: 2,
            switchCountLast15Min: 4,
            activeCategoryDuration: 800,
            isFocusSessionActive: false,
            isBreakActive: true
        )

        return StateEngine().evaluate(snapshot, previousStableState: .focus).state == .breakTime
    }

    func idleOneMinuteIsDistracted() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 61),
            appName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92",
            windowTitle: "Focus Pet project",
            category: .work,
            idleSeconds: 61,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 61,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        return decision.state == .distracted && decision.reason.contains(.inputIdleDistracted)
    }

    func systemSleepIsAway() -> Bool {
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
            isFocusSessionActive: false,
            isBreakActive: true,
            isSystemSleeping: true,
            source: [.systemSleep]
        )

        return StateEngine().evaluate(snapshot, previousStableState: .breakTime).state == .away
    }

    func screenLockIsAway() -> Bool {
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
        return decision.state == .away && decision.reason.contains(.screenLocked)
    }

    func longInputIdleIsAway() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 601),
            appName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92",
            windowTitle: "Focus Pet project",
            category: .work,
            idleSeconds: 601,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 601,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        let decision = StateEngine().evaluate(snapshot, previousStableState: .distracted)
        return decision.state == .away && decision.reason.contains(.longInputIdleAway)
    }

    func incrementalAwayRecordingMergesWithoutDuplication() -> Bool {
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

        return segments.count == 1
            && segments[0].state == .away
            && segments[0].appName == "Locked Screen"
            && segments[0].durationSeconds == 15
    }

    func frequentSwitchingBecomesDistracted() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 300),
            appName: "Finder",
            bundleID: "com.apple.finder",
            windowTitle: nil,
            category: .neutral,
            idleSeconds: 3,
            switchCountLast5Min: 13,
            switchCountLast15Min: 24,
            activeCategoryDuration: 120,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        return decision.state == .distracted && decision.reason.contains(.frequentSwitching)
    }

    func focusTwentyFiveMinutesTriggersRestNudge() -> Bool {
        let state = FocusStateSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_500),
            state: .focus,
            category: .work,
            stableDuration: 1_500,
            appName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92"
        )

        let event = NudgePolicy().nudge(
            for: state,
            previousState: .focus,
            now: Date(timeIntervalSince1970: 1_500),
            lastTriggeredAt: [:]
        )

        return event?.reason == .longFocusRest && event?.petAction == .stretch
    }

    func windowTitlePrivacyDoesNotStoreRawTitleByDefault() -> Bool {
        let sanitized = WindowTitlePrivacy.default.sanitize("Secret Draft - YouTube")
        return sanitized.rawTitle == nil
            && sanitized.titleStored == false
            && sanitized.titleDisplay == "Secret Draft - YouTube".privacyRedactedTitle
    }

    func onlyCategoryPrivacyStoresNoTitleMetadata() -> Bool {
        let sanitized = WindowTitlePrivacy(storeOnlyCategoryResult: true).sanitize("Secret Draft - YouTube")
        return sanitized.rawTitle == nil
            && sanitized.titleDisplay == nil
            && sanitized.titleHash == nil
            && sanitized.titleStored == false
    }

    func timelineTracksFourStateTotals() -> Bool {
        let start = Date(timeIntervalSince1970: 0)
        let segments = [
            StateSegment(id: "focus", start: start, end: start.addingTimeInterval(600), state: .focus, appName: "Cursor", bundleID: "cursor", category: .work, titleStored: false, titleDisplay: nil, source: [.frontmostApplication]),
            StateSegment(id: "distracted", start: start.addingTimeInterval(600), end: start.addingTimeInterval(900), state: .distracted, appName: "Chrome", bundleID: "chrome", category: .entertainment, titleStored: false, titleDisplay: nil, source: [.windowTitle]),
            StateSegment(id: "break", start: start.addingTimeInterval(900), end: start.addingTimeInterval(1_200), state: .breakTime, appName: "Break", bundleID: nil, category: .ignore, titleStored: false, titleDisplay: nil, source: [.breakSession]),
            StateSegment(id: "away", start: start.addingTimeInterval(1_200), end: start.addingTimeInterval(1_800), state: .away, appName: "Away", bundleID: nil, category: .ignore, titleStored: false, titleDisplay: nil, source: [.idleTime])
        ]

        let summary = DailySummaryBuilder().summary(for: start, segments: segments, appUsage: [], focusSessions: [], breakSessions: [], nudges: [])
        return summary.focusSeconds == 600
            && summary.distractedSeconds == 300
            && summary.breakSeconds == 300
            && summary.awaySeconds == 600
            && summary.categorySeconds(.work) == 600
            && summary.categorySeconds(.entertainment) == 300
            && summary.categorySeconds(.ignore) == 900
    }

    func legacyPetSettingsDefaultToInteractivePlacement() -> Bool {
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
            return false
        }

        return settings.placement == .bottomRight
            && settings.customOriginX == nil
            && settings.customOriginY == nil
            && settings.hoverStatusEnabled
    }

    func focusSessionReportsCompletionAndDecodesLegacyJSON() -> Bool {
        let session = FocusSession(
            taskName: "Write",
            start: Date(timeIntervalSince1970: 0),
            targetDurationSeconds: 1_500,
            effectiveFocusSeconds: 900,
            distractedSeconds: 120,
            awaySeconds: 60,
            switchCount: 5,
            interruptionCount: 2,
            mainAppName: "Cursor"
        )
        guard abs(session.completionRatio - 0.6) < 0.001,
              session.effectiveSeconds == 1_080,
              session.mainAppName == "Cursor" else {
            return false
        }

        let legacyJSON = """
        {
          "id": "legacy",
          "taskName": "Legacy",
          "start": "1970-01-01T00:00:00Z",
          "targetDurationSeconds": 1500,
          "effectiveFocusSeconds": 300,
          "distractedSeconds": 60,
          "awaySeconds": 0,
          "switchCount": 3,
          "completed": false,
          "status": "active",
          "autoStartBreak": true,
          "breakDurationSeconds": 300
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = legacyJSON.data(using: .utf8),
              let decoded = try? decoder.decode(FocusSession.self, from: data) else {
            return false
        }
        return decoded.interruptionCount == 0 && decoded.mainAppName == nil
    }

    func groupedRulesClassifyExpectedCategories() -> Bool {
        let rules = [
            ClassificationRule(matchKind: .appName, pattern: "DeepWork", category: .work, priority: 200),
            ClassificationRule(matchKind: .appName, pattern: "Arcade", category: .entertainment, priority: 200),
            ClassificationRule(matchKind: .appName, pattern: "Keychain", category: .ignore, priority: 200),
            ClassificationRule(matchKind: .windowTitle, pattern: "Research Brief", category: .work, priority: 200),
            ClassificationRule(matchKind: .windowTitle, pattern: "Shorts", category: .entertainment, priority: 200)
        ]
        let classifier = ActivityClassifier(rules: rules)

        return classifier.classify(appName: "DeepWork Studio", bundleID: nil, windowTitle: nil) == .work
            && classifier.classify(appName: "Arcade Box", bundleID: nil, windowTitle: nil) == .entertainment
            && classifier.classify(appName: "Keychain Access", bundleID: nil, windowTitle: nil) == .ignore
            && classifier.classify(appName: "Browser", bundleID: nil, windowTitle: "Research Brief Draft") == .work
            && classifier.classify(appName: "Browser", bundleID: nil, windowTitle: "Shorts - Video") == .entertainment
    }

    func redactedExportRemovesTitleMetadata() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("focus-pet-redacted-export-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let start = Date(timeIntervalSince1970: 0)
        let snapshot = LocalStoreSnapshot(
            settings: AppSettings(privacy: WindowTitlePrivacy(storeRawTitle: true)),
            classificationRules: [],
            stateSegments: [
                StateSegment(
                    start: start,
                    end: start.addingTimeInterval(60),
                    state: .focus,
                    appName: "Cursor",
                    bundleID: "cursor",
                    category: .work,
                    titleStored: true,
                    titleDisplay: "Secret Draft",
                    source: [.windowTitle]
                )
            ],
            appUsage: [],
            focusSessions: [],
            breakSessions: [],
            nudges: []
        )
        guard let url = LocalStore(rootURL: root).exportSnapshot(snapshot, redacted: true),
              let data = try? Data(contentsOf: url) else {
            return false
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(LocalStoreSnapshot.self, from: data),
              let segment = decoded.stateSegments.first else {
            return false
        }
        return decoded.settings.privacy.storeRawTitle == false
            && decoded.settings.privacy.storeOnlyCategoryResult
            && segment.titleStored == false
            && segment.titleDisplay == nil
    }

    func overnightIdleIsNotHeuristicallyConvertedToAway() -> Bool {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(6 * 60 * 60)
        let snapshot = LocalStoreSnapshot(
            stateSegments: [
                StateSegment(
                    id: "overnight-focus",
                    start: start,
                    end: end,
                    state: .focus,
                    appName: "loginwindow",
                    bundleID: nil,
                    category: .neutral,
                    titleStored: false,
                    titleDisplay: nil,
                    source: [.frontmostApplication, .idleTime]
                )
            ],
            appUsage: [
                AppUsageSegment(start: start, end: end, appName: "loginwindow", bundleID: nil, category: .neutral)
            ],
            focusSessions: [
                FocusSession(
                    taskName: "Overnight",
                    start: start,
                    targetDurationSeconds: 1_500,
                    end: end,
                    effectiveFocusSeconds: Int(end.timeIntervalSince(start)),
                    awaySeconds: 0,
                    status: .completed
                )
            ],
            nudges: [
                NudgeEvent(
                    time: start.addingTimeInterval(2 * 60 * 60),
                    reason: .veryLongFocusRest,
                    state: .focus,
                    appName: "Cursor",
                    category: .work,
                    petAction: .stretch,
                    cooldownSeconds: 600,
                    message: "已经专注很久了，要休息一下吗？"
                )
            ]
        )

        return snapshot.stateSegments.count == 1
            && snapshot.stateSegments[0].state == .focus
            && snapshot.appUsage.count == 1
            && snapshot.nudges.count == 1
            && snapshot.focusSessions[0].awaySeconds == 0
    }
}

private let runFocusPetMVPProbe: Void = {
    let probe = FocusPetMVPProbe()
    precondition(probe.cursorWorkForAnHourIsFocus(), "Cursor for 60 minutes should be focus")
    precondition(probe.youtubeForTenMinutesIsDistracted(), "YouTube for 10 minutes should be distracted")
    precondition(probe.manualBreakOutranksEntertainment(), "manual break should outrank entertainment")
    precondition(probe.idleOneMinuteIsDistracted(), "1+ minute without input should be distracted")
    precondition(probe.systemSleepIsAway(), "system sleep should be away")
    precondition(probe.screenLockIsAway(), "screen lock should be away")
    precondition(probe.longInputIdleIsAway(), "long input idle should be away")
    precondition(probe.incrementalAwayRecordingMergesWithoutDuplication(), "incremental away recording should not duplicate screen lock time")
    precondition(probe.frequentSwitchingBecomesDistracted(), "12+ app switches in 5 minutes should be distracted")
    precondition(probe.focusTwentyFiveMinutesTriggersRestNudge(), "25 minutes focus should trigger rest nudge")
    precondition(probe.windowTitlePrivacyDoesNotStoreRawTitleByDefault(), "default privacy should not store raw titles")
    precondition(probe.onlyCategoryPrivacyStoresNoTitleMetadata(), "category-only privacy should remove title metadata")
    precondition(probe.timelineTracksFourStateTotals(), "daily summary should aggregate all four states")
    precondition(probe.legacyPetSettingsDefaultToInteractivePlacement(), "legacy pet settings should decode with interaction defaults")
    precondition(probe.focusSessionReportsCompletionAndDecodesLegacyJSON(), "focus sessions should expose completion and decode legacy JSON")
    precondition(probe.groupedRulesClassifyExpectedCategories(), "grouped rules should classify apps and title keywords")
    precondition(probe.redactedExportRemovesTitleMetadata(), "redacted export should remove title metadata")
    precondition(probe.overnightIdleIsNotHeuristicallyConvertedToAway(), "stored history should not be heuristically rewritten")
}()

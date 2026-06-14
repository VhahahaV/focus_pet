import FocusPetCore
import FocusPetStorage
import CoreGraphics
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

    func idleThreeMinutesIsDistracted() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 180),
            appName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92",
            windowTitle: "Focus Pet project",
            category: .work,
            idleSeconds: 180,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 180,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        return decision.state == .distracted && decision.reason.contains(.inputIdleDistracted)
    }

    func idleOneMinuteStaysFocused() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 60),
            appName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92",
            windowTitle: "Focus Pet project",
            category: .work,
            idleSeconds: 60,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 60,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        return decision.state == .focus && !decision.reason.contains(.inputIdleDistracted)
    }

    func entertainmentFortyFiveSecondsStaysInGrace() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 45),
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube",
            category: .entertainment,
            idleSeconds: 4,
            switchCountLast5Min: 1,
            switchCountLast15Min: 2,
            activeCategoryDuration: 45,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        return decision.state == .focus && decision.reason.contains(.entertainmentGrace)
    }

    func entertainmentOneMinuteIsDistracted() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 60),
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube",
            category: .entertainment,
            idleSeconds: 4,
            switchCountLast5Min: 1,
            switchCountLast15Min: 2,
            activeCategoryDuration: 60,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        return decision.state == .distracted && decision.reason.contains(.entertainmentStable)
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

    func longIdleBackfillConvertsNoInputWindowToAway() -> Bool {
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

        return result.reclassifiedSeconds[.focus, default: 0] == 60
            && result.reclassifiedSeconds[.distracted, default: 0] == 540
            && result.segments.count == 1
            && result.segments[0].state == .away
            && result.segments[0].durationSeconds == 610
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

    func frequentSwitchingDoesNotBecomeDistracted() -> Bool {
        let snapshot = ActivitySnapshot(
            timestamp: Date(timeIntervalSince1970: 300),
            appName: "Finder",
            bundleID: "com.apple.finder",
            windowTitle: nil,
            category: .neutral,
            idleSeconds: 3,
            switchCountLast5Min: 7,
            switchCountLast15Min: 12,
            activeCategoryDuration: 120,
            isFocusSessionActive: false,
            isBreakActive: false
        )

        let decision = StateEngine().evaluate(snapshot, previousStableState: .focus)
        return decision.state == .focus && !decision.reason.contains(.frequentSwitching)
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

        return event?.reason == .longFocusRest && event?.petIntent == .focusRestHint
    }

    func legacyReminderSettingsDefaultToCustomizableNudgeParameters() -> Bool {
        let legacyJSON = """
        {
          "enablePetBubbles": true,
          "enableSystemNotifications": false
        }
        """
        guard let data = legacyJSON.data(using: .utf8),
              let settings = try? JSONDecoder().decode(ReminderSettings.self, from: data) else {
            return false
        }

        return settings.pauseMinutes == 30
            && settings.enableDistractedNudges
            && settings.enableFocusRestNudges
            && settings.enableWelcomeBackNudges
            && settings.lightDistractedMinutes == 8
            && settings.strongDistractedMinutes == 15
            && settings.longFocusMinutes == 25
            && settings.veryLongFocusMinutes == 60
            && settings.cooldownMinutes == 10
            && settings.nudgePolicyThresholds.lightDistractedSeconds == 480
            && settings.nudgePolicyThresholds.cooldownSeconds == 600
    }

    func reminderSettingsCustomizeNudgePolicyAndClampValues() -> Bool {
        let custom = ReminderSettings(
            pauseMinutes: 45,
            lightDistractedMinutes: 2,
            strongDistractedMinutes: 4,
            longFocusMinutes: 40,
            veryLongFocusMinutes: 80,
            cooldownMinutes: 3
        )
        let distractedState = FocusStateSnapshot(
            timestamp: Date(timeIntervalSince1970: 120),
            state: .distracted,
            category: .entertainment,
            stableDuration: 120,
            appName: "Browser",
            bundleID: "browser"
        )
        let focusState = FocusStateSnapshot(
            timestamp: Date(timeIntervalSince1970: 2_400),
            state: .focus,
            category: .work,
            stableDuration: 2_400,
            appName: "Cursor",
            bundleID: "cursor"
        )
        let policy = NudgePolicy(thresholds: custom.nudgePolicyThresholds)
        let distractedEvent = policy.nudge(for: distractedState, previousState: .focus, now: distractedState.timestamp, lastTriggeredAt: [:])
        let focusEvent = policy.nudge(for: focusState, previousState: .focus, now: focusState.timestamp, lastTriggeredAt: [:])

        let clamped = ReminderSettings(
            pauseMinutes: 1,
            enableDistractedNudges: false,
            enableFocusRestNudges: false,
            enableWelcomeBackNudges: false,
            lightDistractedMinutes: 99,
            strongDistractedMinutes: 2,
            longFocusMinutes: 2,
            veryLongFocusMinutes: 1,
            cooldownMinutes: 0
        )

        return custom.pauseMinutes == 45
            && custom.nudgePolicyThresholds.strongDistractedSeconds == 240
            && distractedEvent?.reason == .distractedOverThreshold
            && focusEvent?.reason == .longFocusRest
            && clamped.pauseMinutes == 5
            && clamped.lightDistractedMinutes == 60
            && clamped.strongDistractedMinutes == 60
            && clamped.longFocusMinutes == 5
            && clamped.veryLongFocusMinutes == 5
            && clamped.cooldownMinutes == 1
            && !clamped.allows(.distractedStrong)
            && !clamped.allows(.longFocusRest)
            && !clamped.allows(.welcomeBack)
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

    func ignoredAppsAreExcludedFromAppUsageRanking() -> Bool {
        let start = Date(timeIntervalSince1970: 0)
        let appUsage = [
            AppUsageSegment(start: start, end: start.addingTimeInterval(3_600), appName: "Locked Screen", bundleID: nil, category: .ignore),
            AppUsageSegment(start: start, end: start.addingTimeInterval(900), appName: "Cursor", bundleID: "cursor", category: .work)
        ]

        let summary = DailySummaryBuilder().summary(for: start, segments: [], appUsage: appUsage, focusSessions: [], breakSessions: [], nudges: [])
        return summary.appUsage.count == 1
            && summary.appUsage.first?.appName == "Cursor"
            && summary.categorySeconds(.ignore) == 3_600
            && summary.categorySeconds(.work) == 900
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
            && settings.intentSourceActionIDByPack.isEmpty
    }

    func legacyAppSettingsDefaultJudgmentParameters() -> Bool {
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
            return false
        }

        return settings.judgment.inputIdleDistractedSeconds == 180
            && settings.judgment.entertainmentDistractedSeconds == 60
            && settings.judgment.focusRecoverySeconds == 10
            && settings.judgment.idleAwaySeconds == 600
            && settings.retention.inputActivityRetentionDays == 30
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

    func neutralIsLegacyOnlyAndHiddenFromUserChoices() -> Bool {
        ActivityCategory.userFacingClassificationCases == [.work, .entertainment, .ignore]
            && !ActivityCategory.userFacingClassificationCases.contains(.neutral)
            && ActivityClassifier().classify(appName: "Unknown App", bundleID: "example.unknown", windowTitle: nil) == .ignore
    }

    func catalogIsLoadedAndBroadEnough() -> Bool {
        let categoryCounts = Dictionary(grouping: ActivityClassifier.defaultRules, by: { $0.category }).mapValues(\.count)
        return ActivityClassifier.catalogEntries.count >= 35
            && ActivityClassifier.defaultRules.count >= 1_200
            && (categoryCounts[.work] ?? 0) >= 650
            && (categoryCounts[.entertainment] ?? 0) >= 400
            && (categoryCounts[.ignore] ?? 0) >= 150
            && ActivityClassifier.defaultRules.allSatisfy { $0.category != .neutral }
    }

    func expandedCatalogClassifiesRepresentativeCoverage() -> Bool {
        let classifier = ActivityClassifier()
        return classifier.classify(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            windowTitle: "Amazon Web Services Console"
        ) == .work
            && classifier.classify(
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                windowTitle: "Amazon - Online Shopping"
            ) == .entertainment
            && classifier.classify(
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                windowTitle: "Coursera Machine Learning"
            ) == .work
            && classifier.classify(
                appName: "Xcode",
                bundleID: nil,
                windowTitle: nil
            ) == .work
            && classifier.classify(
                appName: "X",
                bundleID: nil,
                windowTitle: nil
            ) == .ignore
            && classifier.classify(
                appName: "Discord",
                bundleID: nil,
                windowTitle: nil
            ) == .entertainment
            && classifier.classify(
                appName: "CleanShot X",
                bundleID: nil,
                windowTitle: nil
            ) == .ignore
    }

    func browserWebsiteRulesOutrankBrowserAppRules() -> Bool {
        let classifier = ActivityClassifier()
        return classifier.classify(
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube - Home"
        ) == .entertainment
            && classifier.classify(
                appName: "Safari",
                bundleID: "com.apple.Safari",
                windowTitle: "GitHub Pull Request"
            ) == .work
            && classifier.classify(
                appName: "Microsoft Edge",
                bundleID: "com.microsoft.edgemac",
                windowTitle: "New Tab"
            ) == .ignore
    }

    func userRuleOverridesCatalog() -> Bool {
        let classifier = ActivityClassifier(rules: [
            ClassificationRule(matchKind: .windowTitle, pattern: "YouTube", category: .work, priority: 1)
        ])
        return classifier.classify(
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube - Course"
        ) == .work
    }

    func builtInRulesAreFilteredFromStoredUserRules() -> Bool {
        ActivityClassifier.userRules(fromStored: ActivityClassifier.defaultRules).isEmpty
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

    func inputActivityRecorderMergesBucketsAndClampsCounts() -> Bool {
        let recorder = InputActivityRecorder(bucketSeconds: 60)
        let start = Date(timeIntervalSince1970: 0)
        let seeded = [
            InputActivityBucket(
                start: start,
                end: start.addingTimeInterval(60),
                keyboardCount: -5,
                pointerCount: 2,
                switchCount: -1
            )
        ]

        let first = recorder.record(
            now: start.addingTimeInterval(62),
            keyboardCount: 3,
            pointerCount: 4,
            switchCount: 1,
            buckets: seeded
        )
        let second = recorder.record(
            now: start.addingTimeInterval(88),
            keyboardCount: 1,
            pointerCount: 0,
            switchCount: 2,
            buckets: first
        )

        guard second.count == 2,
              second[0].keyboardCount == 0,
              second[0].pointerCount == 2,
              second[0].switchCount == 0 else {
            return false
        }

        return second[1].start == start.addingTimeInterval(60)
            && second[1].end == start.addingTimeInterval(120)
            && second[1].keyboardCount == 4
            && second[1].pointerCount == 4
            && second[1].switchCount == 3
            && second[1].totalInputCount == 8
    }

    func localStorePersistsInputActivityAndDecodesLegacySnapshots() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("focus-pet-input-activity-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let start = Date(timeIntervalSince1970: 120)
        let snapshot = LocalStoreSnapshot(
            inputActivity: [
                InputActivityBucket(
                    start: start,
                    end: start.addingTimeInterval(60),
                    keyboardCount: 12,
                    pointerCount: 7,
                    switchCount: 2
                )
            ]
        )
        let store = LocalStore(rootURL: root)
        store.saveSnapshot(snapshot)
        let loaded = store.loadSnapshot()

        let legacyJSON = """
        {
          "settings": {},
          "classificationRules": [],
          "stateSegments": [],
          "appUsage": [],
          "focusSessions": [],
          "breakSessions": [],
          "nudges": []
        }
        """
        guard let data = legacyJSON.data(using: .utf8),
              let decodedLegacy = try? JSONDecoder().decode(LocalStoreSnapshot.self, from: data) else {
            return false
        }

        return loaded.inputActivity == snapshot.inputActivity
            && decodedLegacy.inputActivity.isEmpty
    }

    func retentionPrunesInputActivityBuckets() -> Bool {
        let now = Date(timeIntervalSince1970: 10 * 86_400)
        let old = InputActivityBucket(
            start: now.addingTimeInterval(-3 * 86_400),
            end: now.addingTimeInterval(-3 * 86_400 + 60),
            keyboardCount: 1
        )
        let recent = InputActivityBucket(
            start: now.addingTimeInterval(-3_600),
            end: now.addingTimeInterval(-3_540),
            pointerCount: 2
        )
        let pruned = DataRetentionManager().prune(
            now: now,
            settings: DataRetentionSettings(inputActivityRetentionDays: 1),
            stateSegments: [],
            appUsage: [],
            inputActivity: [old, recent],
            focusSessions: [],
            breakSessions: [],
            nudges: []
        )

        return pruned.inputActivity == [recent]
            && pruned.result.removedInputActivityBuckets == 1
            && pruned.result.totalRemoved == 1
    }

    func inputTimelineSnapshotAggregatesInputAndSmoothsApps() -> Bool {
        let start = Date(timeIntervalSince1970: 600)
        let now = start.addingTimeInterval(600)
        let snapshot = InputTimelineSnapshot(
            windowSeconds: 600,
            stateSegments: [
                StateSegment(
                    start: start,
                    end: start.addingTimeInterval(300),
                    state: .focus,
                    appName: "Codex",
                    bundleID: "codex",
                    category: .work,
                    titleStored: false,
                    titleDisplay: nil,
                    source: [.frontmostApplication]
                ),
                StateSegment(
                    start: start.addingTimeInterval(300),
                    end: now,
                    state: .breakTime,
                    appName: "Break",
                    bundleID: nil,
                    category: .ignore,
                    titleStored: false,
                    titleDisplay: nil,
                    source: [.breakSession]
                )
            ],
            appUsage: [
                AppUsageSegment(start: start, end: start.addingTimeInterval(200), appName: "Codex", bundleID: "codex", category: .work),
                AppUsageSegment(start: start.addingTimeInterval(200), end: start.addingTimeInterval(220), appName: "Finder", bundleID: "finder", category: .ignore),
                AppUsageSegment(start: start.addingTimeInterval(220), end: start.addingTimeInterval(400), appName: "Codex", bundleID: "codex", category: .work),
                AppUsageSegment(start: start.addingTimeInterval(400), end: now, appName: "Safari", bundleID: "safari", category: .work)
            ],
            inputActivity: [
                InputActivityBucket(start: start, end: start.addingTimeInterval(60), keyboardCount: 2, pointerCount: 1, switchCount: 1),
                InputActivityBucket(start: start.addingTimeInterval(60), end: start.addingTimeInterval(120), keyboardCount: 3, pointerCount: 0, switchCount: 2)
            ],
            now: now
        )

        return snapshot.keyboardCount == 5
            && snapshot.pointerCount == 1
            && snapshot.switchCount == 3
            && snapshot.inputBars.count == 2
            && snapshot.switchMarkers.count == 2
            && snapshot.stateDurations[.focus] == 300
            && snapshot.stateDurations[.breakTime] == 300
            && snapshot.appSegments.count == 2
            && snapshot.appSegments[0].appName == "Codex"
            && Int(snapshot.appSegments[0].duration.rounded()) == 400
            && snapshot.appSegments[1].appName == "Safari"
    }

    func inputTimelineSnapshotSmoothsTinyStateFragments() -> Bool {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(7_200)
        let snapshot = InputTimelineSnapshot(
            windowSeconds: 7_200,
            stateSegments: [
                StateSegment(start: start, end: start.addingTimeInterval(3_000), state: .focus, appName: "Codex", bundleID: "codex", category: .work, titleStored: false, titleDisplay: nil, source: [.frontmostApplication]),
                StateSegment(start: start.addingTimeInterval(3_000), end: start.addingTimeInterval(3_020), state: .distracted, appName: "Browser", bundleID: "browser", category: .entertainment, titleStored: false, titleDisplay: nil, source: [.windowTitle]),
                StateSegment(start: start.addingTimeInterval(3_020), end: start.addingTimeInterval(6_600), state: .focus, appName: "Codex", bundleID: "codex", category: .work, titleStored: false, titleDisplay: nil, source: [.frontmostApplication]),
                StateSegment(start: start.addingTimeInterval(6_600), end: now, state: .breakTime, appName: "Break", bundleID: nil, category: .ignore, titleStored: false, titleDisplay: nil, source: [.breakSession])
            ],
            appUsage: [],
            inputActivity: [],
            now: now
        )

        return snapshot.stateDurations[.distracted] == 20
            && snapshot.stateRanges.count == 2
            && snapshot.stateRanges[0].state == .focus
            && snapshot.stateRanges[1].state == .breakTime
    }

    func inputWorkloadSummaryAggregatesReadableMetrics() -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let day = Date(timeIntervalSince1970: 86_400)
        let start = calendar.startOfDay(for: day)
        let summary = InputWorkloadSummary(
            dayContaining: day,
            inputActivity: [
                InputActivityBucket(
                    start: start.addingTimeInterval(-60),
                    end: start,
                    keyboardCount: 99,
                    pointerCount: 99,
                    switchCount: 99
                ),
                InputActivityBucket(
                    start: start.addingTimeInterval(60),
                    end: start.addingTimeInterval(120),
                    keyboardCount: 12,
                    pointerCount: 4,
                    switchCount: 2
                ),
                InputActivityBucket(
                    start: start.addingTimeInterval(180),
                    end: start.addingTimeInterval(240),
                    keyboardCount: 8,
                    pointerCount: 1,
                    switchCount: 3
                )
            ],
            calendar: calendar
        )

        return summary.estimatedTypedCharacters == 20
            && summary.pointerActionCount == 5
            && summary.contextSwitchCount == 5
            && summary.totalInputActions == 25
            && summary.totalWorkloadEvents == 30
            && summary.activeMinutes == 2
            && FocusPetFormatters.estimatedTypedCharacters(summary.estimatedTypedCharacters) == "键入约 20 字"
            && FocusPetFormatters.contextSwitches(summary.contextSwitchCount) == "上下文切换 5 次"
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
                    petIntent: .focusRestHint,
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

    func dashboardPetDockFrameTracksWindowMovement() -> Bool {
        let window = CGRect(x: 240, y: 120, width: 1_180, height: 820)
        let movedWindow = window.offsetBy(dx: 72, dy: -36)
        let dock = DashboardPetDockingGeometry.sidebarDockFrame(windowFrame: window)
        let movedDock = DashboardPetDockingGeometry.sidebarDockFrame(windowFrame: movedWindow)

        return dock.width == DashboardPetDockingGeometry.defaultSidebarWidth
            && dock.height == DashboardPetDockingGeometry.defaultDockHeight
            && movedDock.size == dock.size
            && movedDock.origin.x - dock.origin.x == 72
            && movedDock.origin.y - dock.origin.y == -36
            && dock.minX == window.minX
            && dock.minY == window.minY + DashboardPetDockingGeometry.defaultBottomInset
    }
}

private let runFocusPetMVPProbe: Void = {
    let probe = FocusPetMVPProbe()
    precondition(probe.cursorWorkForAnHourIsFocus(), "Cursor for 60 minutes should be focus")
    precondition(probe.youtubeForTenMinutesIsDistracted(), "YouTube for 10 minutes should be distracted")
    precondition(probe.manualBreakOutranksEntertainment(), "manual break should outrank entertainment")
    precondition(probe.idleThreeMinutesIsDistracted(), "3 minutes without input should be distracted")
    precondition(probe.idleOneMinuteStaysFocused(), "1 minute without input should stay focused")
    precondition(probe.entertainmentFortyFiveSecondsStaysInGrace(), "45 seconds entertainment should stay in grace")
    precondition(probe.entertainmentOneMinuteIsDistracted(), "1 minute entertainment should be distracted")
    precondition(probe.systemSleepIsAway(), "system sleep should be away")
    precondition(probe.screenLockIsAway(), "screen lock should be away")
    precondition(probe.longInputIdleIsAway(), "long input idle should be away")
    precondition(probe.longIdleBackfillConvertsNoInputWindowToAway(), "long idle backfill should convert the no-input window to away")
    precondition(probe.incrementalAwayRecordingMergesWithoutDuplication(), "incremental away recording should not duplicate screen lock time")
    precondition(probe.frequentSwitchingDoesNotBecomeDistracted(), "app switching alone should not be distracted")
    precondition(probe.focusTwentyFiveMinutesTriggersRestNudge(), "25 minutes focus should trigger rest nudge")
    precondition(probe.legacyReminderSettingsDefaultToCustomizableNudgeParameters(), "legacy reminder settings should decode new nudge defaults")
    precondition(probe.reminderSettingsCustomizeNudgePolicyAndClampValues(), "reminder settings should customize nudge thresholds and clamp values")
    precondition(probe.windowTitlePrivacyDoesNotStoreRawTitleByDefault(), "default privacy should not store raw titles")
    precondition(probe.onlyCategoryPrivacyStoresNoTitleMetadata(), "category-only privacy should remove title metadata")
    precondition(probe.timelineTracksFourStateTotals(), "daily summary should aggregate all four states")
    precondition(probe.ignoredAppsAreExcludedFromAppUsageRanking(), "ignored apps should be excluded from app usage ranking")
    precondition(probe.legacyPetSettingsDefaultToInteractivePlacement(), "legacy pet settings should decode with interaction defaults")
    precondition(probe.legacyAppSettingsDefaultJudgmentParameters(), "legacy app settings should decode judgment defaults")
    precondition(probe.focusSessionReportsCompletionAndDecodesLegacyJSON(), "focus sessions should expose completion and decode legacy JSON")
    precondition(probe.groupedRulesClassifyExpectedCategories(), "grouped rules should classify apps and title keywords")
    precondition(probe.neutralIsLegacyOnlyAndHiddenFromUserChoices(), "neutral should be hidden from user-facing classification choices")
    precondition(probe.catalogIsLoadedAndBroadEnough(), "built-in classification catalog should load and cover mainstream app classes")
    precondition(probe.expandedCatalogClassifiesRepresentativeCoverage(), "expanded classification catalog should cover representative work, entertainment, and utility cases")
    precondition(probe.browserWebsiteRulesOutrankBrowserAppRules(), "website/title rules should outrank browser app defaults")
    precondition(probe.userRuleOverridesCatalog(), "user exceptions should override the built-in catalog")
    precondition(probe.builtInRulesAreFilteredFromStoredUserRules(), "stored built-in defaults should not become user exceptions")
    precondition(probe.redactedExportRemovesTitleMetadata(), "redacted export should remove title metadata")
    precondition(probe.inputActivityRecorderMergesBucketsAndClampsCounts(), "input activity should merge buckets and clamp counts")
    precondition(probe.localStorePersistsInputActivityAndDecodesLegacySnapshots(), "input activity should persist and legacy snapshots should decode")
    precondition(probe.retentionPrunesInputActivityBuckets(), "retention should prune input activity buckets")
    precondition(probe.inputTimelineSnapshotAggregatesInputAndSmoothsApps(), "input timeline snapshot should aggregate input and smooth short app switches")
    precondition(probe.inputTimelineSnapshotSmoothsTinyStateFragments(), "input timeline snapshot should smooth tiny state fragments for display")
    precondition(probe.inputWorkloadSummaryAggregatesReadableMetrics(), "input workload should expose user-readable activity metrics")
    precondition(probe.overnightIdleIsNotHeuristicallyConvertedToAway(), "stored history should not be heuristically rewritten")
    precondition(probe.dashboardPetDockFrameTracksWindowMovement(), "dashboard pet dock frame should move with the dashboard window")
}()

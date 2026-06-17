import FocusPetCore
import Foundation

public struct FocusPetWidgetSnapshot: Codable, Hashable, Sendable {
    public var generatedAt: Date
    public var currentState: FocusState
    public var stableDurationSeconds: Int
    public var currentAppName: String
    public var currentCategory: ActivityCategory
    public var focusSeconds: Int
    public var distractedSeconds: Int
    public var breakSeconds: Int
    public var awaySeconds: Int
    public var keyboardCount: Int
    public var pointerCount: Int
    public var contextSwitchCount: Int
    public var recentRhythms: [FocusPetWidgetRhythmSnapshot]
    public var reminderPauseUntil: Date?
    public var petIntentTitle: String
    public var selectedPetPackID: String

    public init(
        generatedAt: Date,
        currentState: FocusState,
        stableDurationSeconds: Int,
        currentAppName: String,
        currentCategory: ActivityCategory,
        focusSeconds: Int,
        distractedSeconds: Int,
        breakSeconds: Int,
        awaySeconds: Int,
        keyboardCount: Int,
        pointerCount: Int,
        contextSwitchCount: Int,
        recentRhythms: [FocusPetWidgetRhythmSnapshot],
        reminderPauseUntil: Date?,
        petIntentTitle: String,
        selectedPetPackID: String
    ) {
        self.generatedAt = generatedAt
        self.currentState = currentState
        self.stableDurationSeconds = max(0, stableDurationSeconds)
        self.currentAppName = currentAppName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Focus Pet"
        self.currentCategory = currentCategory
        self.focusSeconds = max(0, focusSeconds)
        self.distractedSeconds = max(0, distractedSeconds)
        self.breakSeconds = max(0, breakSeconds)
        self.awaySeconds = max(0, awaySeconds)
        self.keyboardCount = max(0, keyboardCount)
        self.pointerCount = max(0, pointerCount)
        self.contextSwitchCount = max(0, contextSwitchCount)
        self.recentRhythms = recentRhythms.sorted { $0.windowHours < $1.windowHours }
        self.reminderPauseUntil = reminderPauseUntil
        self.petIntentTitle = petIntentTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "安静陪伴"
        self.selectedPetPackID = selectedPetPackID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "default"
    }

    public func rhythm(windowHours: Int) -> FocusPetWidgetRhythmSnapshot? {
        recentRhythms.first { $0.windowHours == windowHours } ?? recentRhythms.first
    }
}

public struct FocusPetWidgetRhythmSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var windowHours: Int
    public var focusSeconds: Int
    public var distractedSeconds: Int
    public var breakSeconds: Int
    public var awaySeconds: Int
    public var keyboardCount: Int
    public var pointerCount: Int
    public var contextSwitchCount: Int
    public var timelineRanges: [FocusPetWidgetRhythmRange]

    public var id: Int { windowHours }

    public var totalSeconds: Int {
        focusSeconds + distractedSeconds + breakSeconds + awaySeconds
    }

    public var focusRatio: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(focusSeconds) / Double(totalSeconds)
    }

    public init(
        windowHours: Int,
        focusSeconds: Int,
        distractedSeconds: Int,
        breakSeconds: Int,
        awaySeconds: Int,
        keyboardCount: Int,
        pointerCount: Int,
        contextSwitchCount: Int,
        timelineRanges: [FocusPetWidgetRhythmRange]
    ) {
        self.windowHours = max(1, windowHours)
        self.focusSeconds = max(0, focusSeconds)
        self.distractedSeconds = max(0, distractedSeconds)
        self.breakSeconds = max(0, breakSeconds)
        self.awaySeconds = max(0, awaySeconds)
        self.keyboardCount = max(0, keyboardCount)
        self.pointerCount = max(0, pointerCount)
        self.contextSwitchCount = max(0, contextSwitchCount)
        self.timelineRanges = timelineRanges
    }
}

public struct FocusPetWidgetRhythmRange: Codable, Hashable, Sendable, Identifiable {
    public var state: FocusState
    public var startProgress: Double
    public var endProgress: Double

    public var id: String {
        "\(state.id)-\(Int((startProgress * 10_000).rounded()))-\(Int((endProgress * 10_000).rounded()))"
    }

    public var width: Double {
        max(0, endProgress - startProgress)
    }

    public init(state: FocusState, startProgress: Double, endProgress: Double) {
        self.state = state
        self.startProgress = max(0, min(1, startProgress))
        self.endProgress = max(self.startProgress, min(1, endProgress))
    }
}

extension FocusPetWidgetSnapshot {
    public static func sample(now: Date = Date()) -> FocusPetWidgetSnapshot {
        let ranges: [FocusPetWidgetRhythmRange] = [
            FocusPetWidgetRhythmRange(state: .focus, startProgress: 0.00, endProgress: 0.18),
            FocusPetWidgetRhythmRange(state: .distracted, startProgress: 0.18, endProgress: 0.25),
            FocusPetWidgetRhythmRange(state: .breakTime, startProgress: 0.25, endProgress: 0.30),
            FocusPetWidgetRhythmRange(state: .focus, startProgress: 0.30, endProgress: 0.58),
            FocusPetWidgetRhythmRange(state: .distracted, startProgress: 0.58, endProgress: 0.66),
            FocusPetWidgetRhythmRange(state: .focus, startProgress: 0.66, endProgress: 0.88),
            FocusPetWidgetRhythmRange(state: .breakTime, startProgress: 0.88, endProgress: 0.93),
            FocusPetWidgetRhythmRange(state: .away, startProgress: 0.93, endProgress: 1.00)
        ]
        let rhythm4h = FocusPetWidgetRhythmSnapshot(
            windowHours: 4,
            focusSeconds: 9_960,
            distractedSeconds: 1_260,
            breakSeconds: 1_440,
            awaySeconds: 1_740,
            keyboardCount: 4_820,
            pointerCount: 1_240,
            contextSwitchCount: 23,
            timelineRanges: ranges
        )
        let rhythm8h = FocusPetWidgetRhythmSnapshot(
            windowHours: 8,
            focusSeconds: 15_900,
            distractedSeconds: 2_700,
            breakSeconds: 2_100,
            awaySeconds: 8_100,
            keyboardCount: 8_400,
            pointerCount: 2_760,
            contextSwitchCount: 48,
            timelineRanges: ranges
        )
        let rhythm12h = FocusPetWidgetRhythmSnapshot(
            windowHours: 12,
            focusSeconds: 20_400,
            distractedSeconds: 4_200,
            breakSeconds: 3_000,
            awaySeconds: 15_600,
            keyboardCount: 12_800,
            pointerCount: 4_120,
            contextSwitchCount: 72,
            timelineRanges: ranges
        )
        return FocusPetWidgetSnapshot(
            generatedAt: now,
            currentState: .focus,
            stableDurationSeconds: 42 * 60,
            currentAppName: "Codex",
            currentCategory: .work,
            focusSeconds: 52 * 60,
            distractedSeconds: 9 * 60,
            breakSeconds: 21 * 60,
            awaySeconds: 0,
            keyboardCount: 4_820,
            pointerCount: 1_240,
            contextSwitchCount: 23,
            recentRhythms: [rhythm4h, rhythm8h, rhythm12h],
            reminderPauseUntil: nil,
            petIntentTitle: "安静陪伴",
            selectedPetPackID: "xiaodai_local"
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

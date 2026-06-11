import Foundation

public enum StateReason: String, Codable, Hashable, Sendable, CaseIterable {
    case systemSleep
    case screenLocked
    case longInputIdleAway
    case inputIdleDistracted
    case activeBreak
    case activeFocusSession
    case workCategory
    case entertainmentStable
    case entertainmentGrace
    case frequentSwitching
    case ignoredActivity
    case previousStateHeld
    case neutralDefault
}

public struct StateEngineThresholds: Codable, Hashable, Sendable {
    public var uiStabilitySeconds: TimeInterval
    public var idleDistractedSeconds: TimeInterval
    public var idleAwaySeconds: TimeInterval
    public var distractedSeconds: TimeInterval
    public var frequentSwitchesLast5Min: Int

    public init(
        uiStabilitySeconds: TimeInterval = 10,
        idleDistractedSeconds: TimeInterval = 60,
        idleAwaySeconds: TimeInterval = 10 * 60,
        distractedSeconds: TimeInterval = 60,
        frequentSwitchesLast5Min: Int = 8
    ) {
        self.uiStabilitySeconds = uiStabilitySeconds
        self.idleDistractedSeconds = idleDistractedSeconds
        self.idleAwaySeconds = max(idleDistractedSeconds, idleAwaySeconds)
        self.distractedSeconds = distractedSeconds
        self.frequentSwitchesLast5Min = frequentSwitchesLast5Min
    }
}

public struct StateDecision: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var state: FocusState
    public var category: ActivityCategory
    public var confidence: Double
    public var reason: [StateReason]
    public var stableDuration: TimeInterval

    public init(
        timestamp: Date,
        state: FocusState,
        category: ActivityCategory,
        confidence: Double,
        reason: [StateReason],
        stableDuration: TimeInterval
    ) {
        self.timestamp = timestamp
        self.state = state
        self.category = category
        self.confidence = confidence
        self.reason = reason
        self.stableDuration = max(0, stableDuration)
    }

    public var snapshot: FocusStateSnapshot {
        FocusStateSnapshot(
            timestamp: timestamp,
            state: state,
            category: category,
            stableDuration: stableDuration,
            appName: "",
            bundleID: nil,
            reason: reason
        )
    }
}

public struct StateEngine: Sendable {
    public var thresholds: StateEngineThresholds

    public init(thresholds: StateEngineThresholds = StateEngineThresholds()) {
        self.thresholds = thresholds
    }

    public func evaluate(_ snapshot: ActivitySnapshot, previousStableState: FocusState?) -> StateDecision {
        let activeCarryState: FocusState = previousStableState == .distracted ? .distracted : .focus

        if snapshot.isSystemSleeping {
            return decision(
                snapshot,
                state: .away,
                confidence: 0.98,
                reason: [.systemSleep],
                stableDuration: max(snapshot.idleSeconds, snapshot.activeCategoryDuration)
            )
        }

        if snapshot.isScreenLocked {
            return decision(
                snapshot,
                state: .away,
                confidence: 0.96,
                reason: [.screenLocked],
                stableDuration: max(snapshot.idleSeconds, snapshot.activeCategoryDuration)
            )
        }

        if snapshot.isBreakActive {
            return decision(
                snapshot,
                state: .breakTime,
                confidence: 0.96,
                reason: [.activeBreak],
                stableDuration: snapshot.activeCategoryDuration
            )
        }

        if snapshot.idleSeconds >= thresholds.idleAwaySeconds {
            return decision(
                snapshot,
                state: .away,
                confidence: 0.88,
                reason: [.longInputIdleAway],
                stableDuration: snapshot.idleSeconds
            )
        }

        if snapshot.idleSeconds >= thresholds.idleDistractedSeconds {
            return decision(
                snapshot,
                state: .distracted,
                confidence: 0.82,
                reason: [.inputIdleDistracted],
                stableDuration: snapshot.idleSeconds
            )
        }

        switch snapshot.category {
        case .work:
            return decision(
                snapshot,
                state: .focus,
                confidence: 0.84,
                reason: [.workCategory],
                stableDuration: snapshot.activeCategoryDuration
            )
        case .entertainment:
            if snapshot.activeCategoryDuration >= thresholds.distractedSeconds {
                return decision(
                    snapshot,
                    state: .distracted,
                    confidence: 0.84,
                    reason: [.entertainmentStable],
                    stableDuration: snapshot.activeCategoryDuration
                )
            }

            return decision(
                snapshot,
                state: activeCarryState,
                confidence: 0.58,
                reason: [.entertainmentGrace, .previousStateHeld],
                stableDuration: snapshot.activeCategoryDuration
            )
        case .ignore:
            return decision(
                snapshot,
                state: activeCarryState,
                confidence: 0.45,
                reason: [.ignoredActivity, .previousStateHeld],
                stableDuration: snapshot.activeCategoryDuration
            )
        case .neutral:
            if snapshot.switchCountLast5Min > thresholds.frequentSwitchesLast5Min {
                return decision(
                    snapshot,
                    state: .distracted,
                    confidence: 0.76,
                    reason: [.frequentSwitching],
                    stableDuration: snapshot.activeCategoryDuration
                )
            }

            return decision(
                snapshot,
                state: activeCarryState,
                confidence: 0.55,
                reason: previousStableState == nil ? [.neutralDefault] : [.previousStateHeld],
                stableDuration: snapshot.activeCategoryDuration
            )
        }
    }

    private func decision(
        _ snapshot: ActivitySnapshot,
        state: FocusState,
        confidence: Double,
        reason: [StateReason],
        stableDuration: TimeInterval
    ) -> StateDecision {
        StateDecision(
            timestamp: snapshot.timestamp,
            state: state,
            category: snapshot.category,
            confidence: confidence,
            reason: reason,
            stableDuration: stableDuration
        )
    }
}

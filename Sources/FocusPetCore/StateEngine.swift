import Foundation

public enum StateReason: String, Codable, Hashable, Sendable, CaseIterable {
    case idleAway
    case longAway
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
    public var distractedSeconds: TimeInterval
    public var awaySeconds: TimeInterval
    public var longAwaySeconds: TimeInterval
    public var frequentSwitchesLast5Min: Int

    public init(
        uiStabilitySeconds: TimeInterval = 10,
        distractedSeconds: TimeInterval = 5 * 60,
        awaySeconds: TimeInterval = 10 * 60,
        longAwaySeconds: TimeInterval = 30 * 60,
        frequentSwitchesLast5Min: Int = 12
    ) {
        self.uiStabilitySeconds = uiStabilitySeconds
        self.distractedSeconds = distractedSeconds
        self.awaySeconds = awaySeconds
        self.longAwaySeconds = longAwaySeconds
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
        if snapshot.idleSeconds >= thresholds.awaySeconds {
            return decision(
                snapshot,
                state: .away,
                confidence: snapshot.idleSeconds >= thresholds.longAwaySeconds ? 0.98 : 0.92,
                reason: snapshot.idleSeconds >= thresholds.longAwaySeconds ? [.idleAway, .longAway] : [.idleAway],
                stableDuration: snapshot.idleSeconds
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

        if snapshot.isFocusSessionActive {
            if snapshot.category == .entertainment && snapshot.activeCategoryDuration >= thresholds.distractedSeconds {
                return decision(
                    snapshot,
                    state: .distracted,
                    confidence: 0.78,
                    reason: [.entertainmentStable],
                    stableDuration: snapshot.activeCategoryDuration
                )
            }

            return decision(
                snapshot,
                state: .focus,
                confidence: 0.9,
                reason: [.activeFocusSession],
                stableDuration: snapshot.activeCategoryDuration
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
                state: previousStableState ?? .focus,
                confidence: 0.58,
                reason: [.entertainmentGrace, .previousStateHeld],
                stableDuration: snapshot.activeCategoryDuration
            )
        case .ignore:
            return decision(
                snapshot,
                state: previousStableState ?? .focus,
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
                state: previousStableState ?? .focus,
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

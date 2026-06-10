import Foundation

public struct RuleEngine: Sendable {
    public init() {}

    public func evaluate(
        rules: [FocusRule],
        state: FusedUserState,
        sourceKind: ObservationSourceKind = .live,
        now: Date,
        lastTriggeredAtByRuleID: [String: Date],
        isPaused: Bool
    ) -> [ReminderDecision] {
        guard !isPaused else { return [] }
        guard sourceKind == .live else { return [] }
        guard state.confidence >= 0.65 else { return [] }

        return rules.compactMap { rule in
            guard rule.isEnabled else { return nil }
            guard rule.contexts.contains(state.context) else { return nil }
            guard rule.states.contains(state.userState) else { return nil }
            guard state.stableDurationSeconds >= rule.durationSeconds else { return nil }

            if let lastTriggeredAt = lastTriggeredAtByRuleID[rule.id],
               now.timeIntervalSince(lastTriggeredAt) < rule.cooldownSeconds {
                return nil
            }

            return ReminderDecision(
                id: "\(rule.id).\(Int(now.timeIntervalSince1970))",
                ruleID: rule.id,
                sourceKind: sourceKind,
                triggeredAt: now,
                userState: state.userState,
                action: rule.action
            )
        }
    }
}

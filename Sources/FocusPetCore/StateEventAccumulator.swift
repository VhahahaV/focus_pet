import Foundation

public struct StateEventAccumulator: Sendable {
    public var maxEvents: Int
    public var defaultTickSeconds: TimeInterval
    public var mergeGapSeconds: TimeInterval

    public init(maxEvents: Int = 720, defaultTickSeconds: TimeInterval = 10, mergeGapSeconds: TimeInterval = 15) {
        self.maxEvents = maxEvents
        self.defaultTickSeconds = defaultTickSeconds
        self.mergeGapSeconds = mergeGapSeconds
    }

    public func recording(
        state: FusedUserState,
        sourceKind: ObservationSourceKind,
        in events: [StateEvent]
    ) -> [StateEvent] {
        guard state.confidence > 0 else {
            return pruned(events)
        }

        let endTime = state.timestamp
        guard let startTime = startTime(for: endTime, after: events.last?.endTime) else {
            return pruned(events)
        }

        var updated = events
        if let lastIndex = updated.indices.last,
           canMerge(updated[lastIndex], with: state, sourceKind: sourceKind, endTime: endTime) {
            var last = updated[lastIndex]
            last.endTime = max(last.endTime, endTime)
            last.confidence = max(last.confidence, state.confidence)
            last.reason = state.reason
            updated[lastIndex] = last
        } else {
            updated.append(StateEvent(
                id: UUID().uuidString,
                sourceKind: sourceKind,
                startTime: startTime,
                endTime: endTime,
                userState: state.userState,
                context: state.context,
                confidence: state.confidence,
                reason: state.reason
            ))
        }

        return pruned(updated)
    }

    private func startTime(for endTime: Date, after latestEndTime: Date?) -> Date? {
        guard let latestEndTime else {
            return endTime.addingTimeInterval(-defaultTickSeconds)
        }

        let gap = endTime.timeIntervalSince(latestEndTime)
        guard gap > 0 else { return nil }

        if gap <= mergeGapSeconds {
            return latestEndTime
        }

        return endTime.addingTimeInterval(-min(defaultTickSeconds, gap))
    }

    private func canMerge(
        _ event: StateEvent,
        with state: FusedUserState,
        sourceKind: ObservationSourceKind,
        endTime: Date
    ) -> Bool {
        event.sourceKind == sourceKind
            && event.userState == state.userState
            && event.context == state.context
            && endTime.timeIntervalSince(event.endTime) <= mergeGapSeconds
    }

    private func pruned(_ events: [StateEvent]) -> [StateEvent] {
        guard events.count > maxEvents else { return events }
        return Array(events.suffix(maxEvents))
    }
}

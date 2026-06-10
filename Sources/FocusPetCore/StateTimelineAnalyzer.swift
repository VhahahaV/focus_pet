import Foundation

public struct StateTimelineSegment: Codable, Hashable, Sendable {
    public var startTime: Date
    public var endTime: Date
    public var userState: UserState
    public var context: ContextType

    public var durationSeconds: Int {
        max(0, Int(endTime.timeIntervalSince(startTime)))
    }
}

public struct StateTimelineSummary: Sendable {
    public var segments: [StateTimelineSegment]
    public var durations: [UserState: Int]

    public var totalSeconds: Int {
        segments.reduce(0) { $0 + $1.durationSeconds }
    }

    public var awayCount: Int {
        segments.filter { $0.userState == .away }.count
    }

    public var longestFocusSeconds: Int {
        segments
            .filter { $0.userState == .focused }
            .map(\.durationSeconds)
            .max() ?? 0
    }

    public func seconds(for state: UserState) -> Int {
        durations[state, default: 0]
    }
}

public struct StateTimelineAnalyzer: Sendable {
    public var mergeGapSeconds: TimeInterval

    public init(mergeGapSeconds: TimeInterval = 12) {
        self.mergeGapSeconds = mergeGapSeconds
    }

    public func summarize(
        events: [StateEvent],
        from start: Date,
        to end: Date,
        sourceKind: ObservationSourceKind? = .live
    ) -> StateTimelineSummary {
        let rawSegments = events.compactMap { event -> StateTimelineSegment? in
            if let sourceKind, event.sourceKind != sourceKind {
                return nil
            }

            let clampedStart = max(event.startTime, start)
            let clampedEnd = min(event.endTime, end)
            guard clampedEnd > clampedStart else { return nil }

            return StateTimelineSegment(
                startTime: clampedStart,
                endTime: clampedEnd,
                userState: event.userState,
                context: event.context
            )
        }

        let segments = mergedSegments(rawSegments)
        let durations = segments.reduce(into: Dictionary(uniqueKeysWithValues: UserState.allCases.map { ($0, 0) })) {
            result, segment in
            result[segment.userState, default: 0] += segment.durationSeconds
        }

        return StateTimelineSummary(segments: segments, durations: durations)
    }

    private func mergedSegments(_ segments: [StateTimelineSegment]) -> [StateTimelineSegment] {
        let sorted = segments.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.startTime < rhs.startTime
        }

        return sorted.reduce(into: []) { merged, rawSegment in
            var segment = rawSegment
            guard let last = merged.last else {
                merged.append(segment)
                return
            }

            if segment.userState == last.userState,
               segment.startTime.timeIntervalSince(last.endTime) <= mergeGapSeconds {
                merged[merged.count - 1].endTime = max(last.endTime, segment.endTime)
                return
            }

            if segment.startTime < last.endTime {
                segment.startTime = last.endTime
            }

            guard segment.endTime > segment.startTime else { return }
            merged.append(segment)
        }
    }
}

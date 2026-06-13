import Foundation

public struct StateSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var state: FocusState
    public var appName: String
    public var bundleID: String?
    public var category: ActivityCategory
    public var titleStored: Bool
    public var titleDisplay: String?
    public var source: Set<ActivitySignalSource>

    public init(
        id: String = UUID().uuidString,
        start: Date,
        end: Date,
        state: FocusState,
        appName: String,
        bundleID: String?,
        category: ActivityCategory,
        titleStored: Bool,
        titleDisplay: String?,
        source: Set<ActivitySignalSource>
    ) {
        self.id = id
        self.start = start
        self.end = max(end, start)
        self.state = state
        self.appName = appName
        self.bundleID = bundleID
        self.category = category
        self.titleStored = titleStored
        self.titleDisplay = titleDisplay
        self.source = source
    }

    public var durationSeconds: Int {
        max(0, Int(end.timeIntervalSince(start)))
    }
}

public struct AppUsageSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var appName: String
    public var bundleID: String?
    public var category: ActivityCategory

    public init(
        id: String = UUID().uuidString,
        start: Date,
        end: Date,
        appName: String,
        bundleID: String?,
        category: ActivityCategory
    ) {
        self.id = id
        self.start = start
        self.end = max(end, start)
        self.appName = appName
        self.bundleID = bundleID
        self.category = category
    }

    public var durationSeconds: Int {
        max(0, Int(end.timeIntervalSince(start)))
    }
}

public struct StateReclassificationResult: Hashable, Sendable {
    public var segments: [StateSegment]
    public var reclassifiedSeconds: [FocusState: Int]

    public init(segments: [StateSegment], reclassifiedSeconds: [FocusState: Int]) {
        self.segments = segments
        self.reclassifiedSeconds = reclassifiedSeconds
    }
}

public struct TimeTracker: Sendable {
    public var tickSeconds: TimeInterval
    public var mergeGapSeconds: TimeInterval

    public init(tickSeconds: TimeInterval = 10, mergeGapSeconds: TimeInterval = 15) {
        self.tickSeconds = tickSeconds
        self.mergeGapSeconds = mergeGapSeconds
    }

    public func record(
        decision: StateDecision,
        snapshot: ActivitySnapshot,
        segments: [StateSegment]
    ) -> [StateSegment] {
        let start = snapshot.timestamp.addingTimeInterval(-tickSeconds)
        var updated = segments

        if let lastIndex = updated.indices.last,
           canMerge(updated[lastIndex], decision: decision, snapshot: snapshot) {
            updated[lastIndex].end = max(updated[lastIndex].end, snapshot.timestamp)
            return updated
        }

        updated.append(StateSegment(
            start: start,
            end: snapshot.timestamp,
            state: decision.state,
            appName: snapshot.appName,
            bundleID: snapshot.bundleID,
            category: snapshot.category,
            titleStored: snapshot.titleStored,
            titleDisplay: snapshot.titleDisplay,
            source: snapshot.source
        ))
        return updated
    }

    public func recordAppUsage(snapshot: ActivitySnapshot, appUsage: [AppUsageSegment]) -> [AppUsageSegment] {
        let start = snapshot.timestamp.addingTimeInterval(-tickSeconds)
        var updated = appUsage

        if let lastIndex = updated.indices.last,
           updated[lastIndex].appName == snapshot.appName,
           updated[lastIndex].bundleID == snapshot.bundleID,
           updated[lastIndex].category == snapshot.category,
           snapshot.timestamp.timeIntervalSince(updated[lastIndex].end) <= mergeGapSeconds {
            updated[lastIndex].end = max(updated[lastIndex].end, snapshot.timestamp)
            return updated
        }

        updated.append(AppUsageSegment(
            start: start,
            end: snapshot.timestamp,
            appName: snapshot.appName,
            bundleID: snapshot.bundleID,
            category: snapshot.category
        ))
        return updated
    }

    public func reclassify(
        segments: [StateSegment],
        from intervalStart: Date,
        to intervalEnd: Date,
        matching states: Set<FocusState>,
        as targetState: FocusState,
        addingSource source: ActivitySignalSource
    ) -> StateReclassificationResult {
        guard intervalEnd > intervalStart, !states.isEmpty else {
            return StateReclassificationResult(segments: segments, reclassifiedSeconds: [:])
        }

        var rewritten: [StateSegment] = []
        var reclassifiedSeconds: [FocusState: Int] = [:]

        for segment in segments {
            guard segment.end > intervalStart,
                  segment.start < intervalEnd,
                  states.contains(segment.state),
                  segment.state != targetState else {
                rewritten.append(segment)
                continue
            }

            let overlapStart = max(segment.start, intervalStart)
            let overlapEnd = min(segment.end, intervalEnd)
            guard overlapEnd > overlapStart else {
                rewritten.append(segment)
                continue
            }

            if segment.start < overlapStart {
                rewritten.append(segmentCopy(segment, start: segment.start, end: overlapStart))
            }

            var reclassified = segmentCopy(segment, start: overlapStart, end: overlapEnd)
            reclassified.state = targetState
            reclassified.source.insert(source)
            rewritten.append(reclassified)
            reclassifiedSeconds[segment.state, default: 0] += max(0, Int(overlapEnd.timeIntervalSince(overlapStart).rounded()))

            if overlapEnd < segment.end {
                rewritten.append(segmentCopy(segment, start: overlapEnd, end: segment.end))
            }
        }

        return StateReclassificationResult(
            segments: mergeAdjacentStateSegments(rewritten),
            reclassifiedSeconds: reclassifiedSeconds
        )
    }

    private func canMerge(_ segment: StateSegment, decision: StateDecision, snapshot: ActivitySnapshot) -> Bool {
        segment.state == decision.state
            && segment.category == decision.category
            && segment.appName == snapshot.appName
            && segment.bundleID == snapshot.bundleID
            && snapshot.timestamp.timeIntervalSince(segment.end) <= mergeGapSeconds
    }

    private func segmentCopy(_ segment: StateSegment, start: Date, end: Date) -> StateSegment {
        var copy = segment
        copy.id = UUID().uuidString
        copy.start = start
        copy.end = max(end, start)
        return copy
    }

    private func mergeAdjacentStateSegments(_ segments: [StateSegment]) -> [StateSegment] {
        var merged: [StateSegment] = []
        for segment in segments where segment.end > segment.start {
            guard let lastIndex = merged.indices.last,
                  canMerge(merged[lastIndex], segment) else {
                merged.append(segment)
                continue
            }

            merged[lastIndex].end = max(merged[lastIndex].end, segment.end)
            merged[lastIndex].source.formUnion(segment.source)
        }
        return merged
    }

    private func canMerge(_ lhs: StateSegment, _ rhs: StateSegment) -> Bool {
        lhs.state == rhs.state
            && lhs.category == rhs.category
            && lhs.appName == rhs.appName
            && lhs.bundleID == rhs.bundleID
            && lhs.titleStored == rhs.titleStored
            && lhs.titleDisplay == rhs.titleDisplay
            && rhs.start.timeIntervalSince(lhs.end) <= mergeGapSeconds
    }
}

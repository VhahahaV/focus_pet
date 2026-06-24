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

public struct InputActivityBucket: Identifiable, Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var keyboardCount: Int
    public var pointerCount: Int
    public var switchCount: Int

    public var id: String {
        "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
    }

    public init(
        start: Date,
        end: Date,
        keyboardCount: Int = 0,
        pointerCount: Int = 0,
        switchCount: Int = 0
    ) {
        self.start = start
        self.end = max(end, start)
        self.keyboardCount = max(0, keyboardCount)
        self.pointerCount = max(0, pointerCount)
        self.switchCount = max(0, switchCount)
    }

    public var totalInputCount: Int {
        keyboardCount + pointerCount
    }

    public var estimatedTypedCharacters: Int {
        keyboardCount
    }

    public var pointerActionCount: Int {
        pointerCount
    }

    public var contextSwitchCount: Int {
        switchCount
    }

    public var hasActivity: Bool {
        totalInputCount > 0 || switchCount > 0
    }

    public mutating func add(keyboardCount: Int, pointerCount: Int, switchCount: Int) {
        self.keyboardCount += max(0, keyboardCount)
        self.pointerCount += max(0, pointerCount)
        self.switchCount += max(0, switchCount)
    }
}

public struct InputWorkloadSummary: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var estimatedTypedCharacters: Int
    public var pointerActionCount: Int
    public var contextSwitchCount: Int
    public var activeSeconds: Int

    public var totalInputActions: Int {
        estimatedTypedCharacters + pointerActionCount
    }

    public var totalWorkloadEvents: Int {
        totalInputActions + contextSwitchCount
    }

    public var activeMinutes: Int {
        guard activeSeconds > 0 else { return 0 }
        return max(1, Int((Double(activeSeconds) / 60).rounded(.up)))
    }

    public var hasWorkload: Bool {
        totalWorkloadEvents > 0
    }

    public init(
        start: Date,
        end: Date,
        estimatedTypedCharacters: Int = 0,
        pointerActionCount: Int = 0,
        contextSwitchCount: Int = 0,
        activeSeconds: Int = 0
    ) {
        self.start = start
        self.end = max(end, start)
        self.estimatedTypedCharacters = max(0, estimatedTypedCharacters)
        self.pointerActionCount = max(0, pointerActionCount)
        self.contextSwitchCount = max(0, contextSwitchCount)
        self.activeSeconds = max(0, activeSeconds)
    }

    public init(inputActivity: [InputActivityBucket], start: Date, end: Date) {
        let boundedEnd = max(end, start)
        var typed = 0
        var pointer = 0
        var switches = 0
        var activeSeconds = 0

        for bucket in inputActivity where bucket.end > start && bucket.start < boundedEnd {
            typed += bucket.estimatedTypedCharacters
            pointer += bucket.pointerActionCount
            switches += bucket.contextSwitchCount
            if bucket.hasActivity {
                let clippedStart = max(bucket.start, start)
                let clippedEnd = min(bucket.end, boundedEnd)
                activeSeconds += max(0, Int(clippedEnd.timeIntervalSince(clippedStart).rounded()))
            }
        }

        self.init(
            start: start,
            end: boundedEnd,
            estimatedTypedCharacters: typed,
            pointerActionCount: pointer,
            contextSwitchCount: switches,
            activeSeconds: activeSeconds
        )
    }

    public init(
        dayContaining date: Date,
        inputActivity: [InputActivityBucket],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        self.init(inputActivity: inputActivity, start: start, end: end)
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

public struct WorkTimelineBreakdown: Hashable, Sendable {
    public var focusSeconds: Int
    public var distractedSeconds: Int
    public var breakSeconds: Int
    public var awaySeconds: Int

    public var attentionSeconds: Int {
        focusSeconds + distractedSeconds
    }

    public var trackedSeconds: Int {
        focusSeconds + distractedSeconds + breakSeconds + awaySeconds
    }

    public var workSeconds: Int {
        focusSeconds + distractedSeconds + breakSeconds
    }

    public var focusRatio: Double {
        guard attentionSeconds > 0 else { return 0 }
        return Double(focusSeconds) / Double(attentionSeconds)
    }

    public var distractedRatio: Double {
        guard attentionSeconds > 0 else { return 0 }
        return Double(distractedSeconds) / Double(attentionSeconds)
    }

    public init(
        focusSeconds: Int = 0,
        distractedSeconds: Int = 0,
        breakSeconds: Int = 0,
        awaySeconds: Int = 0
    ) {
        self.focusSeconds = max(0, focusSeconds)
        self.distractedSeconds = max(0, distractedSeconds)
        self.breakSeconds = max(0, breakSeconds)
        self.awaySeconds = max(0, awaySeconds)
    }

    public mutating func add(state: FocusState, seconds: Int) {
        let safeSeconds = max(0, seconds)
        switch state {
        case .focus:
            focusSeconds += safeSeconds
        case .distracted:
            distractedSeconds += safeSeconds
        case .breakTime:
            breakSeconds += safeSeconds
        case .away:
            awaySeconds += safeSeconds
        }
    }

    public mutating func merge(_ other: WorkTimelineBreakdown) {
        focusSeconds += other.focusSeconds
        distractedSeconds += other.distractedSeconds
        breakSeconds += other.breakSeconds
        awaySeconds += other.awaySeconds
    }
}

public struct WorkTimelineRange: Identifiable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var state: FocusState

    public var id: String {
        "\(state.id)-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
    }

    public init(start: Date, end: Date, state: FocusState) {
        self.start = start
        self.end = max(end, start)
        self.state = state
    }
}

public struct WorkTimelineInterval: Identifiable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var ranges: [WorkTimelineRange]
    public var breakdown: WorkTimelineBreakdown

    public var id: String {
        "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))-\(ranges.count)"
    }

    public var totalSeconds: Int {
        max(0, Int(end.timeIntervalSince(start).rounded()))
    }

    public var activeSeconds: Int {
        breakdown.workSeconds
    }

    public var focusRatio: Double {
        breakdown.focusRatio
    }

    public init(
        start: Date,
        end: Date,
        ranges: [WorkTimelineRange],
        breakdown: WorkTimelineBreakdown
    ) {
        self.start = start
        self.end = max(end, start)
        self.ranges = ranges
        self.breakdown = breakdown
    }
}

public struct RecentWorkTimelineSnapshot: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var intervals: [WorkTimelineInterval]
    public var summary: WorkTimelineBreakdown
    public var discardedShortIntervalCount: Int
    public var discardedShortWorkSeconds: Int

    public var hasData: Bool {
        !intervals.isEmpty
    }

    public var longestInterval: WorkTimelineInterval? {
        intervals.max { $0.totalSeconds < $1.totalSeconds }
    }

    public init(
        orderedSegments: [StateSegment],
        now: Date = Date(),
        windowSeconds: TimeInterval = 86_400,
        maxSessionBridgeGap: TimeInterval = 20 * 60,
        minimumStandaloneWorkSeconds: Int = 120
    ) {
        let windowEnd = now
        let windowStart = now.addingTimeInterval(-max(60, windowSeconds))
        let bridgeGap = max(0, maxSessionBridgeGap)
        let minimumWorkSeconds = max(0, minimumStandaloneWorkSeconds)
        var result: [WorkTimelineInterval] = []
        var currentStart: Date?
        var currentEnd: Date?
        var currentRanges: [WorkTimelineRange] = []
        var currentBreakdown = WorkTimelineBreakdown()
        var totalBreakdown = WorkTimelineBreakdown()
        var discardedCount = 0
        var discardedWorkSeconds = 0
        var consumedUntil = windowStart

        func resetCurrent() {
            currentStart = nil
            currentEnd = nil
            currentRanges = []
            currentBreakdown = WorkTimelineBreakdown()
        }

        func appendRange(_ range: WorkTimelineRange) {
            guard range.end > range.start else { return }
            if let lastIndex = currentRanges.indices.last {
                let last = currentRanges[lastIndex]
                if last.state == range.state,
                   range.start.timeIntervalSince(last.end) <= 1.5 {
                    currentRanges[lastIndex] = WorkTimelineRange(
                        start: last.start,
                        end: max(last.end, range.end),
                        state: last.state
                    )
                    return
                }
            }
            currentRanges.append(range)
        }

        func flushCurrent() {
            guard let start = currentStart,
                  let end = currentEnd,
                  end > start,
                  !currentRanges.isEmpty else {
                resetCurrent()
                return
            }

            let interval = WorkTimelineInterval(
                start: start,
                end: end,
                ranges: currentRanges,
                breakdown: currentBreakdown
            )
            if interval.activeSeconds >= minimumWorkSeconds {
                result.append(interval)
                totalBreakdown.merge(currentBreakdown)
            } else {
                discardedCount += 1
                discardedWorkSeconds += interval.activeSeconds
            }
            resetCurrent()
        }

        func addBridgeGapIfNeeded(until nextStart: Date) -> Bool {
            guard let previousEnd = currentEnd,
                  nextStart > previousEnd else { return true }

            let gap = nextStart.timeIntervalSince(previousEnd)
            guard gap <= bridgeGap else {
                flushCurrent()
                return false
            }

            let seconds = max(0, Int(gap.rounded()))
            if seconds > 0 {
                currentBreakdown.add(state: .away, seconds: seconds)
                appendRange(WorkTimelineRange(start: previousEnd, end: nextStart, state: .away))
                currentEnd = nextStart
            }
            return true
        }

        func addWorkRange(_ range: WorkTimelineRange) {
            if currentStart == nil {
                currentStart = range.start
            } else if !addBridgeGapIfNeeded(until: range.start) {
                currentStart = range.start
            }

            currentEnd = max(currentEnd ?? range.end, range.end)
            let seconds = max(0, Int(range.end.timeIntervalSince(range.start).rounded()))
            currentBreakdown.add(state: range.state, seconds: seconds)
            appendRange(range)
        }

        func addAwayRangeIfBridged(_ range: WorkTimelineRange) {
            guard currentStart != nil, let previousEnd = currentEnd else { return }
            let separation = range.end.timeIntervalSince(previousEnd)
            guard separation <= bridgeGap else {
                flushCurrent()
                return
            }

            guard addBridgeGapIfNeeded(until: range.start) else { return }
            currentEnd = max(currentEnd ?? range.end, range.end)
            let seconds = max(0, Int(range.end.timeIntervalSince(range.start).rounded()))
            currentBreakdown.add(state: .away, seconds: seconds)
            appendRange(range)
        }

        for segment in orderedSegments {
            if segment.end <= windowStart { continue }
            if segment.start >= windowEnd { break }

            let clippedEnd = min(segment.end, windowEnd)
            let clippedStart = max(max(segment.start, windowStart), consumedUntil)
            guard clippedEnd > clippedStart else {
                consumedUntil = max(consumedUntil, clippedEnd)
                continue
            }

            let range = WorkTimelineRange(start: clippedStart, end: clippedEnd, state: segment.state)
            consumedUntil = max(consumedUntil, clippedEnd)

            if Self.isWorkState(segment.state) {
                addWorkRange(range)
            } else {
                addAwayRangeIfBridged(range)
            }
        }
        flushCurrent()

        start = windowStart
        end = windowEnd
        intervals = result
        summary = totalBreakdown
        discardedShortIntervalCount = discardedCount
        discardedShortWorkSeconds = discardedWorkSeconds
    }

    private static func isWorkState(_ state: FocusState) -> Bool {
        switch state {
        case .focus, .distracted, .breakTime:
            return true
        case .away:
            return false
        }
    }
}

public struct InputActivityRecorder: Sendable {
    public var bucketSeconds: TimeInterval

    public init(bucketSeconds: TimeInterval = 60) {
        self.bucketSeconds = max(5, bucketSeconds)
    }

    public func record(
        now: Date,
        keyboardCount: Int,
        pointerCount: Int,
        switchCount: Int,
        buckets: [InputActivityBucket]
    ) -> [InputActivityBucket] {
        let keyboardCount = max(0, keyboardCount)
        let pointerCount = max(0, pointerCount)
        let switchCount = max(0, switchCount)
        guard keyboardCount > 0 || pointerCount > 0 || switchCount > 0 else {
            return buckets
        }

        let bucketStart = Self.bucketStart(for: now, bucketSeconds: bucketSeconds)
        let bucketEnd = bucketStart.addingTimeInterval(bucketSeconds)
        var updated = buckets

        if let index = updated.firstIndex(where: { $0.start == bucketStart && $0.end == bucketEnd }) {
            updated[index].add(
                keyboardCount: keyboardCount,
                pointerCount: pointerCount,
                switchCount: switchCount
            )
            return updated
        }

        updated.append(InputActivityBucket(
            start: bucketStart,
            end: bucketEnd,
            keyboardCount: keyboardCount,
            pointerCount: pointerCount,
            switchCount: switchCount
        ))

        if let last = updated.dropLast().last, last.start <= bucketStart {
            return updated
        }
        return updated.sorted { $0.start < $1.start }
    }

    public static func bucketStart(for date: Date, bucketSeconds: TimeInterval = 60) -> Date {
        let interval = max(5, bucketSeconds)
        return Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / interval) * interval)
    }
}

public struct InputTimelineSnapshot: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var stateRanges: [InputTimelineStateRange]
    public var inputBars: [InputTimelineInputBar]
    public var appSegments: [InputTimelineAppSegment]
    public var switchMarkers: [InputTimelineSwitchMarker]
    public var stateDurations: [FocusState: Int]
    public var keyboardCount: Int
    public var pointerCount: Int
    public var switchCount: Int
    public var maxInputCount: Int

    public var totalInputCount: Int {
        keyboardCount + pointerCount
    }

    public var estimatedTypedCharacters: Int {
        keyboardCount
    }

    public var pointerActionCount: Int {
        pointerCount
    }

    public var contextSwitchCount: Int {
        switchCount
    }

    public init(
        windowSeconds: TimeInterval,
        stateSegments: [StateSegment],
        appUsage: [AppUsageSegment],
        inputActivity: [InputActivityBucket],
        now: Date = Date(),
        includeAwayState: Bool = true,
        includeAppSegments: Bool = true
    ) {
        let windowSeconds = max(60, windowSeconds)
        let windowEnd = now
        let windowStart = now.addingTimeInterval(-windowSeconds)
        self.start = windowStart
        self.end = windowEnd

        let span = max(1, windowEnd.timeIntervalSince(windowStart))
        var durations: [FocusState: Int] = [:]
        let rawStateRanges: [InputTimelineStateRange] = Self.overlappingStateSegments(stateSegments, start: windowStart, end: windowEnd).compactMap { segment in
            guard includeAwayState || segment.state != .away else { return nil }
            let clippedStart = max(segment.start, windowStart)
            let clippedEnd = min(segment.end, windowEnd)
            guard clippedEnd > clippedStart else { return nil }
            durations[segment.state, default: 0] += max(0, Int(clippedEnd.timeIntervalSince(clippedStart).rounded()))
            return InputTimelineStateRange(
                startProgress: clippedStart.timeIntervalSince(windowStart) / span,
                endProgress: clippedEnd.timeIntervalSince(windowStart) / span,
                state: segment.state
            )
        }
        self.stateRanges = Self.displayStateRanges(
            rawStateRanges,
            windowSeconds: windowSeconds
        )
        self.stateDurations = durations

        let aggregateSeconds = Self.aggregateSeconds(for: windowSeconds)
        let aggregate = Self.aggregateInputBuckets(
            inputActivity,
            start: windowStart,
            end: windowEnd,
            aggregateSeconds: aggregateSeconds
        )
        self.keyboardCount = aggregate.reduce(0) { $0 + $1.keyboardCount }
        self.pointerCount = aggregate.reduce(0) { $0 + $1.pointerCount }
        self.switchCount = aggregate.reduce(0) { $0 + $1.switchCount }
        self.maxInputCount = max(1, aggregate.map { $0.keyboardCount + $0.pointerCount }.max() ?? 1)
        self.inputBars = aggregate.compactMap { bucket in
            guard bucket.keyboardCount > 0 || bucket.pointerCount > 0 else { return nil }
            let clippedStart = max(bucket.start, windowStart)
            let clippedEnd = min(bucket.end, windowEnd)
            guard clippedEnd > clippedStart else { return nil }
            return InputTimelineInputBar(
                startProgress: clippedStart.timeIntervalSince(windowStart) / span,
                endProgress: clippedEnd.timeIntervalSince(windowStart) / span,
                keyboardCount: bucket.keyboardCount,
                pointerCount: bucket.pointerCount,
                switchCount: bucket.switchCount
            )
        }
        self.switchMarkers = aggregate.compactMap { bucket in
            guard bucket.switchCount > 0 else { return nil }
            let clippedStart = max(bucket.start, windowStart)
            let clippedEnd = min(bucket.end, windowEnd)
            let midpoint = clippedStart.addingTimeInterval(clippedEnd.timeIntervalSince(clippedStart) / 2)
            return InputTimelineSwitchMarker(
                progress: max(0, min(1, midpoint.timeIntervalSince(windowStart) / span)),
                count: bucket.switchCount
            )
        }

        if includeAppSegments {
            let rawAppSegments = Self.overlappingAppUsageSegments(appUsage, start: windowStart, end: windowEnd).compactMap { segment -> InputTimelineAppSegment? in
                guard !Self.isHiddenAppSegment(segment) else { return nil }
                let clippedStart = max(segment.start, windowStart)
                let clippedEnd = min(segment.end, windowEnd)
                guard clippedEnd > clippedStart else { return nil }
                return InputTimelineAppSegment(
                    start: clippedStart,
                    end: clippedEnd,
                    appName: segment.appName,
                    bundleID: segment.bundleID,
                    category: segment.category
                )
            }
            self.appSegments = Self.smoothedAppSegments(
                rawAppSegments.sorted { $0.start < $1.start },
                minVisibleSeconds: min(420, max(180, windowSeconds / 48))
            )
        } else {
            self.appSegments = []
        }
    }

    private static func aggregateSeconds(for windowSeconds: TimeInterval) -> TimeInterval {
        let targetBars: TimeInterval = 104
        let raw = max(60, windowSeconds / targetBars)
        return ceil(raw / 60) * 60
    }

    private static func aggregateInputBuckets(
        _ inputActivity: [InputActivityBucket],
        start: Date,
        end: Date,
        aggregateSeconds: TimeInterval
    ) -> [InputActivityBucket] {
        var grouped: [Date: InputActivityBucket] = [:]
        for bucket in orderedInputActivityBuckets(inputActivity).reversed() {
            if bucket.start >= end { continue }
            if bucket.end <= start { break }
            let key = InputActivityRecorder.bucketStart(for: bucket.start, bucketSeconds: aggregateSeconds)
            let bucketEnd = key.addingTimeInterval(aggregateSeconds)
            var aggregate = grouped[key] ?? InputActivityBucket(start: key, end: bucketEnd)
            aggregate.add(
                keyboardCount: bucket.keyboardCount,
                pointerCount: bucket.pointerCount,
                switchCount: bucket.switchCount
            )
            grouped[key] = aggregate
        }
        return grouped.values.sorted { $0.start < $1.start }
    }

    private static func orderedInputActivityBuckets(_ buckets: [InputActivityBucket]) -> [InputActivityBucket] {
        guard !buckets.isEmpty else { return [] }
        for index in buckets.indices.dropFirst() {
            if buckets[index].start < buckets[buckets.index(before: index)].start {
                return buckets.sorted { $0.start < $1.start }
            }
        }
        return buckets
    }

    private static func overlappingStateSegments(_ segments: [StateSegment], start: Date, end: Date) -> [StateSegment] {
        var result: [StateSegment] = []
        for segment in orderedStateSegments(segments).reversed() {
            if segment.start >= end { continue }
            if segment.end <= start { break }
            result.append(segment)
        }
        return Array(result.reversed())
    }

    private static func overlappingAppUsageSegments(_ segments: [AppUsageSegment], start: Date, end: Date) -> [AppUsageSegment] {
        var result: [AppUsageSegment] = []
        for segment in orderedAppUsageSegments(segments).reversed() {
            if segment.start >= end { continue }
            if segment.end <= start { break }
            result.append(segment)
        }
        return Array(result.reversed())
    }

    private static func orderedStateSegments(_ segments: [StateSegment]) -> [StateSegment] {
        guard !segments.isEmpty else { return [] }
        for index in segments.indices.dropFirst() {
            if segments[index].start < segments[segments.index(before: index)].start {
                return segments.sorted { $0.start < $1.start }
            }
        }
        return segments
    }

    private static func orderedAppUsageSegments(_ segments: [AppUsageSegment]) -> [AppUsageSegment] {
        guard !segments.isEmpty else { return [] }
        for index in segments.indices.dropFirst() {
            if segments[index].start < segments[segments.index(before: index)].start {
                return segments.sorted { $0.start < $1.start }
            }
        }
        return segments
    }

    private static func displayStateRanges(
        _ ranges: [InputTimelineStateRange],
        windowSeconds: TimeInterval
    ) -> [InputTimelineStateRange] {
        guard ranges.count > 1 else { return ranges }
        let mergeGap = min(0.001, max(0.00002, 1 / max(1, windowSeconds)))
        return mergeAdjacentStateRanges(ranges, maxGap: mergeGap)
    }

    private static func mergeAdjacentStateRanges(
        _ ranges: [InputTimelineStateRange],
        maxGap: Double
    ) -> [InputTimelineStateRange] {
        var merged: [InputTimelineStateRange] = []
        for range in ranges.sorted(by: { $0.startProgress < $1.startProgress }) where range.endProgress > range.startProgress {
            if let lastIndex = merged.indices.last,
               merged[lastIndex].state == range.state,
               isAdjacent(merged[lastIndex], range, maxGap: maxGap) {
                merged[lastIndex].endProgress = max(merged[lastIndex].endProgress, range.endProgress)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func isAdjacent(
        _ lhs: InputTimelineStateRange,
        _ rhs: InputTimelineStateRange,
        maxGap: Double
    ) -> Bool {
        rhs.startProgress - lhs.endProgress <= maxGap
    }

    private static func isHiddenAppSegment(_ segment: AppUsageSegment) -> Bool {
        let appName = segment.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bundleID = segment.bundleID?.lowercased() ?? ""
        return appName == "sleep"
            || appName == "loginwindow"
            || appName == "locked screen"
            || bundleID.contains("loginwindow")
    }

    private static func smoothedAppSegments(
        _ segments: [InputTimelineAppSegment],
        minVisibleSeconds: TimeInterval
    ) -> [InputTimelineAppSegment] {
        guard segments.count > 1 else { return segments }
        var result = mergeAdjacentAppSegments(segments)
        var changed = true

        while changed {
            changed = false
            guard result.count > 1 else { break }
            var index = result.startIndex
            while index < result.endIndex {
                let segment = result[index]
                guard segment.duration <= minVisibleSeconds else {
                    index = result.index(after: index)
                    continue
                }

                let previousIndex = index > result.startIndex ? result.index(before: index) : nil
                let nextIndex = result.index(after: index) < result.endIndex ? result.index(after: index) : nil

                if let previousIndex,
                   let nextIndex,
                   result[previousIndex].identity == result[nextIndex].identity {
                    result[previousIndex].end = result[nextIndex].end
                    result.remove(at: nextIndex)
                    result.remove(at: index)
                    changed = true
                    break
                }

                if let previousIndex,
                   nextIndex == nil || result[previousIndex].duration >= result[nextIndex!].duration {
                    result[previousIndex].end = segment.end
                    result.remove(at: index)
                    changed = true
                    break
                }

                if let nextIndex {
                    result[nextIndex].start = segment.start
                    result.remove(at: index)
                    changed = true
                    break
                }

                index = result.index(after: index)
            }
            result = mergeAdjacentAppSegments(result)
        }

        return result
    }

    private static func mergeAdjacentAppSegments(_ segments: [InputTimelineAppSegment]) -> [InputTimelineAppSegment] {
        var merged: [InputTimelineAppSegment] = []
        for segment in segments where segment.end > segment.start {
            if let lastIndex = merged.indices.last,
               merged[lastIndex].identity == segment.identity,
               segment.start.timeIntervalSince(merged[lastIndex].end) <= 60 {
                merged[lastIndex].end = max(merged[lastIndex].end, segment.end)
            } else {
                merged.append(segment)
            }
        }
        return merged
    }
}

public struct InputTimelineStateRange: Identifiable, Hashable, Sendable {
    public var startProgress: Double
    public var endProgress: Double
    public var state: FocusState

    public var id: String {
        "\(state.id)-\(Int((startProgress * 10_000).rounded()))-\(Int((endProgress * 10_000).rounded()))"
    }

    public var width: Double {
        max(0, endProgress - startProgress)
    }

    public init(startProgress: Double, endProgress: Double, state: FocusState) {
        self.startProgress = max(0, min(1, startProgress))
        self.endProgress = max(self.startProgress, min(1, endProgress))
        self.state = state
    }
}

public struct InputTimelineInputBar: Identifiable, Hashable, Sendable {
    public var startProgress: Double
    public var endProgress: Double
    public var keyboardCount: Int
    public var pointerCount: Int
    public var switchCount: Int

    public var id: String {
        "\(Int((startProgress * 10_000).rounded()))-\(Int((endProgress * 10_000).rounded()))-\(keyboardCount)-\(pointerCount)-\(switchCount)"
    }

    public var totalCount: Int {
        keyboardCount + pointerCount
    }

    public var estimatedTypedCharacters: Int {
        keyboardCount
    }

    public var pointerActionCount: Int {
        pointerCount
    }

    public var contextSwitchCount: Int {
        switchCount
    }

    public init(startProgress: Double, endProgress: Double, keyboardCount: Int, pointerCount: Int, switchCount: Int = 0) {
        self.startProgress = max(0, min(1, startProgress))
        self.endProgress = max(self.startProgress, min(1, endProgress))
        self.keyboardCount = max(0, keyboardCount)
        self.pointerCount = max(0, pointerCount)
        self.switchCount = max(0, switchCount)
    }
}

public struct InputTimelineAppSegment: Identifiable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var appName: String
    public var bundleID: String?
    public var category: ActivityCategory

    public var id: String {
        "\(identity)-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
    }

    public var identity: String {
        "\(bundleID ?? "")|\(appName)"
    }

    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    public init(start: Date, end: Date, appName: String, bundleID: String?, category: ActivityCategory) {
        self.start = start
        self.end = max(end, start)
        self.appName = appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : appName
        self.bundleID = bundleID
        self.category = category
    }
}

public struct InputTimelineSwitchMarker: Identifiable, Hashable, Sendable {
    public var progress: Double
    public var count: Int

    public var id: String {
        "\(Int((progress * 10_000).rounded()))-\(count)"
    }

    public init(progress: Double, count: Int) {
        self.progress = max(0, min(1, progress))
        self.count = max(0, count)
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
        var updated = segments

        if let lastIndex = updated.indices.last,
           canMerge(updated[lastIndex], decision: decision, snapshot: snapshot) {
            updated[lastIndex].end = max(updated[lastIndex].end, snapshot.timestamp)
            return updated
        }

        let proposedStart = snapshot.timestamp.addingTimeInterval(-tickSeconds)
        let start = max(proposedStart, updated.last?.end ?? proposedStart)
        guard snapshot.timestamp > start else { return updated }

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
        var updated = appUsage

        if let lastIndex = updated.indices.last,
           updated[lastIndex].appName == snapshot.appName,
           updated[lastIndex].bundleID == snapshot.bundleID,
           updated[lastIndex].category == snapshot.category,
           snapshot.timestamp.timeIntervalSince(updated[lastIndex].end) <= mergeGapSeconds {
            updated[lastIndex].end = max(updated[lastIndex].end, snapshot.timestamp)
            return updated
        }

        let proposedStart = snapshot.timestamp.addingTimeInterval(-tickSeconds)
        let start = max(proposedStart, updated.last?.end ?? proposedStart)
        guard snapshot.timestamp > start else { return updated }

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

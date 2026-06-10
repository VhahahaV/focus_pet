import Foundation

public struct ObservationStabilityTracker: Sendable {
    private var lastKey: ObservationStabilityKey?
    private var currentStartedAt: Date?

    public init() {}

    public mutating func observationWithUpdatedStability(_ observation: StateObservation) -> StateObservation {
        let key = ObservationStabilityKey(observation: observation)
        let now = observation.timestamp

        if key != lastKey {
            lastKey = key
            currentStartedAt = now
        }

        var updated = observation
        updated.stableDurationSeconds = currentStartedAt.map { now.timeIntervalSince($0) } ?? 0

        if observation.sourceKind == .demo, observation.stableDurationSeconds > updated.stableDurationSeconds {
            updated.stableDurationSeconds = observation.stableDurationSeconds
        }

        return updated
    }
}

private struct ObservationStabilityKey: Hashable, Sendable {
    var sourceKind: ObservationSourceKind
    var facePresence: FacePresence
    var gazeState: GazeState
    var context: ContextType
    var localActivityTier: LocalActivityStabilityTier

    init(observation: StateObservation) {
        sourceKind = observation.sourceKind
        facePresence = observation.facePresence
        gazeState = observation.gazeState
        context = observation.context
        localActivityTier = LocalActivityStabilityTier(activity: observation.localActivity)
    }
}

private enum LocalActivityStabilityTier: Hashable, Sendable {
    case active
    case recentlyActive
    case idle
    case longIdle

    init(activity: LocalActivitySnapshot) {
        switch activity.lastInputSeconds {
        case ...30:
            self = .active
        case ...60:
            self = .recentlyActive
        case ...180:
            self = .idle
        default:
            self = .longIdle
        }
    }
}

import FocusPetCore
import Foundation

struct RuntimeInputContext: Sendable {
    var timestamp: Date
    var frontAppName: String
    var frontAppBundleID: String?
    var context: ContextType
    var lastInputSeconds: TimeInterval
    var cameraAuthorization: CameraAuthorizationState
    var cameraRunning: Bool
    var latestFrame: CameraFrameMetadata?
}

struct LiveStateSource: Sendable {
    private let builder: LiveObservationBuilder

    init(faceDetector: any FaceStateDetecting = ModelFreeFaceStateDetector()) {
        builder = LiveObservationBuilder(faceDetector: faceDetector)
    }

    func observation(from context: RuntimeInputContext) -> StateObservation {
        builder.makeObservation(
            input: LiveObservationInput(
                timestamp: context.timestamp,
                frontAppName: context.frontAppName,
                frontAppBundleID: context.frontAppBundleID,
                context: context.context,
                lastInputSeconds: context.lastInputSeconds,
                cameraAuthorization: context.cameraAuthorization,
                cameraRunning: context.cameraRunning,
                latestFrame: context.latestFrame
            ),
            stableDurationSeconds: 0
        )
    }
}

struct DemoStateSource {
    private var tickIndex = 0

    mutating func nextObservation(from context: RuntimeInputContext) -> StateObservation {
        tickIndex += 1
        let scriptedState: UserState

        switch tickIndex % 10 {
        case 0, 1, 2, 3:
            scriptedState = .focused
        case 4:
            scriptedState = .possiblyDistracted
        case 5:
            scriptedState = .offScreen
        case 6:
            scriptedState = .lookingDown
        case 7:
            scriptedState = .entertainment
        case 8:
            scriptedState = .away
        default:
            scriptedState = .focused
        }

        return observation(for: scriptedState, from: context, reasonOverride: nil)
    }

    func observation(
        for state: UserState,
        from context: RuntimeInputContext,
        reasonOverride: String?
    ) -> StateObservation {
        StateObservation(
            timestamp: context.timestamp,
            sourceKind: .demo,
            facePresence: state == .away ? .missing : .present,
            gazeState: gaze(for: state),
            headPitchDegrees: state == .lookingDown ? 32 : 4,
            frontAppName: context.frontAppName,
            context: contextForDemoState(state, fallback: context.context),
            lastInputSeconds: context.lastInputSeconds,
            stableDurationSeconds: scriptedDuration(for: state)
        )
    }

    func reasonOverride(for state: UserState) -> String {
        switch state {
        case .focused: "manual_demo_focus"
        case .possiblyDistracted, .offScreen: "manual_demo_distracted"
        case .lookingDown: "manual_demo_posture"
        case .entertainment: "manual_demo_entertainment"
        case .away: "manual_demo_away"
        default: "manual_demo_unknown"
        }
    }

    private func contextForDemoState(_ state: UserState, fallback: ContextType) -> ContextType {
        switch state {
        case .entertainment:
            .entertainment
        case .meeting:
            .meeting
        case .away:
            .neutral
        default:
            fallback == .neutral ? .work : fallback
        }
    }

    private func gaze(for state: UserState) -> GazeState {
        switch state {
        case .focused, .meeting, .resting, .entertainment:
            .screen
        case .possiblyDistracted, .offScreen:
            .offScreen
        case .lookingDown:
            .down
        case .away, .unknown:
            .unknown
        }
    }

    private func scriptedDuration(for state: UserState) -> TimeInterval {
        switch state {
        case .focused:
            900
        case .possiblyDistracted:
            24
        case .offScreen:
            34
        case .lookingDown:
            130
        case .entertainment:
            1_260
        case .away:
            28
        default:
            6
        }
    }
}

struct ObservationStabilityTracker {
    private var lastKey: ObservationStabilityKey?
    private var currentStartedAt: Date?

    mutating func observationWithUpdatedStability(_ observation: StateObservation) -> StateObservation {
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

private struct ObservationStabilityKey: Hashable {
    var sourceKind: ObservationSourceKind
    var facePresence: FacePresence
    var gazeState: GazeState
    var context: ContextType
    var frontAppName: String?
    var inputBucket: Int

    init(observation: StateObservation) {
        sourceKind = observation.sourceKind
        facePresence = observation.facePresence
        gazeState = observation.gazeState
        context = observation.context
        frontAppName = observation.frontAppName
        inputBucket = observation.lastInputSeconds <= 20 ? 0 : 1
    }
}

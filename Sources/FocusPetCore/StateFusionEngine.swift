import Foundation

public struct StateFusionEngine: Sendable {
    public init() {}

    public func fuse(_ observation: StateObservation) -> FusedUserState {
        if !observation.facePresent, observation.stableDurationSeconds >= 15 {
            return state(
                observation,
                .away,
                confidence: 0.78,
                reason: ["face_missing_over_15s"]
            )
        }

        if observation.context == .meeting {
            return state(
                observation,
                .meeting,
                confidence: 0.88,
                reason: ["front_app_is_meeting", observation.facePresent ? "face_present" : "face_missing"]
            )
        }

        if observation.context == .entertainment {
            return state(
                observation,
                .entertainment,
                confidence: 0.92,
                reason: ["front_app_is_entertainment"]
            )
        }

        if observation.facePresent,
           (observation.gazeState == .down || observation.headPitchDegrees >= 28),
           observation.stableDurationSeconds >= 60 {
            return state(
                observation,
                .lookingDown,
                confidence: 0.86,
                reason: ["head_pitch_down_over_60s"]
            )
        }

        if observation.facePresent,
           observation.context == .work,
           observation.gazeState == .offScreen,
           observation.stableDurationSeconds >= 30 {
            return state(
                observation,
                .offScreen,
                confidence: 0.82,
                reason: ["front_app_is_work", "gaze_off_screen_over_30s", "face_present"]
            )
        }

        if observation.facePresent,
           observation.context == .work,
           observation.gazeState == .offScreen,
           observation.stableDurationSeconds >= 20 {
            return state(
                observation,
                .possiblyDistracted,
                confidence: 0.76,
                reason: ["front_app_is_work", "gaze_off_screen_over_20s", "face_present"]
            )
        }

        if observation.facePresent,
           observation.context == .work,
           observation.gazeState == .screen {
            return state(
                observation,
                .focused,
                confidence: 0.86,
                reason: ["front_app_is_work", "gaze_on_screen", "face_present"]
            )
        }

        if observation.facePresent, observation.gazeState == .screen {
            return state(
                observation,
                .resting,
                confidence: 0.68,
                reason: ["gaze_on_screen", "neutral_context"]
            )
        }

        return state(
            observation,
            .unknown,
            confidence: 0.4,
            reason: ["low_confidence_or_transition"]
        )
    }

    private func state(
        _ observation: StateObservation,
        _ userState: UserState,
        confidence: Double,
        reason: [String]
    ) -> FusedUserState {
        FusedUserState(
            timestamp: observation.timestamp,
            userState: userState,
            context: observation.context,
            confidence: confidence,
            reason: reason,
            stableDurationSeconds: observation.stableDurationSeconds
        )
    }
}

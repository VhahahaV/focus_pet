import Foundation

public struct StateFusionEngine: Sendable {
    private let missingFaceAwaySeconds: TimeInterval
    private let idleAwaySeconds: TimeInterval
    private let offScreenDistractedSeconds: TimeInterval
    private let headDownDistractedSeconds: TimeInterval
    private let entertainmentDistractedSeconds: TimeInterval
    private let idleDistractedSeconds: TimeInterval
    private let meetingIdleAwaySeconds: TimeInterval

    public init(
        missingFaceAwaySeconds: TimeInterval = 45,
        idleAwaySeconds: TimeInterval = 180,
        offScreenDistractedSeconds: TimeInterval = 8,
        headDownDistractedSeconds: TimeInterval = 12,
        entertainmentDistractedSeconds: TimeInterval = 30,
        idleDistractedSeconds: TimeInterval = 60,
        meetingIdleAwaySeconds: TimeInterval = 600
    ) {
        self.missingFaceAwaySeconds = missingFaceAwaySeconds
        self.idleAwaySeconds = idleAwaySeconds
        self.offScreenDistractedSeconds = offScreenDistractedSeconds
        self.headDownDistractedSeconds = headDownDistractedSeconds
        self.entertainmentDistractedSeconds = entertainmentDistractedSeconds
        self.idleDistractedSeconds = idleDistractedSeconds
        self.meetingIdleAwaySeconds = meetingIdleAwaySeconds
    }

    public func fuse(_ observation: StateObservation) -> FusedUserState {
        let activity = observation.localActivity

        if observation.facePresence == .missing,
           observation.lastInputSeconds > 30,
           observation.stableDurationSeconds >= missingFaceAwaySeconds {
            return state(
                observation,
                .away,
                confidence: 0.8,
                reason: ["face_missing_sustained"]
            )
        }

        if observation.facePresence == .present,
           observation.gazeState == .screen {
            return state(
                observation,
                .focused,
                confidence: 0.9,
                reason: ["gaze_on_screen", "face_present"]
            )
        }

        if observation.context == .entertainment,
           observation.stableDurationSeconds >= entertainmentDistractedSeconds {
            return state(
                observation,
                .distracted,
                confidence: 0.86,
                reason: ["front_app_is_entertainment", "entertainment_context_over_30s"]
            )
        }

        if observation.facePresence == .present,
           observation.gazeState == .offScreen,
           observation.stableDurationSeconds >= offScreenDistractedSeconds {
            return state(
                observation,
                .distracted,
                confidence: 0.84,
                reason: ["gaze_off_screen_over_threshold", "face_present"]
            )
        }

        if observation.facePresence == .present,
           (observation.gazeState == .down || observation.headPitchDegrees >= 28),
           observation.stableDurationSeconds >= headDownDistractedSeconds {
            return state(
                observation,
                .distracted,
                confidence: 0.84,
                reason: ["head_down_over_threshold", "face_present"]
            )
        }

        if observation.facePresence == .present,
           observation.gazeState == .side,
           observation.stableDurationSeconds >= offScreenDistractedSeconds {
            return state(
                observation,
                .distracted,
                confidence: 0.8,
                reason: ["side_head_over_threshold", "face_present"]
            )
        }

        if observation.context == .meeting,
           observation.facePresence == .unknown,
           observation.lastInputSeconds >= meetingIdleAwaySeconds {
            return state(
                observation,
                .away,
                confidence: 0.68,
                reason: ["meeting_idle_over_10m", "local_input_idle"]
            )
        }

        if observation.context == .meeting,
           observation.facePresence != .missing,
           observation.lastInputSeconds < meetingIdleAwaySeconds,
           (activity.frontAppStableSeconds >= 60 || !activity.hasDetailedInputBreakdown) {
            return state(
                observation,
                .focused,
                confidence: 0.74,
                reason: ["meeting_context_without_input", "stable_front_app"]
            )
        }

        if activity.hasDetailedInputBreakdown,
           observation.context == .work,
           activity.hasRecentKeyboardInput,
           activity.hasStableFrontApp {
            return state(
                observation,
                .focused,
                confidence: 0.82,
                reason: ["work_keyboard_activity", "stable_front_app"]
            )
        }

        if activity.hasDetailedInputBreakdown,
           observation.context == .work,
           activity.hasRecentInput {
            return state(
                observation,
                .focused,
                confidence: 0.76,
                reason: ["work_recent_activity", "local_input_active"]
            )
        }

        if observation.facePresence == .unknown,
           observation.context != .meeting,
           observation.lastInputSeconds >= idleAwaySeconds {
            return state(
                observation,
                .away,
                confidence: 0.7,
                reason: activity.hasDetailedInputBreakdown
                    ? ["local_input_idle_over_180s"]
                    : ["vision_unknown", "input_idle_over_180s"]
            )
        }

        if activity.hasDetailedInputBreakdown,
           observation.context != .meeting,
           observation.lastInputSeconds >= idleDistractedSeconds {
            return state(
                observation,
                .distracted,
                confidence: 0.66,
                reason: ["local_idle_over_60s"]
            )
        }

        if activity.hasDetailedInputBreakdown,
           observation.context == .neutral,
           activity.hasRecentInput {
            return state(
                observation,
                .focused,
                confidence: 0.68,
                reason: ["recent_local_activity", "neutral_context"]
            )
        }

        if observation.facePresence != .present,
           observation.context != .entertainment,
           observation.lastInputSeconds <= 30 {
            return state(
                observation,
                .focused,
                confidence: 0.68,
                reason: ["recent_input", "vision_unconfirmed"]
            )
        }

        if observation.lastInputSeconds >= idleDistractedSeconds {
            return state(
                observation,
                .distracted,
                confidence: 0.62,
                reason: ["input_idle_without_confirmed_screen_gaze"]
            )
        }

        return state(
            observation,
            .focused,
            confidence: 0.58,
            reason: ["default_to_focused_until_distraction_stable"]
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

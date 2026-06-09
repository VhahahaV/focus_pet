import Foundation

public struct FaceGeometrySnapshot: Codable, Hashable, Sendable {
    public var yawDegrees: Double?
    public var pitchDegrees: Double?
    public var rollDegrees: Double?
    public var boundingBoxCenterY: Double?
    public var confidence: Double

    public init(
        yawDegrees: Double?,
        pitchDegrees: Double?,
        rollDegrees: Double?,
        boundingBoxCenterY: Double?,
        confidence: Double
    ) {
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
        self.rollDegrees = rollDegrees
        self.boundingBoxCenterY = boundingBoxCenterY
        self.confidence = confidence
    }
}

public struct FaceStateHeuristics: Sendable {
    private let yawOffScreenThreshold: Double
    private let pitchDownThreshold: Double

    public init(yawOffScreenThreshold: Double = 24, pitchDownThreshold: Double = 24) {
        self.yawOffScreenThreshold = yawOffScreenThreshold
        self.pitchDownThreshold = pitchDownThreshold
    }

    public func result(from snapshot: FaceGeometrySnapshot?) -> FaceDetectionResult {
        guard let snapshot else {
            return FaceDetectionResult(
                facePresence: .missing,
                gazeState: .unknown,
                headPitchDegrees: 0,
                confidence: 0.78,
                reason: "no_face_detected"
            )
        }

        let yaw = snapshot.yawDegrees ?? 0
        let pitch = snapshot.pitchDegrees ?? estimatedPitch(fromBoundingBoxCenterY: snapshot.boundingBoxCenterY)
        let confidence = min(0.95, max(0.35, snapshot.confidence))

        if pitch >= pitchDownThreshold {
            return FaceDetectionResult(
                facePresence: .present,
                gazeState: .down,
                headPitchDegrees: pitch,
                confidence: confidence,
                reason: "pitch_over_threshold"
            )
        }

        if abs(yaw) >= yawOffScreenThreshold {
            return FaceDetectionResult(
                facePresence: .present,
                gazeState: .offScreen,
                headPitchDegrees: pitch,
                confidence: confidence,
                reason: "yaw_over_threshold"
            )
        }

        return FaceDetectionResult(
            facePresence: .present,
            gazeState: .screen,
            headPitchDegrees: pitch,
            confidence: confidence,
            reason: "face_centered"
        )
    }

    private func estimatedPitch(fromBoundingBoxCenterY centerY: Double?) -> Double {
        guard let centerY else { return 0 }

        if centerY < 0.42 {
            return 28
        }

        if centerY > 0.72 {
            return -8
        }

        return 0
    }
}

import FocusPetCore
import Foundation

struct RuntimeInputContext: Sendable {
    var timestamp: Date
    var frontAppName: String
    var frontAppBundleID: String?
    var frontWindowTitle: String?
    var context: ContextType
    var lastInputSeconds: TimeInterval
    var cameraAuthorization: CameraAuthorizationState
    var cameraRunning: Bool
    var latestFrame: CameraFrameMetadata?
    var latestFaceDetection: FaceDetectionResult?
    var localActivity: LocalActivitySnapshot
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
                latestFrame: context.latestFrame,
                latestFaceDetection: context.latestFaceDetection,
                localActivity: context.localActivity
            ),
            stableDurationSeconds: 0
        )
    }
}

import Foundation

public enum CameraAuthorizationState: String, Codable, Hashable, Sendable, CaseIterable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unknown
}

public struct CameraFrameMetadata: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var sequenceNumber: Int

    public init(timestamp: Date, sequenceNumber: Int) {
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
    }
}

public struct FaceDetectionResult: Codable, Hashable, Sendable {
    public var facePresence: FacePresence
    public var gazeState: GazeState
    public var headPitchDegrees: Double
    public var confidence: Double
    public var reason: String

    public init(
        facePresence: FacePresence,
        gazeState: GazeState,
        headPitchDegrees: Double,
        confidence: Double,
        reason: String
    ) {
        self.facePresence = facePresence
        self.gazeState = gazeState
        self.headPitchDegrees = headPitchDegrees
        self.confidence = confidence
        self.reason = reason
    }
}

public protocol FaceStateDetecting: Sendable {
    func detect(from frame: CameraFrameMetadata?) -> FaceDetectionResult
}

public struct ModelFreeFaceStateDetector: FaceStateDetecting {
    public init() {}

    public func detect(from frame: CameraFrameMetadata?) -> FaceDetectionResult {
        FaceDetectionResult(
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            confidence: 0,
            reason: frame == nil ? "no_camera_frame" : "model_not_configured"
        )
    }
}

public struct LiveObservationInput: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var frontAppName: String
    public var frontAppBundleID: String?
    public var context: ContextType
    public var lastInputSeconds: TimeInterval
    public var cameraAuthorization: CameraAuthorizationState
    public var cameraRunning: Bool
    public var latestFrame: CameraFrameMetadata?
    public var latestFaceDetection: FaceDetectionResult?

    public init(
        timestamp: Date,
        frontAppName: String,
        frontAppBundleID: String?,
        context: ContextType,
        lastInputSeconds: TimeInterval,
        cameraAuthorization: CameraAuthorizationState,
        cameraRunning: Bool,
        latestFrame: CameraFrameMetadata?,
        latestFaceDetection: FaceDetectionResult? = nil
    ) {
        self.timestamp = timestamp
        self.frontAppName = frontAppName
        self.frontAppBundleID = frontAppBundleID
        self.context = context
        self.lastInputSeconds = lastInputSeconds
        self.cameraAuthorization = cameraAuthorization
        self.cameraRunning = cameraRunning
        self.latestFrame = latestFrame
        self.latestFaceDetection = latestFaceDetection
    }
}

public struct LiveObservationBuilder: Sendable {
    private let faceDetector: any FaceStateDetecting

    public init(faceDetector: any FaceStateDetecting) {
        self.faceDetector = faceDetector
    }

    public func makeObservation(
        input: LiveObservationInput,
        stableDurationSeconds: TimeInterval
    ) -> StateObservation {
        let detection = input.latestFaceDetection ?? faceDetector.detect(from: input.latestFrame)

        return StateObservation(
            timestamp: input.timestamp,
            sourceKind: .live,
            facePresence: detection.facePresence,
            gazeState: detection.gazeState,
            headPitchDegrees: detection.headPitchDegrees,
            frontAppName: input.frontAppName,
            context: input.context,
            lastInputSeconds: input.lastInputSeconds,
            stableDurationSeconds: stableDurationSeconds
        )
    }
}

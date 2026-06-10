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
    public var localActivity: LocalActivitySnapshot

    public init(
        timestamp: Date,
        frontAppName: String,
        frontAppBundleID: String?,
        context: ContextType,
        lastInputSeconds: TimeInterval,
        cameraAuthorization: CameraAuthorizationState,
        cameraRunning: Bool,
        latestFrame: CameraFrameMetadata?,
        latestFaceDetection: FaceDetectionResult? = nil,
        localActivity: LocalActivitySnapshot? = nil
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
        self.localActivity = localActivity ?? .legacy(lastInputSeconds: lastInputSeconds)
    }
}

public struct LiveObservationBuilder: Sendable {
    private let faceDetector: any FaceStateDetecting
    private let maxFaceDetectionAgeSeconds: TimeInterval
    private let minFaceDetectionConfidence: Double

    public init(
        faceDetector: any FaceStateDetecting,
        maxFaceDetectionAgeSeconds: TimeInterval = 20,
        minFaceDetectionConfidence: Double = 0.55
    ) {
        self.faceDetector = faceDetector
        self.maxFaceDetectionAgeSeconds = maxFaceDetectionAgeSeconds
        self.minFaceDetectionConfidence = minFaceDetectionConfidence
    }

    public func makeObservation(
        input: LiveObservationInput,
        stableDurationSeconds: TimeInterval
    ) -> StateObservation {
        let detection = usableFaceDetection(from: input)

        return StateObservation(
            timestamp: input.timestamp,
            sourceKind: .live,
            facePresence: detection.facePresence,
            gazeState: detection.gazeState,
            headPitchDegrees: detection.headPitchDegrees,
            frontAppName: input.frontAppName,
            context: input.context,
            lastInputSeconds: input.lastInputSeconds,
            stableDurationSeconds: stableDurationSeconds,
            localActivity: input.localActivity
        )
    }

    private func usableFaceDetection(from input: LiveObservationInput) -> FaceDetectionResult {
        guard input.cameraAuthorization == .authorized,
              input.cameraRunning else {
            return unknownDetection(reason: "camera_not_running")
        }

        guard let frame = input.latestFrame,
              input.timestamp.timeIntervalSince(frame.timestamp) <= maxFaceDetectionAgeSeconds else {
            return unknownDetection(reason: "stale_or_missing_camera_frame")
        }

        let detection = input.latestFaceDetection ?? faceDetector.detect(from: frame)
        guard detection.confidence >= minFaceDetectionConfidence else {
            return unknownDetection(reason: "low_confidence_camera_ignored")
        }

        return detection
    }

    private func unknownDetection(reason: String) -> FaceDetectionResult {
        FaceDetectionResult(
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            confidence: 0,
            reason: reason
        )
    }
}

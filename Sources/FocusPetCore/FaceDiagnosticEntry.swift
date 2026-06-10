import Foundation

public enum FaceDiagnosticPhase: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case frame
    case fusion

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .frame: "帧"
        case .fusion: "融合"
        }
    }
}

public struct FaceDiagnosticEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var timestamp: Date
    public var phase: FaceDiagnosticPhase
    public var frameSequenceNumber: Int?
    public var facePresence: FacePresence
    public var gazeState: GazeState
    public var headPitchDegrees: Double
    public var visionConfidence: Double
    public var fusedState: UserState?
    public var context: ContextType
    public var stableDurationSeconds: TimeInterval
    public var reason: [String]
    public var frontAppName: String?
    public var frontWindowTitle: String?
    public var localActivity: LocalActivitySnapshot?
    public var contextConfidence: Double?
    public var contextReason: [String]?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date,
        phase: FaceDiagnosticPhase,
        frameSequenceNumber: Int?,
        facePresence: FacePresence,
        gazeState: GazeState,
        headPitchDegrees: Double,
        visionConfidence: Double,
        fusedState: UserState?,
        context: ContextType,
        stableDurationSeconds: TimeInterval,
        reason: [String],
        frontAppName: String? = nil,
        frontWindowTitle: String? = nil,
        localActivity: LocalActivitySnapshot? = nil,
        contextConfidence: Double? = nil,
        contextReason: [String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.phase = phase
        self.frameSequenceNumber = frameSequenceNumber
        self.facePresence = facePresence
        self.gazeState = gazeState
        self.headPitchDegrees = headPitchDegrees
        self.visionConfidence = visionConfidence
        self.fusedState = fusedState
        self.context = context
        self.stableDurationSeconds = stableDurationSeconds
        self.reason = reason
        self.frontAppName = frontAppName
        self.frontWindowTitle = frontWindowTitle
        self.localActivity = localActivity
        self.contextConfidence = contextConfidence
        self.contextReason = contextReason
    }
}

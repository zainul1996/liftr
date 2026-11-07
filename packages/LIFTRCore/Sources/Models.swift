import Foundation

public enum TrackingCapability: String, Codable, Sendable { case automatic, assisted, manual }
public struct ExerciseDefinition: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var equipment: String
    public var capability: TrackingCapability
    public init(id: String, name: String, equipment: String, capability: TrackingCapability = .manual) {
        self.id = id; self.name = name; self.equipment = equipment; self.capability = capability
    }
}
public enum ExerciseLibrary {
    public static let taxonomyVersion = 1
    public static let all: [ExerciseDefinition] = [
        .init(id: "machine_chest_press", name: "Machine Chest Press", equipment: "Seated chest press machine"),
        .init(id: "machine_shoulder_press", name: "Machine Shoulder Press", equipment: "Seated shoulder press machine"),
        .init(id: "cable_fly_high_low", name: "High-to-Low Chest Fly", equipment: "Cable machine"),
        .init(id: "cable_fly_mid", name: "Mid-Height Chest Fly", equipment: "Cable machine"),
        .init(id: "cable_fly_low_high", name: "Low-to-High Chest Fly", equipment: "Cable machine"),
        .init(id: "dumbbell_bicep_curl", name: "Dumbbell Bicep Curl", equipment: "Dumbbells"),
        .init(id: "machine_triceps_extension", name: "Machine Triceps Extension", equipment: "Seated supported-arm machine"),
        .init(id: "seated_leg_extension", name: "Seated Leg Extension", equipment: "Leg extension machine, provisional"),
        .init(id: "seated_leg_curl", name: "Seated Leg Curl", equipment: "Seated leg curl machine, provisional")
    ]
    public static func find(id: String) -> ExerciseDefinition? { all.first { $0.id == id } }
}
public struct Vector3: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double; public var z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}
public struct Quaternion: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double; public var z: Double; public var w: Double
    public init(x: Double, y: Double, z: Double, w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }
}
public struct MotionSample: Codable, Equatable, Sendable {
    /// Core Motion monotonic seconds since boot, never wall-clock seconds.
    public var timestamp: TimeInterval
    public var userAcceleration: Vector3
    public var rotationRate: Vector3
    public var gravity: Vector3
    public var attitude: Quaternion
    public init(timestamp: TimeInterval, userAcceleration: Vector3, rotationRate: Vector3, gravity: Vector3, attitude: Quaternion) {
        self.timestamp = timestamp; self.userAcceleration = userAcceleration; self.rotationRate = rotationRate; self.gravity = gravity; self.attitude = attitude
    }
}
public struct SensorConfiguration: Codable, Equatable, Sendable {
    public var targetHz: Double = 50
    public var accelerationUnit: String = "g"
    public var rotationRateUnit: String = "rad/s"
    public var timestampUnit: String = "seconds_since_boot"
    public var coordinateFrame: String = "CMDeviceMotion device axes, xArbitraryZVertical reference frame"
    public init(targetHz: Double = 50) { self.targetHz = targetHz }
}
public enum LabelReviewStatus: String, Codable, Sendable { case unreviewed, reviewed, corrected }
public enum RecordingMode: String, Codable, Sendable { case set, continuous }
public enum RecordingStatus: String, Codable, Sendable { case complete, interrupted }
public struct RecordingMetadata: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var participantID: String
    public var sessionID: UUID
    public var exerciseID: String?
    public var equipment: String?
    public var weightKG: Double?
    public var actualReps: Int?
    public var startedAt: Date
    public var endedAt: Date?
    public var watchWrist: String
    public var watchModel: String
    public var watchOSVersion: String
    public var sensorConfiguration: SensorConfiguration
    public var schemaVersion: Int
    public var taxonomyVersion: Int
    public var labelReviewStatus: LabelReviewStatus
    public var mode: RecordingMode
    public var status: RecordingStatus
    public init(id: UUID = UUID(), participantID: String, sessionID: UUID, exerciseID: String? = nil, equipment: String? = nil, weightKG: Double? = nil, actualReps: Int? = nil, startedAt: Date = Date(), endedAt: Date? = nil, watchWrist: String, watchModel: String, watchOSVersion: String, sensorConfiguration: SensorConfiguration = .init(), schemaVersion: Int = 1, taxonomyVersion: Int = 1, labelReviewStatus: LabelReviewStatus = .unreviewed, mode: RecordingMode = .set, status: RecordingStatus = .complete) {
        self.id = id; self.participantID = participantID; self.sessionID = sessionID; self.exerciseID = exerciseID; self.equipment = equipment; self.weightKG = weightKG; self.actualReps = actualReps; self.startedAt = startedAt; self.endedAt = endedAt; self.watchWrist = watchWrist; self.watchModel = watchModel; self.watchOSVersion = watchOSVersion; self.sensorConfiguration = sensorConfiguration; self.schemaVersion = schemaVersion; self.taxonomyVersion = taxonomyVersion; self.labelReviewStatus = labelReviewStatus; self.mode = mode; self.status = status
    }
}
public struct SetAnnotation: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var exerciseID: String
    public var startTimestamp: TimeInterval
    public var endTimestamp: TimeInterval
    public var actualReps: Int?
    public var weightKG: Double?
    public var repBoundaries: [TimeInterval]?
    public init(id: UUID = UUID(), exerciseID: String, startTimestamp: TimeInterval, endTimestamp: TimeInterval, actualReps: Int? = nil, weightKG: Double? = nil, repBoundaries: [TimeInterval]? = nil) {
        self.id = id; self.exerciseID = exerciseID; self.startTimestamp = startTimestamp; self.endTimestamp = endTimestamp; self.actualReps = actualReps; self.weightKG = weightKG; self.repBoundaries = repBoundaries
    }
}
public struct Recording: Codable, Identifiable, Equatable, Sendable {
    public var metadata: RecordingMetadata
    public var samples: [MotionSample]
    public var annotations: [SetAnnotation]
    public var id: UUID { metadata.id }
    public init(metadata: RecordingMetadata, samples: [MotionSample], annotations: [SetAnnotation] = []) { self.metadata = metadata; self.samples = samples; self.annotations = annotations }
}
public enum RecordingJSON {
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }
    public static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

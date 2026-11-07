import Foundation
import LIFTRCore

// This is an integration fixture, never real gym data or a training example.
let started = Date(timeIntervalSince1970: 1_799_999_000)
let metadata = RecordingMetadata(
    participantID: "synthetic-schema-test-only", sessionID: UUID(),
    exerciseID: "machine_chest_press", equipment: "Synthetic schema fixture",
    weightKG: 40, actualReps: 2, startedAt: started,
    endedAt: started.addingTimeInterval(2), watchWrist: "left",
    watchModel: "synthetic-test", watchOSVersion: "synthetic-test", labelReviewStatus: .reviewed
)
let samples = (0...100).map { index in
    MotionSample(timestamp: 100 + Double(index) / 50,
        userAcceleration: .init(x: 0, y: 0.1, z: 0), rotationRate: .init(x: 0, y: 0, z: 0),
        gravity: .init(x: 0, y: -1, z: 0), attitude: .init(x: 0, y: 0, z: 0, w: 1))
}
let annotation = SetAnnotation(exerciseID: "machine_chest_press", startTimestamp: 100,
    endTimestamp: 102, actualReps: 2, weightKG: 40, repBoundaries: [100.1, 101.1])
let data = try RecordingJSON.encoder().encode(Recording(metadata: metadata, samples: samples, annotations: [annotation]))
if CommandLine.arguments.count > 1 {
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
} else { FileHandle.standardOutput.write(data) }

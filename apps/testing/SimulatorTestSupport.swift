#if DEBUG && targetEnvironment(simulator)
  import Foundation
  import LIFTRCore

  /// Explicit test-only data injection. This code is absent from Release and physical-device builds.
  enum SimulatorTestSupport {
    static let recordingID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    static var enabled: Bool {
      ProcessInfo.processInfo.arguments.contains("--liftr-ui-testing")
        && ProcessInfo.processInfo.environment["LIFTR_UI_TESTING"] == "1"
    }
    static func prepare(directory: URL) throws {
      guard enabled else { return }
      let root = directory.deletingLastPathComponent()
      guard directory.lastPathComponent == "Recordings", root.lastPathComponent == "LIFTR" else {
        return
      }
      let env = ProcessInfo.processInfo.environment
      if env["LIFTR_UI_TEST_RESET"] == "1" {
        if FileManager.default.fileExists(atPath: root.path) {
          try FileManager.default.removeItem(at: root)
        }
        let exports = FileManager.default.temporaryDirectory.appendingPathComponent("LIFTR-Exports")
        if FileManager.default.fileExists(atPath: exports.path) {
          try FileManager.default.removeItem(at: exports)
        }
      }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if env["LIFTR_UI_TEST_FIXTURE"] == "set" || env["LIFTR_UI_TEST_FIXTURE"] == "corrupt" {
        let url = directory.appendingPathComponent(recordingID.uuidString + ".liftr.json")
        if !FileManager.default.fileExists(atPath: url.path) {
          try RecordingJSON.encoder().encode(recording()).write(to: url, options: .atomic)
        }
      }
      if env["LIFTR_UI_TEST_FIXTURE"] == "corrupt" {
        try Data("explicitly synthetic invalid recording".utf8).write(
          to: directory.appendingPathComponent("99999999-9999-4999-8999-999999999999.liftr.json"))
      }
      if env["LIFTR_UI_TEST_EXPORT_FAILURE"] == "1" {
        try Data("synthetic filesystem collision".utf8).write(
          to: FileManager.default.temporaryDirectory.appendingPathComponent("LIFTR-Exports"))
      }
      if env["LIFTR_UI_TEST_REVIEW_FAILURE"] == "1" {
        try FileManager.default.createDirectory(
          at: root.appendingPathComponent("reviews.json"), withIntermediateDirectories: true)
      }
    }
    static func recording() -> Recording {
      let started = Date(timeIntervalSince1970: 1_800_000_000)
      let metadata = RecordingMetadata(
        id: recordingID, participantID: "synthetic-ui-test-never-train",
        sessionID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        exerciseID: "machine_chest_press", equipment: "Synthetic test machine variant",
        weightKG: 40, actualReps: 2, startedAt: started, endedAt: started.addingTimeInterval(2),
        watchWrist: "synthetic", watchModel: "synthetic-ui-test",
        watchOSVersion: "synthetic-ui-test", labelReviewStatus: .reviewed)
      let samples = (0...100).map { index in
        MotionSample(
          timestamp: 100 + Double(index) / 50,
          userAcceleration: .init(x: 0, y: sin(Double(index) / 10) * 0.2, z: 0),
          rotationRate: .init(x: 0, y: 0, z: 0), gravity: .init(x: 0, y: -1, z: 0),
          attitude: .init(x: 0, y: 0, z: 0, w: 1))
      }
      return Recording(
        metadata: metadata, samples: samples,
        annotations: [
          .init(
            exerciseID: "machine_chest_press", startTimestamp: 100, endTimestamp: 102,
            actualReps: 2, weightKG: 40)
        ])
    }
  }
#endif

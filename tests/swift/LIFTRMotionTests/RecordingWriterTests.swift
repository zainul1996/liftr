import Foundation
import LIFTRCore
import XCTest

@testable import LIFTRMotion

final class RecordingWriterTests: XCTestCase {
  private func sample(_ timestamp: Double) -> MotionSample {
    .init(
      timestamp: timestamp, userAcceleration: .init(x: 0.1, y: 0.2, z: 0.3),
      rotationRate: .init(x: 0, y: 0, z: 0), gravity: .init(x: 0, y: 0, z: -1),
      attitude: .init(x: 0, y: 0, z: 0, w: 1))
  }
  private func metadata() -> RecordingMetadata {
    .init(
      participantID: "test-only", sessionID: UUID(), exerciseID: "machine_chest_press",
      startedAt: Date(timeIntervalSince1970: 1_700_000_000), watchWrist: "left",
      watchModel: "fixture", watchOSVersion: "fixture")
  }

  func testStreamingProducesCanonicalDecodableRecordingWithAnnotation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var metadata = metadata()
    let writer = try StreamingRecordingWriter(directory: directory, metadata: metadata)
    for timestamp in [100.0, 100.02, 100.04] { try writer.append(sample(timestamp)) }
    metadata.actualReps = 2
    metadata.endedAt = metadata.startedAt.addingTimeInterval(0.04)
    let annotation = SetAnnotation(
      exerciseID: metadata.exerciseID!, startTimestamp: 100, endTimestamp: 100.04, actualReps: 2)
    let url = try writer.finish(metadata: metadata, annotations: [annotation])
    let decoded = try RecordingJSON.decoder().decode(Recording.self, from: Data(contentsOf: url))
    XCTAssertEqual(decoded.samples.count, 3)
    XCTAssertEqual(decoded.annotations, [annotation])
    XCTAssertEqual(decoded.metadata.actualReps, 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: writer.partialURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: writer.draftMetadataURL.path))
  }

  func testDiagnosticsMeasureRateAndRejectReorderedSamples() {
    var quality = MotionQuality()
    XCTAssertTrue(quality.accept(sample(1)))
    XCTAssertTrue(quality.accept(sample(1.02)))
    XCTAssertFalse(quality.accept(sample(1.01)))
    XCTAssertFalse(quality.accept(sample(.nan)))
    XCTAssertTrue(quality.accept(sample(1.12)))
    XCTAssertEqual(quality.sampleCount, 3)
    XCTAssertEqual(quality.rejectedSamples, 2)
    XCTAssertEqual(quality.gapCount, 1)
    XCTAssertEqual(quality.measuredHz!, 2 / 0.12, accuracy: 0.001)
  }

  func testInterruptedWriterPreservesDraftWithoutClaimingCompletion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = try StreamingRecordingWriter(directory: directory, metadata: metadata())
    try writer.append(sample(5))
    writer.preserveDraft()
    XCTAssertTrue(FileManager.default.fileExists(atPath: writer.partialURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: writer.draftMetadataURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: writer.finalURL.path))
    XCTAssertThrowsError(try writer.append(sample(6)))
  }

  func testCrashRecoverySkipsTruncatedTailAndLeavesRepsUnknown() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = try StreamingRecordingWriter(directory: directory, metadata: metadata())
    try writer.append(sample(20))
    try writer.append(sample(20.02))
    writer.preserveDraft()
    let tail = try FileHandle(forWritingTo: writer.partialURL)
    try tail.seekToEnd()
    try tail.write(contentsOf: Data(",{\"timestamp\":20.04,\"gravity\":".utf8))
    try tail.close()
    let recovered = try DraftRecovery.recover(
      metadataURL: writer.draftMetadataURL,
      outputDirectory: directory.appendingPathComponent("recovered"))
    let decoded = try RecordingJSON.decoder().decode(
      Recording.self, from: Data(contentsOf: recovered.fileURL))
    XCTAssertEqual(decoded.samples.count, 2)
    XCTAssertEqual(recovered.skippedLines, 1)
    XCTAssertEqual(decoded.metadata.status, .interrupted)
    XCTAssertEqual(decoded.metadata.labelReviewStatus, .unreviewed)
    XCTAssertNil(decoded.metadata.actualReps)
    XCTAssertNil(decoded.annotations.first?.actualReps)
    XCTAssertEqual(decoded.annotations.first?.startTimestamp, 20)
    XCTAssertEqual(decoded.annotations.first?.endTimestamp, 20.02)
    XCTAssertTrue(FileManager.default.fileExists(atPath: writer.partialURL.path))
  }

  func testFailedFinalRenameCanRetryWithoutDuplicatingJSONSuffix() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let metadata = metadata()
    let writer = try StreamingRecordingWriter(directory: directory, metadata: metadata)
    try writer.append(sample(1))
    try writer.append(sample(1.02))
    try FileManager.default.createDirectory(at: writer.finalURL, withIntermediateDirectories: false)
    XCTAssertThrowsError(try writer.finish(metadata: metadata, annotations: []))
    XCTAssertTrue(FileManager.default.fileExists(atPath: writer.partialURL.path))
    try FileManager.default.removeItem(at: writer.finalURL)
    let final = try writer.finish(metadata: metadata, annotations: [])
    let decoded = try RecordingJSON.decoder().decode(Recording.self, from: Data(contentsOf: final))
    XCTAssertEqual(decoded.samples.map(\.timestamp), [1, 1.02])
  }

  func testOneSampleCannotBecomeACompletedRecordingOrRecoveredZeroDurationSet() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let metadata = metadata()
    let writer = try StreamingRecordingWriter(directory: directory, metadata: metadata)
    try writer.append(sample(2))
    XCTAssertThrowsError(try writer.finish(metadata: metadata, annotations: []))
    writer.preserveDraft()
    XCTAssertThrowsError(
      try DraftRecovery.recover(
        metadataURL: writer.draftMetadataURL,
        outputDirectory: directory.appendingPathComponent("recovery")))
    XCTAssertTrue(FileManager.default.fileExists(atPath: writer.partialURL.path))
  }

  func testContinuousRecoveryKeepsConfirmedIntervalsAndUnlabelledRest() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var metadata = metadata()
    metadata.mode = .continuous
    metadata.exerciseID = nil
    let writer = try StreamingRecordingWriter(directory: directory, metadata: metadata)
    for timestamp in [10.0, 10.02, 10.04, 10.06, 10.08, 10.10] {
      try writer.append(sample(timestamp))
    }
    let labelled = SetAnnotation(
      exerciseID: "machine_chest_press", startTimestamp: 10.02, endTimestamp: 10.06, actualReps: 3,
      weightKG: 40)
    try writer.checkpoint(annotations: [labelled])
    writer.preserveDraft()
    let result = try DraftRecovery.recover(
      metadataURL: writer.draftMetadataURL,
      outputDirectory: directory.appendingPathComponent("recovery"))
    let recording = try RecordingJSON.decoder().decode(
      Recording.self, from: Data(contentsOf: result.fileURL))
    XCTAssertNil(recording.metadata.exerciseID)
    XCTAssertEqual(recording.metadata.mode, .continuous)
    XCTAssertEqual(recording.samples.count, 6)
    XCTAssertEqual(recording.annotations, [labelled])
    XCTAssertLessThan(recording.samples.first!.timestamp, recording.annotations[0].startTimestamp)
    XCTAssertGreaterThan(recording.samples.last!.timestamp, recording.annotations[0].endTimestamp)
  }
}

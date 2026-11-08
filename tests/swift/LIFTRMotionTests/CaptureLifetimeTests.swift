import Foundation
import LIFTRCore
import XCTest

@testable import LIFTRMotion

final class CaptureLifetimeTests: XCTestCase {
  private func sample(_ t: Double) -> MotionSample {
    .init(
      timestamp: t, userAcceleration: .init(x: 0, y: 0, z: 0),
      rotationRate: .init(x: 0, y: 0, z: 0), gravity: .init(x: 0, y: -1, z: 0),
      attitude: .init(x: 0, y: 0, z: 0, w: 1))
  }
  private func metadata() -> RecordingMetadata {
    .init(
      participantID: "synthetic-lifetime-test", sessionID: UUID(), watchWrist: "left",
      watchModel: "synthetic", watchOSVersion: "synthetic")
  }
  func testStoppedAndOldCallbacksCannotWriteIntoNextRecording() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = MotionCapture()
    let first = metadata()
    let oldToken = try capture.start(directory: directory, metadata: first)
    _ = try capture.append(sample(100), token: oldToken)
    _ = try capture.append(sample(100.02), token: oldToken)
    XCTAssertEqual(capture.stop().sampleCount, 2)
    XCTAssertNil(try capture.append(sample(100.04), token: oldToken))
    _ = try capture.finish(metadata: first, annotations: [])
    let second = metadata()
    let newToken = try capture.start(directory: directory, metadata: second)
    XCTAssertNil(try capture.append(sample(100.06), token: oldToken))
    XCTAssertFalse(capture.fail(token: oldToken))
    _ = try capture.append(sample(200), token: newToken)
    _ = try capture.append(sample(200.02), token: newToken)
    XCTAssertEqual(capture.stop().sampleCount, 2)
    let url = try capture.finish(metadata: second, annotations: [])
    let saved = try RecordingJSON.decoder().decode(Recording.self, from: Data(contentsOf: url))
    XCTAssertEqual(saved.samples.map(\.timestamp), [200, 200.02])
    XCTAssertEqual(saved.metadata.id, second.id)
  }
}

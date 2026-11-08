import Foundation
import LIFTRCore

/// Owns the recording lifetime. Delayed callbacks cannot write into another capture.
public final class MotionCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var writer: StreamingRecordingWriter?
  private var activeToken: UUID?
  public init() {}

  public func start(directory: URL, metadata: RecordingMetadata) throws -> UUID {
    lock.lock()
    defer { lock.unlock() }
    guard writer == nil else { throw CaptureError.alreadyRecording }
    writer = try StreamingRecordingWriter(directory: directory, metadata: metadata)
    let token = UUID()
    activeToken = token
    return token
  }
  public func append(_ sample: MotionSample, token: UUID) throws -> MotionQuality? {
    lock.lock()
    defer { lock.unlock() }
    guard activeToken == token, let writer else { return nil }
    try writer.append(sample)
    return writer.quality
  }
  public func stop() -> MotionQuality {
    lock.lock()
    defer { lock.unlock() }
    activeToken = nil
    return writer?.quality ?? .init()
  }
  /// Returns false for failures from stopped or superseded callbacks.
  public func fail(token: UUID) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard activeToken == token else { return false }
    activeToken = nil
    return true
  }
  public func snapshot() -> MotionQuality {
    lock.lock()
    defer { lock.unlock() }
    return writer?.quality ?? .init()
  }
  public func checkpoint(annotations: [SetAnnotation]) throws {
    lock.lock()
    defer { lock.unlock() }
    guard let writer else { throw CaptureError.noRecording }
    try writer.checkpoint(annotations: annotations)
  }
  public func finish(metadata: RecordingMetadata, annotations: [SetAnnotation]) throws -> URL {
    lock.lock()
    defer { lock.unlock() }
    guard activeToken == nil, let writer else { throw CaptureError.noRecording }
    let url = try writer.finish(metadata: metadata, annotations: annotations)
    self.writer = nil
    return url
  }
  public func preserveDraft() {
    lock.lock()
    defer { lock.unlock() }
    activeToken = nil
    writer?.preserveDraft()
    writer = nil
  }
  public enum CaptureError: LocalizedError {
    case alreadyRecording, noRecording
    public var errorDescription: String? {
      switch self {
      case .alreadyRecording: "Finish the current recording before starting another."
      case .noRecording: "There is no stopped recording to save."
      }
    }
  }
}

#if os(watchOS)
  import CoreMotion
  import Foundation
  import LIFTRCore

  /// Core Motion callbacks and file writes are serialized. UI receives only diagnostics.
  public final class DeviceMotionRecorder: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
      let queue = OperationQueue()
      queue.name = "app.liftr.motion"
      queue.maxConcurrentOperationCount = 1
      queue.qualityOfService = .userInitiated
      return queue
    }()
    private let lock = NSLock()
    private var writer: StreamingRecordingWriter?
    private var active = false
    private var latestUpdate: TimeInterval = 0
    public var onUpdate: (@Sendable (MotionQuality) -> Void)?
    public var onFailure: (@Sendable (String) -> Void)?

    public init() {}

    public func start(directory: URL, metadata: RecordingMetadata) throws {
      guard manager.isDeviceMotionAvailable else { throw MotionError.unavailable }
      guard CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else {
        throw MotionError.referenceFrameUnavailable
      }
      lock.lock()
      defer { lock.unlock() }
      guard !active, writer == nil else { throw MotionError.alreadyRecording }
      writer = try StreamingRecordingWriter(directory: directory, metadata: metadata)
      active = true
      latestUpdate = 0
      manager.deviceMotionUpdateInterval = 1 / metadata.sensorConfiguration.targetHz
      manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) {
        [weak self] motion, error in
        guard let self else { return }
        if let error {
          self.fail(error.localizedDescription)
          return
        }
        guard let motion else { return }
        let q = motion.attitude.quaternion
        let sample = MotionSample(
          timestamp: motion.timestamp,
          userAcceleration: .init(
            x: motion.userAcceleration.x, y: motion.userAcceleration.y, z: motion.userAcceleration.z
          ),
          rotationRate: .init(
            x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z),
          gravity: .init(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
          attitude: .init(x: q.x, y: q.y, z: q.z, w: q.w))
        self.lock.lock()
        guard self.active, let writer = self.writer else {
          self.lock.unlock()
          return
        }
        do {
          try writer.append(sample)
          let quality = writer.quality
          let shouldUpdate = sample.timestamp - self.latestUpdate >= 0.5
          if shouldUpdate { self.latestUpdate = sample.timestamp }
          self.lock.unlock()
          if shouldUpdate { self.onUpdate?(quality) }
        } catch {
          self.lock.unlock()
          self.fail(error.localizedDescription)
        }
      }
    }

    @discardableResult public func stop() -> MotionQuality {
      manager.stopDeviceMotionUpdates()
      lock.lock()
      defer { lock.unlock() }
      active = false
      return writer?.quality ?? .init()
    }

    public func snapshot() -> MotionQuality {
      lock.lock()
      defer { lock.unlock() }
      return writer?.quality ?? .init()
    }

    public func checkpoint(annotations: [SetAnnotation]) throws {
      lock.lock()
      defer { lock.unlock() }
      guard let writer else { throw MotionError.noRecording }
      try writer.checkpoint(annotations: annotations)
    }

    public func finish(metadata: RecordingMetadata, annotations: [SetAnnotation]) throws -> URL {
      lock.lock()
      defer { lock.unlock() }
      guard !active, let writer else { throw MotionError.noRecording }
      let url = try writer.finish(metadata: metadata, annotations: annotations)
      self.writer = nil
      return url
    }

    public func preserveDraft() {
      manager.stopDeviceMotionUpdates()
      lock.lock()
      defer { lock.unlock() }
      active = false
      writer?.preserveDraft()
      writer = nil
    }

    private func fail(_ message: String) {
      manager.stopDeviceMotionUpdates()
      lock.lock()
      active = false
      lock.unlock()
      onFailure?(message)
    }

    public enum MotionError: LocalizedError {
      case unavailable, referenceFrameUnavailable, alreadyRecording, noRecording
      public var errorDescription: String? {
        switch self {
        case .unavailable: "Motion sensors are unavailable. Collect data on a physical Apple Watch."
        case .referenceFrameUnavailable: "The required motion reference frame is unavailable."
        case .alreadyRecording: "Finish the current recording before starting another."
        case .noRecording: "There is no recording to save."
        }
      }
    }
  }
#endif

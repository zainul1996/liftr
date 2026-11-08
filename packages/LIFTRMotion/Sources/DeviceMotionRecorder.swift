#if os(watchOS)
  import CoreMotion
  import Foundation
  import LIFTRCore

  /// Serial callbacks stream to disk through a token-checked capture lifetime.
  public final class DeviceMotionRecorder: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
      let queue = OperationQueue()
      queue.name = "app.liftr.motion"
      queue.maxConcurrentOperationCount = 1
      queue.qualityOfService = .userInitiated
      return queue
    }()
    private let capture = MotionCapture()
    private let updateLock = NSLock()
    private var latestUpdate: TimeInterval = 0
    public var onUpdate: (@Sendable (UUID, MotionQuality) -> Void)?
    public var onFailure: (@Sendable (UUID, String) -> Void)?
    #if DEBUG && targetEnvironment(simulator)
      private var syntheticTimer: DispatchSourceTimer?
      private var isSyntheticUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("--liftr-ui-testing")
          && ProcessInfo.processInfo.environment["LIFTR_UI_TESTING"] == "1"
      }
    #endif
    public init() {}

    public func start(directory: URL, metadata: RecordingMetadata) throws {
      #if DEBUG && targetEnvironment(simulator)
        if isSyntheticUITest {
          if ProcessInfo.processInfo.environment["LIFTR_UI_TEST_MOTION_FAILURE"] == "1" {
            throw MotionError.unavailable
          }
          let token = try capture.start(directory: directory, metadata: metadata)
          resetUpdateClock()
          let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "app.liftr.synthetic-ui-test"))
          timer.schedule(deadline: .now(), repeating: .milliseconds(20))
          timer.setEventHandler { [weak self] in
            let now = ProcessInfo.processInfo.systemUptime
            let sample = MotionSample(
              timestamp: now, userAcceleration: .init(x: 0, y: sin(now * 4) * 0.2, z: 0),
              rotationRate: .init(x: 0, y: 0, z: 0), gravity: .init(x: 0, y: -1, z: 0),
              attitude: .init(x: 0, y: 0, z: 0, w: 1))
            self?.receive(sample, token: token, recordingID: metadata.id)
          }
          syntheticTimer = timer
          timer.resume()
          return
        }
      #endif
      guard manager.isDeviceMotionAvailable else { throw MotionError.unavailable }
      guard CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else {
        throw MotionError.referenceFrameUnavailable
      }
      let token = try capture.start(directory: directory, metadata: metadata)
      resetUpdateClock()
      manager.deviceMotionUpdateInterval = 1 / metadata.sensorConfiguration.targetHz
      manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) {
        [weak self] motion, error in
        guard let self else { return }
        if let error {
          self.fail(error.localizedDescription, token: token, recordingID: metadata.id)
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
        self.receive(sample, token: token, recordingID: metadata.id)
      }
    }
    private func resetUpdateClock() {
      updateLock.lock()
      latestUpdate = 0
      updateLock.unlock()
    }
    private func receive(_ sample: MotionSample, token: UUID, recordingID: UUID) {
      do {
        guard let quality = try capture.append(sample, token: token) else { return }
        updateLock.lock()
        let shouldUpdate = sample.timestamp - latestUpdate >= 0.5
        if shouldUpdate { latestUpdate = sample.timestamp }
        updateLock.unlock()
        if shouldUpdate { onUpdate?(recordingID, quality) }
      } catch { fail(error.localizedDescription, token: token, recordingID: recordingID) }
    }
    @discardableResult public func stop() -> MotionQuality {
      let quality = capture.stop()
      manager.stopDeviceMotionUpdates()
      #if DEBUG && targetEnvironment(simulator)
        syntheticTimer?.cancel()
        syntheticTimer = nil
      #endif
      return quality
    }
    public func snapshot() -> MotionQuality { capture.snapshot() }
    public func checkpoint(annotations: [SetAnnotation]) throws {
      try capture.checkpoint(annotations: annotations)
    }
    public func finish(metadata: RecordingMetadata, annotations: [SetAnnotation]) throws -> URL {
      try capture.finish(metadata: metadata, annotations: annotations)
    }
    public func preserveDraft() {
      _ = stop()
      capture.preserveDraft()
    }
    private func fail(_ message: String, token: UUID, recordingID: UUID) {
      guard capture.fail(token: token) else { return }
      manager.stopDeviceMotionUpdates()
      #if DEBUG && targetEnvironment(simulator)
        syntheticTimer?.cancel()
        syntheticTimer = nil
      #endif
      onFailure?(recordingID, message)
    }
    public enum MotionError: LocalizedError {
      case unavailable, referenceFrameUnavailable
      public var errorDescription: String? {
        switch self {
        case .unavailable: "Motion sensors are unavailable. Collect data on a physical Apple Watch."
        case .referenceFrameUnavailable: "The required motion reference frame is unavailable."
        }
      }
    }
  }
#endif

import Foundation
import LIFTRCore

/// Incremental diagnostics. A target frequency is a request, never a measured rate.
public struct MotionQuality: Equatable, Sendable {
    public private(set) var sampleCount = 0
    public private(set) var rejectedSamples = 0
    public private(set) var gapCount = 0
    public private(set) var firstTimestamp: TimeInterval?
    public private(set) var lastTimestamp: TimeInterval?
    public let targetHz: Double

    public init(targetHz: Double = 50) { self.targetHz = targetHz }

    public var measuredHz: Double? {
        guard sampleCount > 1, let firstTimestamp, let lastTimestamp, lastTimestamp > firstTimestamp else { return nil }
        return Double(sampleCount - 1) / (lastTimestamp - firstTimestamp)
    }

    /// Reject malformed and reordered samples rather than silently rewriting time.
    @discardableResult public mutating func accept(_ sample: MotionSample) -> Bool {
        let values = [sample.timestamp,
                      sample.userAcceleration.x, sample.userAcceleration.y, sample.userAcceleration.z,
                      sample.rotationRate.x, sample.rotationRate.y, sample.rotationRate.z,
                      sample.gravity.x, sample.gravity.y, sample.gravity.z,
                      sample.attitude.x, sample.attitude.y, sample.attitude.z, sample.attitude.w]
        guard values.allSatisfy(\.isFinite), sample.timestamp >= 0,
              lastTimestamp.map({ sample.timestamp > $0 }) ?? true else {
            rejectedSamples += 1
            return false
        }
        if let lastTimestamp, targetHz > 0, sample.timestamp - lastTimestamp > 2.5 / targetHz { gapCount += 1 }
        if firstTimestamp == nil { firstTimestamp = sample.timestamp }
        lastTimestamp = sample.timestamp
        sampleCount += 1
        return true
    }
}

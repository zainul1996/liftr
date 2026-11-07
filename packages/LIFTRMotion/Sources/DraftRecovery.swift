import Foundation
import LIFTRCore

public struct RecoveredDraft: Sendable {
    public let fileURL: URL
    public let metadata: RecordingMetadata
    public let sampleCount: Int
    public let skippedLines: Int
}

/// Replays complete sample lines in small chunks. A truncated final write is excluded.
public enum DraftRecovery {
    public static func recover(metadataURL: URL, outputDirectory: URL) throws -> RecoveredDraft {
        var metadata = try RecordingJSON.decoder().decode(RecordingMetadata.self, from: Data(contentsOf: metadataURL))
        metadata.status = .interrupted
        metadata.actualReps = nil
        metadata.labelReviewStatus = .unreviewed
        let base = metadataURL.deletingPathExtension().deletingPathExtension()
        let source = base.appendingPathExtension("partial")
        let writer = try StreamingRecordingWriter(directory: outputDirectory, metadata: metadata)
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        var buffer = Data()
        var sawHeader = false
        var skipped = 0
        func consume(_ line: Data) throws {
            if !sawHeader {
                guard String(data: line, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "{\"samples\":[" else {
                    throw RecoveryError.invalidHeader
                }
                sawHeader = true
                return
            }
            let payload = line.first == 0x2C ? Data(line.dropFirst()) : line
            guard !payload.isEmpty else { return }
            do {
                let sample = try RecordingJSON.decoder().decode(MotionSample.self, from: payload)
                if try !writer.append(sample) { skipped += 1 }
            } catch let error as DecodingError {
                _ = error
                skipped += 1
            }
        }
        do {
            while let chunk = try reader.read(upToCount: 16_384), !chunk.isEmpty {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    try consume(line)
                }
                guard buffer.count < 16_384 else { throw RecoveryError.oversizedLine }
            }
            if !buffer.isEmpty { try consume(buffer) }
            guard writer.quality.sampleCount > 1, let start = writer.quality.firstTimestamp, let end = writer.quality.lastTimestamp, end > start else {
                throw RecoveryError.noSamples
            }
            // Wall time is approximate after a crash. Raw monotonic sample boundaries stay exact.
            metadata.endedAt = metadata.startedAt.addingTimeInterval(max(0, end - start))
            let checkpointURL = base.appendingPathExtension("annotations.json")
            let savedAnnotations: [SetAnnotation]
            if FileManager.default.fileExists(atPath: checkpointURL.path) {
                savedAnnotations = try RecordingJSON.decoder().decode([SetAnnotation].self, from: Data(contentsOf: checkpointURL))
            } else { savedAnnotations = [] }
            let annotations = metadata.mode == .continuous ? savedAnnotations.filter {
                $0.startTimestamp >= start && $0.endTimestamp <= end && $0.endTimestamp >= $0.startTimestamp
            } : (metadata.exerciseID.map {
                [SetAnnotation(exerciseID: $0, startTimestamp: start, endTimestamp: end, actualReps: nil, weightKG: metadata.weightKG)]
            } ?? [])
            let url = try writer.finish(metadata: metadata, annotations: annotations)
            return .init(fileURL: url, metadata: metadata, sampleCount: writer.quality.sampleCount, skippedLines: skipped)
        } catch {
            writer.preserveDraft()
            throw error
        }
    }

    public enum RecoveryError: LocalizedError {
        case invalidHeader, oversizedLine, noSamples
        public var errorDescription: String? {
            switch self {
            case .invalidHeader: "The unfinished recording has an unrecognized file header."
            case .oversizedLine: "The unfinished recording contains an invalid sensor row."
            case .noSamples: "This unfinished recording contains no complete sensor samples."
            }
        }
    }
}

import Foundation
import LIFTRCore

/// Writes each sample to disk. Memory use does not grow with workout duration.
/// Callers must serialize calls, including finish. Unfinished files stay on disk.
public final class StreamingRecordingWriter {
    public let partialURL: URL
    public let draftMetadataURL: URL
    public let finalURL: URL
    public private(set) var quality: MotionQuality
    private var handle: FileHandle?
    private var finished = false
    private var lastSyncTimestamp: TimeInterval?

    public init(directory: URL, metadata: RecordingMetadata) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        partialURL = directory.appendingPathComponent(metadata.id.uuidString + ".partial")
        draftMetadataURL = directory.appendingPathComponent(metadata.id.uuidString + ".draft.json")
        finalURL = directory.appendingPathComponent(metadata.id.uuidString + ".liftr.json")
        quality = MotionQuality(targetHz: metadata.sensorConfiguration.targetHz)
        guard !FileManager.default.fileExists(atPath: partialURL.path),
              !FileManager.default.fileExists(atPath: finalURL.path) else { throw WriterError.alreadyExists }
        try RecordingJSON.encoder().encode(metadata).write(to: draftMetadataURL, options: .atomic)
        guard FileManager.default.createFile(atPath: partialURL.path, contents: Data("{\"samples\":[\n".utf8)) else {
            throw WriterError.cannotCreateFile
        }
        handle = try FileHandle(forWritingTo: partialURL)
        try handle?.seekToEnd()
    }

    @discardableResult public func append(_ sample: MotionSample) throws -> Bool {
        guard !finished, let handle else { throw WriterError.closed }
        var updatedQuality = quality
        guard updatedQuality.accept(sample) else { quality = updatedQuality; return false }
        var encoded = Data((quality.sampleCount == 0 ? "" : ",").utf8)
        encoded.append(try RecordingJSON.encoder().encode(sample))
        encoded.append(0x0A)
        try handle.write(contentsOf: encoded)
        quality = updatedQuality
        if lastSyncTimestamp == nil || sample.timestamp - (lastSyncTimestamp ?? sample.timestamp) >= 1 {
            try handle.synchronize()
            lastSyncTimestamp = sample.timestamp
        }
        return true
    }

    public func finish(metadata: RecordingMetadata, annotations: [SetAnnotation]) throws -> URL {
        guard !finished, let handle else { throw WriterError.closed }
        guard metadata.id.uuidString == finalURL.deletingPathExtension().deletingPathExtension().lastPathComponent else { throw WriterError.wrongRecording }
        let suffix = Data("],\"metadata\":".utf8)
            + (try RecordingJSON.encoder().encode(metadata))
            + Data(",\"annotations\":".utf8)
            + (try RecordingJSON.encoder().encode(annotations))
            + Data("}".utf8)
        try handle.synchronize()
        // Finalize a disk copy so a storage failure never appends a second JSON suffix on retry.
        let staging = partialURL.appendingPathExtension("finishing")
        if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: partialURL, to: staging)
        do {
            let finalHandle = try FileHandle(forWritingTo: staging)
            do {
                try finalHandle.seekToEnd()
                try finalHandle.write(contentsOf: suffix)
                try finalHandle.synchronize()
                try finalHandle.close()
            } catch {
                try? finalHandle.close()
                throw error
            }
            try FileManager.default.moveItem(at: staging, to: finalURL)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        try? handle.close()
        self.handle = nil
        finished = true
        try? FileManager.default.removeItem(at: partialURL)
        try? FileManager.default.removeItem(at: draftMetadataURL)
        return finalURL
    }

    /// Close without deleting data. A failed or interrupted save remains inspectable.
    public func preserveDraft() { try? handle?.synchronize(); try? handle?.close(); handle = nil }
    deinit { try? handle?.close() }

    public enum WriterError: LocalizedError {
        case alreadyExists, cannotCreateFile, closed, wrongRecording
        public var errorDescription: String? {
            switch self {
            case .alreadyExists: "A recording already exists with this identifier."
            case .cannotCreateFile: "The recording file could not be created. Check available storage."
            case .closed: "This recording is already closed."
            case .wrongRecording: "The recording metadata does not match its motion file."
            }
        }
    }
}

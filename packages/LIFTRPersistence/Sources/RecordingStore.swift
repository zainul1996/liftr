import Foundation
import LIFTRCore

public actor RecordingStore {
    public let directory: URL
    public init(directory: URL) throws { self.directory = directory; try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("LIFTR/Recordings", isDirectory: true)
    }
    public func save(_ recording: Recording) throws -> URL {
        let data = try RecordingJSON.encoder().encode(recording)
        let url = fileURL(id: recording.id)
        try data.write(to: url, options: .atomic)
        try writeSummary(recording.metadata)
        return url
    }
    /// Stream writer callers provide metadata to avoid loading raw samples on Watch.
    public func importFile(at source: URL, metadata: RecordingMetadata? = nil) throws -> URL {
        let resolved = try metadata ?? RecordingJSON.decoder().decode(Recording.self, from: Data(contentsOf: source)).metadata
        guard resolved.schemaVersion == 1 else { throw StoreError.unsupportedSchema }
        let destination = fileURL(id: resolved.id)
        if source.standardizedFileURL != destination.standardizedFileURL {
            let temporary = directory.appendingPathComponent(UUID().uuidString + ".incoming")
            try FileManager.default.copyItem(at: source, to: temporary)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: destination) }
        }
        try writeSummary(resolved)
        return destination
    }
    public func list() throws -> [RecordingMetadata] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".metadata.json") }
            .map { try RecordingJSON.decoder().decode(RecordingMetadata.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }
    public func load(id: UUID) throws -> Recording { try RecordingJSON.decoder().decode(Recording.self, from: Data(contentsOf: fileURL(id: id))) }
    public func fileURL(id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".liftr.json") }
    public func delete(id: UUID) throws {
        for url in [fileURL(id: id), summaryURL(id: id)] where FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func summaryURL(id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".metadata.json") }
    private func writeSummary(_ metadata: RecordingMetadata) throws { try RecordingJSON.encoder().encode(metadata).write(to: summaryURL(id: metadata.id), options: .atomic) }
    public enum StoreError: Error { case unsupportedSchema }
}

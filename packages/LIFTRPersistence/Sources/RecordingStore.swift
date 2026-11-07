import Foundation
import LIFTRCore

public actor RecordingStore {
    public let directory: URL
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("LIFTR/Recordings", isDirectory: true)
    }
    public func save(_ recording: Recording) throws -> URL {
        try validate(metadata: recording.metadata)
        let url = fileURL(id: recording.id)
        try RecordingJSON.encoder().encode(recording).write(to: url, options: .atomic)
        try writeSummary(recording.metadata)
        return url
    }
    /// Stream writer callers provide metadata to avoid loading raw samples on Watch.
    /// Duplicate transfers keep the existing canonical recording and its summary.
    public func importFile(at source: URL, metadata: RecordingMetadata? = nil) throws -> URL {
        let resolved = try metadata ?? RecordingJSON.decoder().decode(Recording.self, from: Data(contentsOf: source)).metadata
        try validate(metadata: resolved)
        let destination = fileURL(id: resolved.id)
        if source.standardizedFileURL == destination.standardizedFileURL {
            try writeSummary(resolved)
            return destination
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            if !FileManager.default.fileExists(atPath: summaryURL(id: resolved.id).path) {
                try writeSummary(load(id: resolved.id).metadata)
            }
            return destination
        }
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".incoming")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        try FileManager.default.moveItem(at: temporary, to: destination)
        try writeSummary(resolved)
        return destination
    }
    public func list() throws -> [RecordingMetadata] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        // Recover an index entry after an interruption between canonical write and summary write.
        for url in urls where url.lastPathComponent.hasSuffix(".liftr.json") {
            let idText = url.lastPathComponent.replacingOccurrences(of: ".liftr.json", with: "")
            if let id = UUID(uuidString: idText), !FileManager.default.fileExists(atPath: summaryURL(id: id).path) {
                try writeSummary(load(id: id).metadata)
            }
        }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".metadata.json") }
            .map { try RecordingJSON.decoder().decode(RecordingMetadata.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }
    public func load(id: UUID) throws -> Recording {
        let recording = try RecordingJSON.decoder().decode(Recording.self, from: Data(contentsOf: fileURL(id: id)))
        try validate(metadata: recording.metadata)
        guard recording.id == id else { throw StoreError.identityMismatch }
        return recording
    }
    public func fileURL(id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".liftr.json") }
    public func delete(id: UUID) throws {
        for url in [fileURL(id: id), summaryURL(id: id)] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    public func acknowledgeTransfer(id: UUID) throws {
        var ids = try acknowledgedIDs()
        ids.insert(id)
        try RecordingJSON.encoder().encode(ids).write(to: acknowledgementsURL, options: .atomic)
    }
    public func pendingTransfers() throws -> [RecordingMetadata] {
        let acknowledged = try acknowledgedIDs()
        return try list().filter { !acknowledged.contains($0.id) }
    }
    private var acknowledgementsURL: URL { directory.appendingPathComponent("transfer-acknowledgements.json") }
    private func acknowledgedIDs() throws -> Set<UUID> {
        guard FileManager.default.fileExists(atPath: acknowledgementsURL.path) else { return [] }
        return try RecordingJSON.decoder().decode(Set<UUID>.self, from: Data(contentsOf: acknowledgementsURL))
    }
    private func summaryURL(id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".metadata.json") }
    private func writeSummary(_ metadata: RecordingMetadata) throws {
        try RecordingJSON.encoder().encode(metadata).write(to: summaryURL(id: metadata.id), options: .atomic)
    }
    private func validate(metadata: RecordingMetadata) throws {
        guard metadata.schemaVersion == 1 else { throw StoreError.unsupportedSchema }
        guard !metadata.participantID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              metadata.sensorConfiguration.targetHz.isFinite, metadata.sensorConfiguration.targetHz > 0,
              metadata.weightKG.map({ $0.isFinite && $0 >= 0 }) ?? true,
              metadata.actualReps.map({ $0 >= 0 }) ?? true
        else { throw StoreError.invalidMetadata }
        if let end = metadata.endedAt, end < metadata.startedAt { throw StoreError.invalidMetadata }
    }
    public enum StoreError: Error { case unsupportedSchema, identityMismatch, invalidMetadata }
}

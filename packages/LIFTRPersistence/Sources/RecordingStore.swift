import Foundation
import LIFTRCore

public actor RecordingStore {
  public let directory: URL
  public private(set) var damagedRecordingCount = 0
  public init(directory: URL) throws {
    self.directory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  public static func defaultDirectory() throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
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
  public func importFile(
    at source: URL, metadata: RecordingMetadata? = nil, expectedID: UUID? = nil
  ) throws -> URL {
    let resolved =
      try metadata
      ?? RecordingJSON.decoder().decode(Recording.self, from: Data(contentsOf: source)).metadata
    if let expectedID, resolved.id != expectedID { throw StoreError.identityMismatch }
    try validate(metadata: resolved)
    let destination = fileURL(id: resolved.id)
    if source.standardizedFileURL == destination.standardizedFileURL {
      try writeSummary(resolved)
      return destination
    }
    if FileManager.default.fileExists(atPath: destination.path) {
      if !FileManager.default.fileExists(atPath: summaryURL(id: resolved.id).path) {
        try writeSummary(RecordingMetadataReader.read(from: destination))
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
  /// Restores a file atomically finalized by the Watch writer before a process interruption.
  /// Metadata extraction stays bounded even when raw samples contain a full workout.
  public func recoverFinalizedDraft(at source: URL) throws -> (
    fileURL: URL, metadata: RecordingMetadata
  ) {
    let metadata = try RecordingMetadataReader.read(from: source)
    let fileURL = try importFile(at: source, metadata: metadata)
    return (fileURL, metadata)
  }
  public func list() throws -> [RecordingMetadata] {
    let urls = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    damagedRecordingCount = 0
    var result: [RecordingMetadata] = []
    for url in urls where url.lastPathComponent.hasSuffix(".liftr.json") {
      let idText = url.lastPathComponent.replacingOccurrences(of: ".liftr.json", with: "")
      guard let id = UUID(uuidString: idText) else {
        damagedRecordingCount += 1
        continue
      }
      do {
        let summary = try? RecordingJSON.decoder().decode(
          RecordingMetadata.self, from: Data(contentsOf: summaryURL(id: id)))
        let metadata: RecordingMetadata
        if let summary, summary.id == id {
          metadata = summary
        } else {
          // Recovery reads raw JSON in fixed-size chunks, never a Watch-sized sample array.
          metadata = try RecordingMetadataReader.read(from: url)
          guard metadata.id == id else { throw StoreError.identityMismatch }
          try writeSummary(metadata)
        }
        try validate(metadata: metadata)
        result.append(metadata)
      } catch {
        // Preserve the damaged item for recovery without hiding healthy recordings.
        damagedRecordingCount += 1
      }
    }
    return result.sorted { $0.startedAt > $1.startedAt }
  }
  public func load(id: UUID) throws -> Recording {
    let recording = try RecordingJSON.decoder().decode(
      Recording.self, from: Data(contentsOf: fileURL(id: id)))
    try validate(metadata: recording.metadata)
    guard recording.id == id else { throw StoreError.identityMismatch }
    return recording
  }
  public func fileURL(id: UUID) -> URL {
    directory.appendingPathComponent(id.uuidString + ".liftr.json")
  }
  public func delete(id: UUID) throws {
    for url in [fileURL(id: id), summaryURL(id: id)]
    where FileManager.default.fileExists(atPath: url.path) {
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
  private var acknowledgementsURL: URL {
    directory.appendingPathComponent("transfer-acknowledgements.json")
  }
  private func acknowledgedIDs() throws -> Set<UUID> {
    guard FileManager.default.fileExists(atPath: acknowledgementsURL.path) else { return [] }
    return try RecordingJSON.decoder().decode(
      Set<UUID>.self, from: Data(contentsOf: acknowledgementsURL))
  }
  private func summaryURL(id: UUID) -> URL {
    directory.appendingPathComponent(id.uuidString + ".metadata.json")
  }
  private func writeSummary(_ metadata: RecordingMetadata) throws {
    try RecordingJSON.encoder().encode(metadata).write(
      to: summaryURL(id: metadata.id), options: .atomic)
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

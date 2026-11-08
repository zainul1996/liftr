import Foundation
import LIFTRCore

public actor RecordingStore {
  public let directory: URL
  private let index: SQLiteRecordingIndex
  private var persistenceWarnings: [String] = []
  public private(set) var damagedRecordingCount = 0
  public init(directory: URL) throws {
    self.directory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let indexURL = directory.appendingPathComponent("recording-index.sqlite")
    do {
      index = try SQLiteRecordingIndex(url: indexURL)
    } catch SQLiteRecordingIndex.IndexError.corruptDatabase {
      let recovery = directory.appendingPathComponent("Index-Recovery-" + UUID().uuidString)
      try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
      for suffix in ["", "-wal", "-shm", "-journal"] {
        let source = URL(fileURLWithPath: indexURL.path + suffix)
        if FileManager.default.fileExists(atPath: source.path) {
          try FileManager.default.copyItem(
            at: source, to: recovery.appendingPathComponent(source.lastPathComponent))
        }
      }
      // All recovery copies exist before the corrupt index is removed.
      for suffix in ["", "-wal", "-shm", "-journal"] {
        let source = URL(fileURLWithPath: indexURL.path + suffix)
        if FileManager.default.fileExists(atPath: source.path) {
          try FileManager.default.removeItem(at: source)
        }
      }
      index = try SQLiteRecordingIndex(url: indexURL)
      persistenceWarnings.append(
        "The damaged recording index was preserved for recovery. Raw recordings remain available. Review history and transfer acknowledgements may need recovery; retrying transfers can resend the same stable IDs."
      )
    }
    // Resolve interruptions between the raw-file rename and the SQLite commit.
    for staged in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    where staged.lastPathComponent.hasSuffix(".liftr-deleting")
      || staged.lastPathComponent.hasSuffix(".metadata-deleting")
    {
      let name = staged.deletingPathExtension().lastPathComponent
      guard let id = UUID(uuidString: name) else { continue }
      if try index.deletionCommitted(id: id) {
        do { try FileManager.default.removeItem(at: staged) } catch {
          persistenceWarnings.append(
            "A deleted recording has a retained local cleanup file. Retry deletion or recover local storage."
          )
        }
      } else {
        let suffix = staged.pathExtension == "liftr-deleting" ? ".liftr.json" : ".metadata.json"
        let destination = directory.appendingPathComponent(id.uuidString + suffix)
        if !FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.moveItem(at: staged, to: destination)
        }
      }
    }
    let acknowledgements = directory.appendingPathComponent("transfer-acknowledgements.json")
    if FileManager.default.fileExists(atPath: acknowledgements.path) {
      do {
        if try !index.hasMigration("acknowledgements-json-v1") {
          let ids = try RecordingJSON.decoder().decode(
            Set<UUID>.self, from: Data(contentsOf: acknowledgements))
          try index.migrateAcknowledgements(ids)
        }
        try FileManager.default.removeItem(at: acknowledgements)
      } catch {
        persistenceWarnings.append(
          "Legacy transfer acknowledgements remain on device because migration or cleanup could not finish."
        )
      }
    }
    let legacyReviews = directory.deletingLastPathComponent().appendingPathComponent("reviews.json")
    if FileManager.default.fileExists(atPath: legacyReviews.path) {
      do {
        if try !index.hasMigration("reviews-json-v1") {
          let reviews = try RecordingJSON.decoder().decode(
            [String: [RecordingReview]].self, from: Data(contentsOf: legacyReviews))
          try index.migrateReviews(reviews)
        }
        try FileManager.default.removeItem(at: legacyReviews)
      } catch {
        persistenceWarnings.append(
          "Legacy review history remains on device because migration or cleanup could not finish. New recording transfers remain available."
        )
      }
    }
  }
  public static func defaultDirectory() throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("--liftr-ui-testing"),
        ProcessInfo.processInfo.environment["LIFTR_UI_TESTING"] == "1"
      {
        return base.appendingPathComponent("LIFTR-UI-Tests/Recordings", isDirectory: true)
      }
    #endif
    return base.appendingPathComponent("LIFTR/Recordings", isDirectory: true)
  }
  public static func exportDirectory() -> URL {
    #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("--liftr-ui-testing"),
        ProcessInfo.processInfo.environment["LIFTR_UI_TESTING"] == "1"
      {
        return FileManager.default.temporaryDirectory.appendingPathComponent(
          "LIFTR-UI-Tests-Exports", isDirectory: true)
      }
    #endif
    return FileManager.default.temporaryDirectory.appendingPathComponent(
      "LIFTR-Exports", isDirectory: true)
  }
  public func save(_ recording: Recording) throws -> URL {
    try validate(metadata: recording.metadata)
    try finishCommittedStaging(id: recording.id)
    let url = fileURL(id: recording.id)
    try RecordingJSON.encoder().encode(recording).write(to: url, options: .atomic)
    try synchronize(url)
    try index.saveMetadata(recording.metadata)
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
    try finishCommittedStaging(id: resolved.id)
    let destination = fileURL(id: resolved.id)
    if source.standardizedFileURL == destination.standardizedFileURL {
      try index.saveMetadata(resolved)
      return destination
    }
    if FileManager.default.fileExists(atPath: destination.path) {
      if try index.metadata(id: resolved.id) == nil {
        try index.saveMetadata(RecordingMetadataReader.read(from: destination))
      }
      return destination
    }
    let temporary = directory.appendingPathComponent(UUID().uuidString + ".incoming")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.copyItem(at: source, to: temporary)
    try synchronize(temporary)
    try FileManager.default.moveItem(at: temporary, to: destination)
    try index.saveMetadata(resolved)
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
        let summary = try? index.metadata(id: id)
        let metadata: RecordingMetadata
        if let summary, summary.id == id {
          metadata = summary
        } else {
          // Recovery reads raw JSON in fixed-size chunks, never a Watch-sized sample array.
          metadata = try RecordingMetadataReader.read(from: url)
          guard metadata.id == id else { throw StoreError.identityMismatch }
          try index.saveMetadata(metadata)
        }
        try validate(metadata: metadata)
        result.append(metadata)
        let legacySummary = summaryURL(id: id)
        if FileManager.default.fileExists(atPath: legacySummary.path) {
          try? FileManager.default.removeItem(at: legacySummary)
        }
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
    let pairs = [
      (fileURL(id: id), directory.appendingPathComponent(id.uuidString + ".liftr-deleting")),
      (summaryURL(id: id), directory.appendingPathComponent(id.uuidString + ".metadata-deleting")),
    ]
    var moved: [(URL, URL)] = []
    do {
      try index.delete(id: id) {
        for (original, staged) in pairs where FileManager.default.fileExists(atPath: original.path)
        {
          try FileManager.default.moveItem(at: original, to: staged)
          moved.append((original, staged))
        }
      }
    } catch {
      for (original, staged) in moved.reversed() {
        if !FileManager.default.fileExists(atPath: original.path) {
          try? FileManager.default.moveItem(at: staged, to: original)
        }
      }
      throw error
    }
    for (_, staged) in pairs where FileManager.default.fileExists(atPath: staged.path) {
      do { try FileManager.default.removeItem(at: staged) } catch {
        persistenceWarnings.append(
          "Recording deleted. A local cleanup copy remains and will be retried when storage reopens."
        )
      }
    }
  }
  public func acknowledgeTransfer(id: UUID) throws { try index.acknowledge(id: id) }
  public func pendingTransfers() throws -> [RecordingMetadata] {
    let acknowledged = try index.acknowledgedIDs()
    return try list().filter { !acknowledged.contains($0.id) }
  }
  @discardableResult public func appendReview(recordingID: UUID, review: RecordingReview) throws
    -> [RecordingReview]
  {
    try validateReview(review)
    guard FileManager.default.fileExists(atPath: fileURL(id: recordingID).path) else {
      throw StoreError.missingRecording
    }
    return try index.appendReview(recordingID: recordingID, review: review)
  }
  private func validateReview(_ review: RecordingReview) throws {
    guard review.actualReps.map { $0 >= 0 } ?? true,
      review.weightKG.map { $0.isFinite && $0 >= 0 } ?? true,
      ExerciseLibrary.find(id: review.exerciseID) != nil
    else { throw StoreError.invalidMetadata }
  }
  public func loadReviews() throws -> [String: [RecordingReview]] { try index.reviews() }
  public func saveReviews(recordingID: UUID, reviews: [RecordingReview]) throws {
    guard
      reviews.allSatisfy({ review in
        (review.actualReps.map { $0 >= 0 } ?? true)
          && (review.weightKG.map { $0.isFinite && $0 >= 0 } ?? true)
          && ExerciseLibrary.find(id: review.exerciseID) != nil
      })
    else { throw StoreError.invalidMetadata }
    try index.replaceReviews(recordingID: recordingID, with: reviews)
  }
  public func takePersistenceWarnings() -> [String] {
    defer { persistenceWarnings = [] }
    return persistenceWarnings
  }
  public func hasUnresolvedLegacyReviews() -> Bool {
    FileManager.default.fileExists(
      atPath: directory.deletingLastPathComponent().appendingPathComponent("reviews.json").path)
  }
  private func finishCommittedStaging(id: UUID) throws {
    guard try index.deletionCommitted(id: id) else { return }
    for suffix in [".liftr-deleting", ".metadata-deleting"] {
      let staged = directory.appendingPathComponent(id.uuidString + suffix)
      if FileManager.default.fileExists(atPath: staged.path) {
        try FileManager.default.removeItem(at: staged)
      }
    }
  }
  private func synchronize(_ url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.synchronize()
  }
  private func summaryURL(id: UUID) -> URL {
    directory.appendingPathComponent(id.uuidString + ".metadata.json")
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
  public enum StoreError: Error {
    case unsupportedSchema, identityMismatch, invalidMetadata, missingRecording
  }
}

import Foundation
import LIFTRCore
import SQLite3
import XCTest

@testable import LIFTRPersistence

final class SQLitePersistenceTests: XCTestCase {
  private func metadata() -> RecordingMetadata {
    .init(
      participantID: "synthetic-sqlite-test", sessionID: UUID(), exerciseID: "machine_chest_press",
      equipment: "synthetic", actualReps: 2, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
      watchWrist: "left", watchModel: "synthetic", watchOSVersion: "synthetic")
  }
  private func review(id: UUID = UUID(), time: Double = 100, reps: Int = 12) -> RecordingReview {
    .init(
      id: id, reviewedAt: Date(timeIntervalSince1970: time), exerciseID: "dumbbell_bicep_curl",
      actualReps: reps, weightKG: 17.5)
  }
  func testLegacyMetadataReviewsAndAcknowledgementsMigrateTransactionallyAndReopen() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let directory = base.appendingPathComponent("Recordings")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let recording = Recording(metadata: metadata(), samples: [])
    let bytes = try RecordingJSON.encoder().encode(recording)
    let raw = directory.appendingPathComponent(recording.id.uuidString + ".liftr.json")
    try bytes.write(to: raw)
    let summary = directory.appendingPathComponent(recording.id.uuidString + ".metadata.json")
    try RecordingJSON.encoder().encode(recording.metadata).write(to: summary)
    let legacyReviews = base.appendingPathComponent("reviews.json")
    let expected = [recording.id.uuidString: [review()]]
    try RecordingJSON.encoder().encode(expected).write(to: legacyReviews)
    let legacyACK = directory.appendingPathComponent("transfer-acknowledgements.json")
    try RecordingJSON.encoder().encode(Set([recording.id])).write(to: legacyACK)
    let store = try RecordingStore(directory: directory)
    let listed = try await store.list()
    let migrated = try await store.loadReviews()
    let pending = try await store.pendingTransfers()
    XCTAssertEqual(listed.map(\.id), [recording.id])
    XCTAssertEqual(migrated, expected)
    XCTAssertTrue(pending.isEmpty)
    XCTAssertEqual(try Data(contentsOf: raw), bytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyReviews.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyACK.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: summary.path))
    let reopened = try RecordingStore(directory: directory)
    let persisted = try await reopened.loadReviews()
    let persistedPending = try await reopened.pendingTransfers()
    XCTAssertEqual(persisted, expected)
    XCTAssertTrue(persistedPending.isEmpty)
  }
  func testFailedLegacyReviewCommitRollsBackAndKeepsSourceForRetry() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let directory = base.appendingPathComponent("Recordings")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let id = UUID()
    let duplicate = review()
    let legacy = base.appendingPathComponent("reviews.json")
    let brokenBytes = try RecordingJSON.encoder().encode([id.uuidString: [duplicate, duplicate]])
    try brokenBytes.write(to: legacy)
    let failed = try RecordingStore(directory: directory)
    let rolledBack = try await failed.loadReviews()
    XCTAssertTrue(rolledBack.isEmpty)
    XCTAssertEqual(try Data(contentsOf: legacy), brokenBytes)
    let warnings = await failed.takePersistenceWarnings()
    XCTAssertFalse(warnings.isEmpty)
    try RecordingJSON.encoder().encode([id.uuidString: [duplicate]]).write(
      to: legacy, options: .atomic)
    let retry = try RecordingStore(directory: directory)
    let restored = try await retry.loadReviews()
    XCTAssertEqual(restored[id.uuidString], [duplicate])
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
  }
  func testReplacementConstraintFailurePreservesCommittedReviewHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let index = try SQLiteRecordingIndex(url: directory.appendingPathComponent("index.sqlite"))
    let id = UUID()
    let original = review(reps: 8)
    try index.replaceReviews(recordingID: id, with: [original])
    let duplicate = review(reps: 99)
    XCTAssertThrowsError(try index.replaceReviews(recordingID: id, with: [duplicate, duplicate]))
    XCTAssertEqual(try index.reviews()[id.uuidString], [original])
  }
  func testReviewSubmissionOrderSurvivesBackwardClockAndLowercaseLegacyIdentity() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let directory = base.appendingPathComponent("Recordings")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let id = UUID()
    let history = [review(time: 200, reps: 8), review(time: 100, reps: 12)]
    try RecordingJSON.encoder().encode([id.uuidString.lowercased(): history]).write(
      to: base.appendingPathComponent("reviews.json"))
    let store = try RecordingStore(directory: directory)
    let migrated = try await store.loadReviews()
    XCTAssertEqual(migrated[id.uuidString], history)
    XCTAssertEqual(migrated[id.uuidString]?.last?.actualReps, 12)
    let reopened = try RecordingStore(directory: directory)
    let persisted = try await reopened.loadReviews()
    XCTAssertEqual(persisted[id.uuidString], history)
  }
  func testFutureDatabaseSchemaIsRejectedWithoutChangingVersion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("future.sqlite")
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
    XCTAssertEqual(sqlite3_exec(database, "PRAGMA user_version=99", nil, nil, nil), SQLITE_OK)
    sqlite3_close(database)
    XCTAssertThrowsError(try SQLiteRecordingIndex(url: url))
    XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    XCTAssertEqual(
      sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil), SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
    XCTAssertEqual(sqlite3_column_int(statement, 0), 99)
  }
  func testDeletionRemovesStructuredReviewAndACKWithoutDeletingOtherRawFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let deleted = Recording(metadata: metadata(), samples: [])
    let kept = Recording(metadata: metadata(), samples: [])
    _ = try await store.save(deleted)
    let keptURL = try await store.save(kept)
    try await store.saveReviews(recordingID: deleted.id, reviews: [review()])
    try await store.acknowledgeTransfer(id: deleted.id)
    try await store.delete(id: deleted.id)
    let reviews = try await store.loadReviews()
    XCTAssertNil(reviews[deleted.id.uuidString])
    XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
    let index = try SQLiteRecordingIndex(
      url: directory.appendingPathComponent("recording-index.sqlite"))
    XCTAssertNil(try index.metadata(id: deleted.id))
    XCTAssertFalse(try index.acknowledgedIDs().contains(deleted.id))
  }
  func testCommittedMigrationMarkerPreventsDeletedReviewsBeingReplayed() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let directory = base.appendingPathComponent("Recordings")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let id = UUID()
    let legacy = base.appendingPathComponent("reviews.json")
    let bytes = try RecordingJSON.encoder().encode([id.uuidString: [review()]])
    try bytes.write(to: legacy)
    let store = try RecordingStore(directory: directory)
    try await store.saveReviews(recordingID: id, reviews: [])
    // Models a committed migration whose old file survived cleanup or was restored later.
    try bytes.write(to: legacy)
    let reopened = try RecordingStore(directory: directory)
    let history = try await reopened.loadReviews()
    XCTAssertNil(history[id.uuidString])
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
  }
  func testConcurrentReviewAppendsPreserveEverySubmissionAndRecording() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let a = Recording(metadata: metadata(), samples: [])
    let b = Recording(metadata: metadata(), samples: [])
    _ = try await store.save(a)
    _ = try await store.save(b)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for n in 0..<30 {
        let id = n.isMultiple(of: 2) ? a.id : b.id
        let value = review(time: Double(100 - n), reps: n)
        group.addTask { _ = try await store.appendReview(recordingID: id, review: value) }
      }
      try await group.waitForAll()
    }
    let history = try await store.loadReviews()
    XCTAssertEqual(history[a.id.uuidString]?.count, 15)
    XCTAssertEqual(history[b.id.uuidString]?.count, 15)
    XCTAssertEqual(
      Set(history.values.flatMap { $0.map(\.actualReps) }), Set((0..<30).map(Optional.some)))
    let reopened = try RecordingStore(directory: directory)
    let restored = try await reopened.loadReviews()
    XCTAssertEqual(restored, history)
  }
  func testBusyDatabaseDeletionKeepsRawAndReviewForRetry() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let recording = Recording(metadata: metadata(), samples: [])
    let raw = try await store.save(recording)
    let value = review()
    _ = try await store.appendReview(recordingID: recording.id, review: value)
    var lock: OpaquePointer?
    XCTAssertEqual(
      sqlite3_open(directory.appendingPathComponent("recording-index.sqlite").path, &lock),
      SQLITE_OK)
    defer { sqlite3_close(lock) }
    XCTAssertEqual(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
    do {
      try await store.delete(id: recording.id)
      XCTFail("Locked DB must prevent deletion")
    } catch {}
    XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
    let history = try await store.loadReviews()
    XCTAssertEqual(history[recording.id.uuidString], [value])
    XCTAssertEqual(sqlite3_exec(lock, "ROLLBACK", nil, nil, nil), SQLITE_OK)
    try await store.delete(id: recording.id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))
  }
  func testCorruptIndexIsPreservedAndRawRecordingsRemainAvailableWithWarning() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let recording = Recording(metadata: metadata(), samples: [])
    let rawBytes = try RecordingJSON.encoder().encode(recording)
    try rawBytes.write(
      to: directory.appendingPathComponent(recording.id.uuidString + ".liftr.json"))
    let corruptBytes = Data("synthetic corrupt sqlite".utf8)
    try corruptBytes.write(to: directory.appendingPathComponent("recording-index.sqlite"))
    let store = try RecordingStore(directory: directory)
    let listed = try await store.list()
    XCTAssertEqual(listed.map(\.id), [recording.id])
    let warnings = await store.takePersistenceWarnings()
    XCTAssertTrue(warnings.contains { $0.contains("preserved for recovery") })
    let backups = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("Index-Recovery-") }
    XCTAssertEqual(backups.count, 1)
    XCTAssertEqual(
      try Data(contentsOf: backups[0].appendingPathComponent("recording-index.sqlite")),
      corruptBytes)
    XCTAssertEqual(
      try Data(
        contentsOf: directory.appendingPathComponent(recording.id.uuidString + ".liftr.json")),
      rawBytes)
  }

  func testRawStagingFailureRollsBackReviewAndMetadataDeletion() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let recording = Recording(metadata: metadata(), samples: [])
    let raw = try await store.save(recording)
    let value = review()
    _ = try await store.appendReview(recordingID: recording.id, review: value)
    let collision = directory.appendingPathComponent(recording.id.uuidString + ".liftr-deleting")
    try Data("synthetic collision".utf8).write(to: collision)
    do {
      try await store.delete(id: recording.id)
      XCTFail("Staging collision must preserve recording")
    } catch {}
    XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
    let history = try await store.loadReviews()
    XCTAssertEqual(history[recording.id.uuidString], [value])
    try FileManager.default.removeItem(at: collision)
    try await store.delete(id: recording.id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))
  }
  func testInterruptedUncommittedDeletionRestoresRawAndReviewOnReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let recording = Recording(metadata: metadata(), samples: [])
    let raw = try await store.save(recording)
    let value = review()
    _ = try await store.appendReview(recordingID: recording.id, review: value)
    let staged = directory.appendingPathComponent(recording.id.uuidString + ".liftr-deleting")
    // A process can die after rename but before its SQLite transaction commits.
    try FileManager.default.moveItem(at: raw, to: staged)
    let reopened = try RecordingStore(directory: directory)
    XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    let history = try await reopened.loadReviews()
    XCTAssertEqual(history[recording.id.uuidString], [value])
  }
  func testCommittedDeletionFinishesStagedCleanupAndReimportClearsMarker() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let recording = Recording(metadata: metadata(), samples: [])
    let raw = try await store.save(recording)
    let index = try SQLiteRecordingIndex(
      url: directory.appendingPathComponent("recording-index.sqlite"))
    let staged = directory.appendingPathComponent(recording.id.uuidString + ".liftr-deleting")
    try index.delete(id: recording.id) { try FileManager.default.moveItem(at: raw, to: staged) }
    let reopened = try RecordingStore(directory: directory)
    XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    let listed = try await reopened.list()
    XCTAssertTrue(listed.isEmpty)
    // A previous cleanup may remain until this same UUID is reimported.
    try Data("retained synthetic deletion".utf8).write(to: staged)
    _ = try await reopened.save(recording)
    XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    XCTAssertFalse(try index.deletionCommitted(id: recording.id))
    try await reopened.delete(id: recording.id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))
  }

}

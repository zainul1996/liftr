import SQLite3
import XCTest

@testable import LIFTRCore
@testable import LIFTRPersistence

final class RecordingTests: XCTestCase {
  func testTaxonomyIsStableAndManualUntilValidated() {
    XCTAssertEqual(ExerciseLibrary.all.count, 9)
    XCTAssertEqual(Set(ExerciseLibrary.all.map(\.id)).count, 9)
    XCTAssertTrue(ExerciseLibrary.all.allSatisfy { $0.capability == .manual })
  }
  func testRoundTripAndIdempotentImport() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let metadata = RecordingMetadata(
      participantID: "synthetic-test", sessionID: UUID(), watchWrist: "left",
      watchModel: "test-fixture", watchOSVersion: "test")
    let recording = Recording(metadata: metadata, samples: [])
    let url = try await store.save(recording)
    _ = try await store.importFile(at: url)
    let listed = try await store.list()
    XCTAssertEqual(listed.count, 1)
    let loaded = try await store.load(id: recording.id)
    XCTAssertEqual(loaded.metadata.id, recording.id)
    try await store.delete(id: recording.id)
    let remaining = try await store.list()
    XCTAssertTrue(remaining.isEmpty)
  }

  private func fixture() -> Recording {
    Recording(
      metadata: .init(
        participantID: "synthetic-only", sessionID: UUID(),
        watchWrist: "left", watchModel: "synthetic", watchOSVersion: "synthetic"), samples: [])
  }
  func testAcknowledgedRecordingsStayOutOfRetryQueueAfterReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let recording = fixture()
    _ = try await store.save(recording)
    let before = try await store.pendingTransfers()
    XCTAssertEqual(before.count, 1)
    try await store.acknowledgeTransfer(id: recording.id)
    let reopened = try RecordingStore(directory: directory)
    let after = try await reopened.pendingTransfers()
    XCTAssertTrue(after.isEmpty)
  }
  func testDuplicateImportKeepsCanonicalRecordingAndSummary() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let incoming = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: incoming)
    }
    let store = try RecordingStore(directory: directory)
    let recording = fixture()
    _ = try await store.save(recording)
    var duplicate = recording
    duplicate.metadata.participantID = "changed-duplicate"
    try RecordingJSON.encoder().encode(duplicate).write(to: incoming)
    _ = try await store.importFile(at: incoming)
    let loaded = try await store.load(id: recording.id)
    let listed = try await store.list()
    XCTAssertEqual(loaded.metadata.participantID, "synthetic-only")
    XCTAssertEqual(listed.first?.participantID, "synthetic-only")
  }
  func testListRecoversMissingSummaryAfterInterruptedWrite() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let recording = fixture()
    let raw = await store.fileURL(id: recording.id)
    try RecordingJSON.encoder().encode(recording).write(to: raw)
    let recovered = try await store.list()
    XCTAssertEqual(recovered.map(\.id), [recording.id])
  }
  func testFutureSchemaAndNegativeLabelsAreRejected() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    for change in [0, 1] {
      var recording = fixture()
      if change == 0 {
        recording.metadata.schemaVersion = 2
      } else {
        recording.metadata.actualReps = -1
      }
      do {
        _ = try await store.save(recording)
        XCTFail("Invalid recording was saved")
      } catch {  // Expected validation failure.
      }
    }
    let saved = try await store.list()
    XCTAssertTrue(saved.isEmpty)
  }

  func testIdentityMismatchRejectsBeforeWritingAnyCanonicalFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let incoming = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: incoming)
    }
    let store = try RecordingStore(directory: directory)
    let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    let recording = fixture()
    try RecordingJSON.encoder().encode(recording).write(to: incoming)
    do {
      _ = try await store.importFile(at: incoming, expectedID: UUID())
      XCTFail("Mismatched transfer must be rejected")
    } catch RecordingStore.StoreError.identityMismatch {  // Expected before mutation.
    }
    let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertTrue(
      entries.filter { $0.hasSuffix(".liftr.json") || $0.hasSuffix(".metadata.json") }.isEmpty)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before)
    var database: OpaquePointer?
    XCTAssertEqual(
      sqlite3_open(directory.appendingPathComponent("recording-index.sqlite").path, &database),
      SQLITE_OK)
    defer { sqlite3_close(database) }
    for table in ["recording_metadata", "transfer_acknowledgements", "recording_reviews"] {
      var statement: OpaquePointer?
      XCTAssertEqual(
        sqlite3_prepare_v2(database, "SELECT count(*) FROM \(table)", -1, &statement, nil),
        SQLITE_OK)
      XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
      XCTAssertEqual(sqlite3_column_int(statement, 0), 0)
      sqlite3_finalize(statement)
    }
    let rejectedImports = try await store.list()
    XCTAssertTrue(rejectedImports.isEmpty)
  }
  func testMetadataRecoveryStreamsPastLargeSampleArray() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let metadata = fixture().metadata
    // More than one disk buffer, with escaped JSON text inside an earlier annotation.
    let largePrefix =
      "{\"samples\":[" + String(repeating: "{\"timestamp\":1},", count: 10_000)
      + "{}],\"metadata\":"
    var data = Data(largePrefix.utf8)
    data.append(try RecordingJSON.encoder().encode(metadata))
    data.append(Data(",\"annotations\":[]}".utf8))
    try data.write(to: url)
    let recovered = try RecordingMetadataReader.read(from: url)
    XCTAssertEqual(recovered.id, metadata.id)
  }

  func testOneDamagedSummaryIsRebuiltWithoutHidingHealthyRecordings() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let healthy = fixture()
    let damagedSummary = fixture()
    _ = try await store.save(healthy)
    _ = try await store.save(damagedSummary)
    try Data("broken summary".utf8).write(
      to: directory.appendingPathComponent(damagedSummary.id.uuidString + ".metadata.json"))
    let recordings = try await store.list()
    XCTAssertEqual(Set(recordings.map(\.id)), Set([healthy.id, damagedSummary.id]))
    let damagedCount = await store.damagedRecordingCount
    XCTAssertEqual(damagedCount, 0)
  }
  func testUnrecoverableFileIsReportedAndHealthyRecordingStaysVisible() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let healthy = fixture()
    _ = try await store.save(healthy)
    try Data("corrupt raw file".utf8).write(
      to: directory.appendingPathComponent(UUID().uuidString + ".liftr.json"))
    let recordings = try await store.list()
    XCTAssertEqual(recordings.map(\.id), [healthy.id])
    let damagedCount = await store.damagedRecordingCount
    XCTAssertEqual(damagedCount, 1)
  }
  func testMalformedIncomingSampleBodyIsRejectedBeforeCopyOrAcknowledgement() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let incoming = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: incoming)
    }
    let store = try RecordingStore(directory: directory)
    let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    let metadata = fixture().metadata
    var malformed = Data("{\"metadata\":".utf8)
    malformed.append(try RecordingJSON.encoder().encode(metadata))
    malformed.append(Data(",\"samples\":[BROKEN],\"annotations\":[]}".utf8))
    try malformed.write(to: incoming)
    do {
      _ = try await store.importFile(at: incoming, expectedID: metadata.id)
      XCTFail("Malformed raw JSON imported")
    } catch {  // No canonical copy can be acknowledged.
    }
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertTrue(
      files.filter { $0.hasSuffix(".liftr.json") || $0.hasSuffix(".metadata.json") }.isEmpty)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before)
    var database: OpaquePointer?
    XCTAssertEqual(
      sqlite3_open(directory.appendingPathComponent("recording-index.sqlite").path, &database),
      SQLITE_OK)
    defer { sqlite3_close(database) }
    for table in ["recording_metadata", "transfer_acknowledgements", "recording_reviews"] {
      var statement: OpaquePointer?
      XCTAssertEqual(
        sqlite3_prepare_v2(database, "SELECT count(*) FROM \(table)", -1, &statement, nil),
        SQLITE_OK)
      XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
      XCTAssertEqual(sqlite3_column_int(statement, 0), 0)
      sqlite3_finalize(statement)
    }
    let rejectedImports = try await store.pendingTransfers()
    XCTAssertTrue(rejectedImports.isEmpty)
  }

  func testDeletingOneRecordingPreservesOtherSavedMotionAndRetryQueue() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RecordingStore(directory: directory)
    let deleted = fixture()
    let kept = fixture()
    let deletedURL = try await store.save(deleted)
    let keptURL = try await store.save(kept)
    try await store.delete(id: deleted.id)
    let remaining = try await store.list()
    let pending = try await store.pendingTransfers()
    XCTAssertEqual(remaining.map(\.id), [kept.id])
    XCTAssertEqual(pending.map(\.id), [kept.id])
    XCTAssertFalse(FileManager.default.fileExists(atPath: deletedURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
  }

  func testFinalizedDraftWithoutSidecarRecoversAfterCrashBeforeImport() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let drafts = base.appendingPathComponent("Drafts")
    try FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: true)
    let store = try RecordingStore(directory: base.appendingPathComponent("Recordings"))
    var recording = fixture()
    recording.metadata.startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    recording.metadata.actualReps = 12
    let orphan = drafts.appendingPathComponent(recording.id.uuidString + ".liftr.json")
    try RecordingJSON.encoder().encode(recording).write(to: orphan)
    let recovered = try await store.recoverFinalizedDraft(at: orphan)
    _ = try await store.recoverFinalizedDraft(at: orphan)
    let saved = try await store.list()
    let loaded = try await store.load(id: recording.id)
    XCTAssertEqual(saved.count, 1)
    XCTAssertEqual(recovered.metadata.actualReps, 12)
    XCTAssertEqual(loaded.metadata, recording.metadata)
    XCTAssertTrue(FileManager.default.fileExists(atPath: recovered.fileURL.path))
  }
}

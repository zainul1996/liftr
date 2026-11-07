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
        let metadata = RecordingMetadata(participantID: "synthetic-test", sessionID: UUID(), watchWrist: "left", watchModel: "test-fixture", watchOSVersion: "test")
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
        Recording(metadata: .init(participantID: "synthetic-only", sessionID: UUID(),
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
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: incoming) }
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
            if change == 0 { recording.metadata.schemaVersion = 2 }
            else { recording.metadata.actualReps = -1 }
            do { _ = try await store.save(recording); XCTFail("Invalid recording was saved") }
            catch { /* expected */ }
        }
        let saved = try await store.list()
        XCTAssertTrue(saved.isEmpty)
    }

    func testIdentityMismatchRejectsBeforeWritingAnyCanonicalFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let incoming = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: incoming) }
        let store = try RecordingStore(directory: directory)
        let recording = fixture()
        try RecordingJSON.encoder().encode(recording).write(to: incoming)
        do {
            _ = try await store.importFile(at: incoming, expectedID: UUID())
            XCTFail("Mismatched transfer must be rejected")
        } catch RecordingStore.StoreError.identityMismatch { /* expected before mutation */ }
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(entries.isEmpty)
    }
    func testMetadataRecoveryStreamsPastLargeSampleArray() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = fixture().metadata
        // More than one disk buffer, with escaped JSON text inside an earlier annotation.
        let largePrefix = "{\"samples\":[" + String(repeating: "{\"timestamp\":1},", count: 10_000) + "{}],\"metadata\":"
        var data = Data(largePrefix.utf8)
        data.append(try RecordingJSON.encoder().encode(metadata))
        data.append(Data(",\"annotations\":[]}".utf8))
        try data.write(to: url)
        let recovered = try RecordingMetadataReader.read(from: url)
        XCTAssertEqual(recovered.id, metadata.id)
    }
}

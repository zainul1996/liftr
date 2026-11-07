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
}

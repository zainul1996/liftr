import Combine
import Foundation
import LIFTRCore
import LIFTRPersistence
import LIFTRSync

struct RecordingReview: Codable, Identifiable, Sendable {
  var id = UUID()
  var reviewedAt = Date()
  var exerciseID: String
  var actualReps: Int?
  var weightKG: Double?
}

private struct ReviewedRecordingExport: Encodable {
  var metadata: RecordingMetadata
  var samples: [MotionSample]
  var annotations: [SetAnnotation]
  var originalMetadata: RecordingMetadata
  var originalAnnotations: [SetAnnotation]
  var correctionHistory: [RecordingReview]
}

@MainActor
final class PhoneLibrary: ObservableObject {
  @Published private(set) var recordings: [RecordingMetadata] = []
  @Published private(set) var reviews: [String: [RecordingReview]] = [:]
  @Published private(set) var syncStatus = "Starting connection"
  @Published private(set) var isLoading = false
  @Published private(set) var damagedRecordingCount = 0
  @Published var errorMessage: String?

  private var store: RecordingStore?
  private var transfer: RecordingTransfer?
  private var statusSubscription: AnyCancellable?
  private var reviewsURL: URL?

  init() {
    do {
      let directory = try RecordingStore.defaultDirectory()
      let store = try RecordingStore(directory: directory)
      self.store = store
      let reviewsURL = directory.deletingLastPathComponent().appendingPathComponent("reviews.json")
      self.reviewsURL = reviewsURL
      if FileManager.default.fileExists(atPath: reviewsURL.path) {
        do {
          reviews = try RecordingJSON.decoder().decode(
            [String: [RecordingReview]].self, from: Data(contentsOf: reviewsURL))
        } catch {
          // A damaged optional review file must never disable incoming recordings.
          let recovery = reviewsURL.deletingLastPathComponent().appendingPathComponent(
            "reviews-recovery-\(UUID().uuidString).json")
          do {
            try FileManager.default.copyItem(at: reviewsURL, to: recovery)
            errorMessage =
              "Review history could not be read. A recovery copy was preserved. Recording transfers remain available."
          } catch {
            self.reviewsURL = nil
            errorMessage =
              "Review history could not be read or backed up. Review edits are disabled to preserve it. Recording transfers remain available."
          }
        }
      }
      let transfer = RecordingTransfer(store: store)
      self.transfer = transfer
      statusSubscription = transfer.$status.sink { [weak self] status in self?.syncStatus = status }
      transfer.onReceive = { [weak self] in Task { await self?.refresh() } }
      transfer.activate()
    } catch {
      errorMessage = "Could not open local recordings: \(error.localizedDescription)"
    }
  }

  func refresh() async {
    guard let store else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      recordings = try await store.list()
      damagedRecordingCount = await store.damagedRecordingCount
    } catch { errorMessage = "Could not load recordings: \(error.localizedDescription)" }
  }

  func load(_ id: UUID) async throws -> Recording {
    guard let store else { throw LibraryError.unavailable }
    return try await store.load(id: id)
  }

  func latestReview(for id: UUID) -> RecordingReview? { reviews[id.uuidString]?.last }
  func reviewCount(for id: UUID) -> Int { reviews[id.uuidString]?.count ?? 0 }

  func displayedMetadata(_ original: RecordingMetadata) -> RecordingMetadata {
    guard let review = latestReview(for: original.id) else { return original }
    return applying(review, to: original)
  }

  private func applying(_ review: RecordingReview, to original: RecordingMetadata)
    -> RecordingMetadata
  {
    var metadata = original
    metadata.exerciseID = review.exerciseID
    metadata.equipment =
      review.exerciseID == original.exerciseID
      ? original.equipment
      : ExerciseLibrary.find(id: review.exerciseID)?.equipment ?? original.equipment
    metadata.actualReps = review.actualReps
    metadata.weightKG = review.weightKG
    metadata.labelReviewStatus = .corrected
    return metadata
  }

  func saveReview(for id: UUID, exerciseID: String, reps: Int?, weightKG: Double?) throws {
    guard ExerciseLibrary.find(id: exerciseID) != nil,
      reps.map({ $0 >= 0 }) ?? true,
      weightKG.map({ $0.isFinite && $0 >= 0 }) ?? true,
      let reviewsURL
    else { throw LibraryError.invalidReview }
    var next = reviews
    next[id.uuidString, default: []].append(
      .init(exerciseID: exerciseID, actualReps: reps, weightKG: weightKG))
    try RecordingJSON.encoder().encode(next).write(to: reviewsURL, options: .atomic)
    reviews = next
  }

  func deleteFromPhone(_ id: UUID) async {
    guard let store else { return }
    do {
      try await store.delete(id: id)
      var next = reviews
      next.removeValue(forKey: id.uuidString)
      if let reviewsURL {
        try RecordingJSON.encoder().encode(next).write(to: reviewsURL, options: .atomic)
      }
      reviews = next
      await refresh()
    } catch { errorMessage = "Could not delete recording: \(error.localizedDescription)" }
  }

  /// Share original files directly. Only reviewed sets require a separate export copy.
  func exportURLs(for ids: [UUID]) async throws -> [URL] {
    guard let store else { throw LibraryError.unavailable }
    let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "LIFTR-Exports", isDirectory: true)
    try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
    var urls: [URL] = []
    for id in ids {
      guard let history = reviews[id.uuidString], !history.isEmpty else {
        urls.append(await store.fileURL(id: id))
        continue
      }
      let original = try await store.load(id: id)
      var annotations = original.annotations
      if original.metadata.mode == .set && annotations.count == 1 {
        annotations[0].exerciseID = history.last!.exerciseID
        annotations[0].actualReps = history.last!.actualReps
        annotations[0].weightKG = history.last!.weightKG
      }
      let reviewed = ReviewedRecordingExport(
        metadata: applying(history.last!, to: original.metadata), samples: original.samples,
        annotations: annotations, originalMetadata: original.metadata,
        originalAnnotations: original.annotations, correctionHistory: history)
      let url = exportDirectory.appendingPathComponent(id.uuidString + ".liftr.json")
      try RecordingJSON.encoder().encode(reviewed).write(to: url, options: .atomic)
      urls.append(url)
    }
    return urls
  }

  enum LibraryError: LocalizedError {
    case unavailable, invalidReview
    var errorDescription: String? {
      switch self {
      case .unavailable: "The recording store is unavailable."
      case .invalidReview: "Choose an exercise and enter nonnegative reps and weight."
      }
    }
  }
}

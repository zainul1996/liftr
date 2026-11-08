import Combine
import Darwin
import Foundation
import LIFTRCore
import LIFTRMotion
import LIFTRPersistence
import LIFTRSync
import WatchKit

@MainActor
final class RecordingController: ObservableObject {
  enum Phase: Hashable { case ready, preparing, recording, review, saving, rest }
  @Published private(set) var phase: Phase = .ready
  @Published var selectedExercise = ExerciseLibrary.all[0]
  @Published var actualReps = 0
  @Published var weightKG = 0.0
  @Published var equipmentVariant = ""
  @Published var continuousMode = false
  @Published private(set) var isContinuousRecording = false
  @Published private(set) var continuousCaptureStopped = false
  @Published private(set) var annotatedSetCount = 0
  @Published private(set) var labelsLockedForSaveRetry = false
  @Published var errorMessage: String?
  @Published private(set) var quality = MotionQuality()
  @Published private(set) var recordingStartedAt: Date?
  @Published private(set) var restStartedAt: Date?
  @Published private(set) var savedCount = 0
  @Published private(set) var recentRecordings: [RecordingMetadata] = []
  @Published private(set) var pendingDraftCount = 0
  let workout = WorkoutSessionController()
  let store: RecordingStore
  let transfer: RecordingTransfer
  private let recorder = DeviceMotionRecorder()
  private var metadata: RecordingMetadata?
  private var sessionID = UUID()
  private var pendingFinishedFile: URL?
  private var setStartTimestamp: TimeInterval?
  private var setEndTimestamp: TimeInterval?
  private var activeSetExercise: ExerciseDefinition?
  private var annotations: [SetAnnotation] = []
  private let draftDirectory: URL

  init() throws {
    let directory = try RecordingStore.defaultDirectory()
    #if DEBUG && targetEnvironment(simulator)
      try SimulatorTestSupport.prepare(directory: directory)
    #endif
    store = try RecordingStore(directory: directory)
    transfer = RecordingTransfer(store: store)
    draftDirectory = directory.deletingLastPathComponent().appendingPathComponent(
      "Drafts", isDirectory: true)
    recorder.onUpdate = { [weak self] recordingID, quality in
      Task { @MainActor in
        guard let self, self.metadata?.id == recordingID,
          self.phase == .recording || (self.phase == .rest && self.isContinuousRecording),
          quality.sampleCount >= self.quality.sampleCount
        else { return }
        self.quality = quality
      }
    }
    recorder.onFailure = { [weak self] recordingID, message in
      Task { @MainActor in
        guard self?.metadata?.id == recordingID else { return }
        self?.interrupt(message)
      }
    }
    workout.onInterruption = { [weak self] message in self?.interrupt(message) }
    transfer.activate()
    Task { await refreshRecordings() }
  }

  func startSet() async {
    guard phase == .ready || phase == .rest else { return }
    phase = .preparing
    errorMessage = nil
    let workoutWasActive = workout.isActive
    do {
      if isContinuousRecording {
        guard !continuousCaptureStopped else {
          phase = .rest
          errorMessage =
            "Capture has stopped. End Workout to save this session before starting another set."
          return
        }
        activeSetExercise = selectedExercise
        setStartTimestamp = ProcessInfo.processInfo.systemUptime
        actualReps = 0
        recordingStartedAt = Date()
        phase = .recording
        return
      }
      if !workout.isActive {
        sessionID = UUID()
        try await workout.start()
      }
      if workout.isPaused { workout.resume() }
      let device = WKInterfaceDevice.current()
      var participantID = Self.participantID()
      #if DEBUG && targetEnvironment(simulator)
        if SimulatorTestSupport.enabled { participantID = "synthetic-ui-test-never-train" }
      #endif
      var machine = utsname()
      uname(&machine)
      var hardware = withUnsafeBytes(of: &machine.machine) {
        String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
      }
      var recordedOSVersion = device.systemVersion
      var recordedWrist = device.wristLocation == .left ? "left" : "right"
      #if DEBUG && targetEnvironment(simulator)
        if SimulatorTestSupport.enabled {
          hardware = "synthetic-ui-test"
          recordedOSVersion = "synthetic-ui-test"
          recordedWrist = "synthetic"
        }
      #endif
      let metadata = RecordingMetadata(
        participantID: participantID, sessionID: sessionID,
        exerciseID: continuousMode ? nil : selectedExercise.id,
        equipment: continuousMode
          ? nil
          : (equipmentVariant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? selectedExercise.equipment
            : equipmentVariant.trimmingCharacters(in: .whitespacesAndNewlines)),
        weightKG: continuousMode ? nil : weightKG, startedAt: Date(),
        watchWrist: recordedWrist,
        watchModel: hardware, watchOSVersion: recordedOSVersion,
        mode: continuousMode ? .continuous : .set)
      try recorder.start(directory: draftDirectory, metadata: metadata)
      self.metadata = metadata
      pendingFinishedFile = nil
      labelsLockedForSaveRetry = false
      actualReps = 0
      quality = .init()
      recordingStartedAt = metadata.startedAt
      annotations = []
      annotatedSetCount = 0
      continuousCaptureStopped = false
      isContinuousRecording = continuousMode
      if continuousMode {
        restStartedAt = Date()
        phase = .rest
      } else {
        activeSetExercise = selectedExercise
        phase = .recording
      }
    } catch {
      if !workoutWasActive && workout.isActive { try? await workout.finish() }
      phase = .ready
      errorMessage = error.localizedDescription
    }
  }

  func endSet() {
    guard phase == .recording else { return }
    quality = isContinuousRecording ? recorder.snapshot() : recorder.stop()
    setEndTimestamp = quality.lastTimestamp
    if !isContinuousRecording { metadata?.endedAt = Date() }
    phase = .review
    if quality.sampleCount < 2 {
      errorMessage =
        "At least two sensor samples are needed. Keep this recording unfinished and try a longer set."
    }
  }

  func saveSet() async {
    guard phase == .review, var metadata, quality.sampleCount > 1,
      actualReps > 0, weightKG.isFinite, weightKG >= 0
    else { return }
    phase = .saving
    errorMessage = nil
    if isContinuousRecording {
      guard let rawFirst = quality.firstTimestamp, let end = setEndTimestamp,
        let requestedStart = setStartTimestamp, end > requestedStart
      else {
        phase = .review
        errorMessage = "No motion samples fall inside this set. Keep it unfinished and try again."
        return
      }
      let annotation = SetAnnotation(
        exerciseID: activeSetExercise?.id ?? selectedExercise.id,
        startTimestamp: max(rawFirst, requestedStart), endTimestamp: end,
        actualReps: actualReps, weightKG: weightKG)
      do {
        let next = annotations + [annotation]
        try recorder.checkpoint(annotations: next)
        annotations = next
        annotatedSetCount = next.count
        savedCount += 1
        restStartedAt = Date()
        phase = .rest
      } catch {
        phase = .review
        errorMessage =
          "Set label could not be saved. Motion data remains on Watch. \(error.localizedDescription)"
      }
      return
    }
    if pendingFinishedFile == nil {
      metadata.actualReps = actualReps
      metadata.weightKG = weightKG
      metadata.labelReviewStatus = .reviewed
      metadata.endedAt = metadata.endedAt ?? Date()
    }
    do {
      let annotation = SetAnnotation(
        exerciseID: metadata.exerciseID ?? selectedExercise.id,
        startTimestamp: quality.firstTimestamp!, endTimestamp: quality.lastTimestamp!,
        actualReps: actualReps, weightKG: weightKG)
      let source: URL
      if let pendingFinishedFile {
        source = pendingFinishedFile
      } else {
        source = try recorder.finish(metadata: metadata, annotations: [annotation])
        pendingFinishedFile = source
        labelsLockedForSaveRetry = true
      }
      let destination = try await store.importFile(at: source, metadata: metadata)
      transfer.enqueue(fileURL: destination, recordingID: metadata.id)
      if source != destination { try? FileManager.default.removeItem(at: source) }
      savedCount += 1
      self.metadata = nil
      pendingFinishedFile = nil
      labelsLockedForSaveRetry = false
      restStartedAt = Date()
      phase = .rest
      await refreshRecordings()
    } catch {
      self.metadata = metadata
      phase = .review
      errorMessage = "Save failed. Your local recording is retained. \(error.localizedDescription)"
    }
  }

  func keepInterruptedDraft() {
    guard pendingFinishedFile == nil else {
      errorMessage =
        "This set is finalized. Retry Save Set before leaving. You can correct its labels on iPhone afterwards."
      return
    }
    if isContinuousRecording {
      // Leave this interval unlabelled. Continuous raw recording keeps rest and transitions.
      setStartTimestamp = nil
      setEndTimestamp = nil
      restStartedAt = Date()
      phase = .rest
      return
    }
    recorder.preserveDraft()
    metadata = nil
    pendingFinishedFile = nil
    phase = .rest
    restStartedAt = Date()
    Task { await refreshRecordings() }
  }

  func finishWorkout() async {
    guard phase == .ready || phase == .rest else { return }
    phase = .preparing
    do {
      if isContinuousRecording, var metadata {
        if pendingFinishedFile == nil {
          quality = recorder.stop()
          metadata.endedAt = metadata.endedAt ?? Date()
          self.metadata = metadata
        }
        continuousCaptureStopped = true
        if pendingFinishedFile != nil || quality.sampleCount > 1 {
          let source: URL
          if let pendingFinishedFile {
            source = pendingFinishedFile
          } else {
            source = try recorder.finish(metadata: metadata, annotations: annotations)
            pendingFinishedFile = source
            self.metadata = metadata
          }
          let destination = try await store.importFile(at: source, metadata: metadata)
          transfer.enqueue(fileURL: destination, recordingID: metadata.id)
          if source != destination { try? FileManager.default.removeItem(at: source) }
        } else {
          recorder.preserveDraft()
        }
        self.metadata = nil
        pendingFinishedFile = nil
        isContinuousRecording = false
        annotations = []
      }
      try await workout.finish()
      phase = .ready
      await refreshRecordings()
    } catch {
      phase = isContinuousRecording ? .rest : .ready
      errorMessage =
        isContinuousRecording
        ? "Session save failed. Raw capture has stopped and is retained. Retry End Workout. \(error.localizedDescription)"
        : "Motion recordings are saved. Health workout save failed: \(error.localizedDescription)"
    }
  }

  func deleteSavedRecording(id: UUID) async {
    guard metadata?.id != id, recentRecordings.contains(where: { $0.id == id }) else {
      errorMessage = "An active recording or unfinished draft cannot be deleted here."
      return
    }
    transfer.cancelPending(recordingID: id)
    do {
      try await store.delete(id: id)
      await refreshRecordings()
    } catch {
      errorMessage = "The Watch copy could not be deleted: \(error.localizedDescription)"
    }
  }

  func retryTransfers() async { await transfer.retryPending() }

  func recoverDrafts() async {
    guard phase == .ready || phase == .rest, !isContinuousRecording, metadata == nil else { return }
    phase = .preparing
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: draftDirectory, includingPropertiesForKeys: nil)) ?? []
    var recoveredCount = 0
    var failures = 0
    for completed in files where completed.lastPathComponent.hasSuffix(".liftr.json") {
      do {
        let recovered = try await store.recoverFinalizedDraft(at: completed)
        transfer.enqueue(fileURL: recovered.fileURL, recordingID: recovered.metadata.id)
        if completed != recovered.fileURL { try FileManager.default.removeItem(at: completed) }
        recoveredCount += 1
      } catch { failures += 1 }
    }
    for metadataURL in files where metadataURL.lastPathComponent.hasSuffix(".draft.json") {
      let output = draftDirectory.appendingPathComponent(
        "Recovery-" + UUID().uuidString, isDirectory: true)
      do {
        let recovered = try await Task.detached(priority: .utility) {
          try DraftRecovery.recover(metadataURL: metadataURL, outputDirectory: output)
        }.value
        let destination = try await store.importFile(
          at: recovered.fileURL, metadata: recovered.metadata)
        transfer.enqueue(fileURL: destination, recordingID: recovered.metadata.id)
        let partial = metadataURL.deletingPathExtension().deletingPathExtension()
          .appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        try? FileManager.default.removeItem(at: metadataURL)
        try? FileManager.default.removeItem(
          at: metadataURL.deletingPathExtension().deletingPathExtension().appendingPathExtension(
            "annotations.json"))
        try? FileManager.default.removeItem(at: output)
        recoveredCount += 1
      } catch {
        try? FileManager.default.removeItem(at: output)
        failures += 1
      }
    }
    phase = .rest
    restStartedAt = restStartedAt ?? Date()
    await refreshRecordings()
    errorMessage =
      "Recovered \(recoveredCount) saved or interrupted recording(s). \(failures > 0 ? "\(failures) draft(s) could not be recovered and remain on Watch." : "Review labels on iPhone.")"
  }

  func refreshRecordings() async {
    let warnings = await store.takePersistenceWarnings()
    if !warnings.isEmpty { errorMessage = warnings.joined(separator: " ") }
    do { recentRecordings = try await store.list() } catch {
      errorMessage = "Recording list could not be loaded: \(error.localizedDescription)"
    }
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: draftDirectory, includingPropertiesForKeys: nil)) ?? []
    pendingDraftCount =
      files.filter {
        $0.pathExtension == "partial" || $0.lastPathComponent.hasSuffix(".liftr.json")
      }.count
  }

  private func interrupt(_ message: String) {
    if phase == .recording || isContinuousRecording {
      quality = recorder.stop()
      metadata?.endedAt = Date()
      metadata?.status = .interrupted
      continuousCaptureStopped = isContinuousRecording
      if phase == .recording { phase = .review }
    }
    errorMessage = message
  }

  private static func participantID() -> String {
    let key = "liftr.participantID"
    if let existing = UserDefaults.standard.string(forKey: key) { return existing }
    let id = UUID().uuidString
    UserDefaults.standard.set(id, forKey: key)
    return id
  }
}

import Foundation
import Combine
import WatchKit
import Darwin
import LIFTRCore
import LIFTRMotion
import LIFTRPersistence
import LIFTRSync

@MainActor
final class RecordingController: ObservableObject {
    enum Phase { case ready, preparing, recording, review, saving, rest }
    @Published private(set) var phase: Phase = .ready
    @Published var selectedExercise = ExerciseLibrary.all[0]
    @Published var actualReps = 0
    @Published var weightKG = 0.0
    @Published var equipmentVariant = ""
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
    private let draftDirectory: URL

    init() throws {
        let directory = try RecordingStore.defaultDirectory()
        store = try RecordingStore(directory: directory)
        transfer = RecordingTransfer(store: store)
        draftDirectory = directory.deletingLastPathComponent().appendingPathComponent("Drafts", isDirectory: true)
        recorder.onUpdate = { [weak self] quality in Task { @MainActor in self?.quality = quality } }
        recorder.onFailure = { [weak self] message in Task { @MainActor in self?.interrupt(message) } }
        workout.onInterruption = { [weak self] message in self?.interrupt(message) }
        transfer.activate()
        Task { await refreshRecordings() }
    }

    func startSet() async {
        guard phase == .ready || phase == .rest else { return }
        phase = .preparing
        errorMessage = nil
        do {
            if !workout.isActive { sessionID = UUID(); try await workout.start() }
            if workout.isPaused { workout.resume() }
            let device = WKInterfaceDevice.current()
            let participantID = Self.participantID()
            var machine = utsname()
            uname(&machine)
            let hardware = withUnsafeBytes(of: &machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let metadata = RecordingMetadata(participantID: participantID, sessionID: sessionID,
                                             exerciseID: selectedExercise.id,
                                             equipment: equipmentVariant.isEmpty ? selectedExercise.equipment : equipmentVariant,
                                             weightKG: weightKG, startedAt: Date(),
                                             watchWrist: device.wristLocation == .left ? "left" : "right",
                                             watchModel: hardware, watchOSVersion: device.systemVersion)
            try recorder.start(directory: draftDirectory, metadata: metadata)
            self.metadata = metadata
            pendingFinishedFile = nil
            actualReps = 0
            quality = .init()
            recordingStartedAt = metadata.startedAt
            phase = .recording
        } catch {
            phase = .ready
            errorMessage = error.localizedDescription
        }
    }

    func endSet() {
        guard phase == .recording else { return }
        quality = recorder.stop()
        metadata?.endedAt = Date()
        phase = .review
        if quality.sampleCount == 0 { errorMessage = "No motion samples were captured. This set cannot be saved as a valid recording." }
    }

    func saveSet() async {
        guard phase == .review, var metadata, quality.sampleCount > 0,
              actualReps > 0, weightKG.isFinite, weightKG >= 0 else { return }
        phase = .saving
        errorMessage = nil
        metadata.actualReps = actualReps
        metadata.weightKG = weightKG
        metadata.labelReviewStatus = .reviewed
        metadata.endedAt = metadata.endedAt ?? Date()
        do {
            let annotation = SetAnnotation(exerciseID: metadata.exerciseID ?? selectedExercise.id,
                                           startTimestamp: quality.firstTimestamp!, endTimestamp: quality.lastTimestamp!,
                                           actualReps: actualReps, weightKG: weightKG)
            let source: URL
            if let pendingFinishedFile { source = pendingFinishedFile }
            else {
                source = try recorder.finish(metadata: metadata, annotations: [annotation])
                pendingFinishedFile = source
            }
            let destination = try await store.importFile(at: source, metadata: metadata)
            transfer.enqueue(fileURL: destination, recordingID: metadata.id)
            if source != destination { try? FileManager.default.removeItem(at: source) }
            savedCount += 1
            self.metadata = nil
            pendingFinishedFile = nil
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
        do { try await workout.finish(); phase = .ready }
        catch { phase = .ready; errorMessage = "Motion recordings are saved. Health workout save failed: \(error.localizedDescription)" }
    }

    func retryTransfers() async { await transfer.retryPending() }

    func refreshRecordings() async {
        do { recentRecordings = try await store.list() }
        catch { errorMessage = "Recording list could not be loaded: \(error.localizedDescription)" }
        let files = (try? FileManager.default.contentsOfDirectory(at: draftDirectory, includingPropertiesForKeys: nil)) ?? []
        pendingDraftCount = files.filter { $0.pathExtension == "partial" }.count
    }

    private func interrupt(_ message: String) {
        if phase == .recording {
            quality = recorder.stop()
            metadata?.endedAt = Date()
            metadata?.status = .interrupted
            phase = .review
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

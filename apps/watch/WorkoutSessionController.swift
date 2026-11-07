import Foundation
import HealthKit
import Combine

@MainActor
final class WorkoutSessionController: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    @Published private(set) var isActive = false
    @Published private(set) var isPaused = false
    @Published private(set) var startedAt: Date?
    var onInterruption: ((String) -> Void)?
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var ending = false

    func start() async throws {
        guard !isActive else { return }
        guard HKHealthStore.isHealthDataAvailable() else { throw WorkoutError.unavailable }
        try await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { throw WorkoutError.denied }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        session.delegate = self
        builder.delegate = self
        // Run 1 only saves workout duration. No health samples are read or exported.
        self.session = session
        self.builder = builder
        ending = false
        let date = Date()
        session.startActivity(with: date)
        do {
            try await builder.beginCollection(at: date)
            startedAt = date
            isActive = true
        } catch {
            ending = true
            session.end()
            builder.discardWorkout()
            self.session = nil
            self.builder = nil
            throw error
        }
    }

    func pause() { session?.pause(); isPaused = true }
    func resume() { session?.resume(); isPaused = false }

    func finish() async throws {
        guard let session, let builder else { return }
        ending = true
        session.end()
        isActive = false
        isPaused = false
        defer { self.session = nil; self.builder = nil }
        try await builder.endCollection(at: Date())
        _ = try await builder.finishWorkout()
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.isPaused = toState == .paused
            if toState == .ended, !self.ending {
                self.isActive = false
                self.onInterruption?("The workout session ended. Your motion recording needs review.")
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.isActive = false
            self.onInterruption?("Workout interrupted: \(error.localizedDescription)")
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}

    enum WorkoutError: LocalizedError {
        case unavailable, denied
        var errorDescription: String? {
            switch self {
            case .unavailable: "HealthKit is unavailable on this device."
            case .denied: "Allow LIFTR to save workouts in Health permissions before recording."
            }
        }
    }
}

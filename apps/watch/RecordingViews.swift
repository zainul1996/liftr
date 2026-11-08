import LIFTRCore
import LIFTRSync
import SwiftUI

struct RecordingHomeView: View {
  @ObservedObject var controller: RecordingController
  @State private var showingExercises = false
  @State private var showingRecordings = false
  @State private var confirmPreserve = false
  @State private var recordingToDelete: RecordingMetadata?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 12) {
          switch controller.phase {
          case .preparing, .saving:
            ProgressView(controller.phase == .saving ? "Saving set" : "Preparing workout")
          case .recording:
            recording
          case .review:
            review
          case .ready, .rest:
            ready
          }
        }
        .padding(.horizontal, 4)
      }
      .navigationTitle("LIFTR")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $showingExercises) { exercises }
      .sheet(isPresented: $showingRecordings) { recordings }
      .alert(
        "Recording notice",
        isPresented: Binding(
          get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } }
        )
      ) {
        Button("OK") { controller.errorMessage = nil }
      } message: {
        Text(controller.errorMessage ?? "")
      }
      .confirmationDialog(
        "Keep this unfinished recording for later recovery?", isPresented: $confirmPreserve,
        titleVisibility: .visible
      ) {
        Button("Keep draft") { controller.keepInterruptedDraft() }
        Button("Continue review", role: .cancel) {}
      }
    }
    .tint(.green)
  }

  private var ready: some View {
    VStack(spacing: 12) {
      #if DEBUG && targetEnvironment(simulator)
        if SimulatorTestSupport.enabled {
          Text("SYNTHETIC UI TEST DATA").font(.caption2).foregroundStyle(.orange)
        }
      #endif
      if controller.phase == .rest, let date = controller.restStartedAt {
        HStack {
          Text("REST").foregroundStyle(.secondary)
          Spacer()
          Text(date, style: .timer).monospacedDigit().foregroundStyle(.green)
        }.font(.caption)
      }
      Button {
        showingExercises = true
      } label: {
        VStack(spacing: 4) {
          Text(controller.selectedExercise.name).font(.headline).multilineTextAlignment(.center)
          Text("Change exercise").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
      }
      .buttonStyle(.plain).accessibilityIdentifier("watch.exercise")
      .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
      Button {
        Task { await controller.startSet() }
      } label: {
        Label(
          controller.workout.isActive ? "Start Set" : "Start Workout", systemImage: "record.circle"
        )
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent).accessibilityIdentifier("watch.start")
      .foregroundStyle(.black)
      .disabled(controller.continuousCaptureStopped && controller.isContinuousRecording)
      if !controller.workout.isActive && !controller.isContinuousRecording {
        Toggle("Record rest too", isOn: $controller.continuousMode).font(.caption)
        if controller.continuousMode {
          Text(
            "Continuous raw capture includes rest and transitions. Mark each set. Battery use needs device testing."
          )
          .font(.caption2).foregroundStyle(.secondary)
        }
      }
      if controller.isContinuousRecording {
        Text(
          controller.continuousCaptureStopped
            ? "Capture stopped. Save session below."
            : "Continuous capture · \(controller.annotatedSetCount) labelled sets"
        )
        .font(.caption2).foregroundStyle(
          controller.continuousCaptureStopped ? Color.orange : Color.green)
      }
      TextField("Machine variant", text: $controller.equipmentVariant).font(.caption)
      Text("Data collection mode").font(.caption2).foregroundStyle(.secondary)
      if controller.workout.isActive || controller.isContinuousRecording {
        Button("End Workout") { Task { await controller.finishWorkout() } }.tint(.gray)
      }
      Button("Recordings · \(controller.recentRecordings.count)") { showingRecordings = true }
        .font(.caption)
      SyncStatusView(transfer: controller.transfer)
      if controller.pendingDraftCount > 0 {
        Text("\(controller.pendingDraftCount) unfinished recording(s) retained on Watch.")
          .font(.caption2).foregroundStyle(.orange)
        Button("Recover recordings") { Task { await controller.recoverDrafts() } }
          .font(.caption2).disabled(controller.isContinuousRecording)
      }
    }
  }

  private var recording: some View {
    VStack(spacing: 12) {
      HStack(spacing: 6) {
        Circle().fill(.red).frame(width: 7, height: 7)
        Text("RECORDING").font(.caption2).foregroundStyle(.red)
      }
      Text(controller.selectedExercise.name).font(.headline).multilineTextAlignment(.center)
      if let date = controller.recordingStartedAt {
        Text(date, style: .timer).font(.system(.largeTitle, design: .rounded).monospacedDigit())
      }
      Text("\(controller.quality.sampleCount) samples").font(.caption2).foregroundStyle(.secondary)
      if let measured = controller.quality.measuredHz {
        Text("\(measured, specifier: "%.1f") Hz measured").font(.caption2).foregroundStyle(
          .secondary)
      }
      Button("End Set") { controller.endSet() }
        .buttonStyle(.borderedProminent).tint(.red)
      Text("Finish the movement, then tap End Set.").font(.caption2).foregroundStyle(.secondary)
    }
  }

  private var review: some View {
    VStack(spacing: 12) {
      Text("Save set").font(.title3.bold())
      Text(controller.selectedExercise.name).font(.caption).multilineTextAlignment(.center)
      Stepper(value: $controller.actualReps, in: 0...200) {
        VStack(alignment: .leading) {
          Text("Actual reps").font(.caption2).foregroundStyle(.secondary)
          Text(controller.actualReps == 0 ? "Enter reps" : "\(controller.actualReps)").font(.title3)
        }
      }
      .disabled(controller.labelsLockedForSaveRetry)
      Stepper(value: $controller.weightKG, in: 0...500, step: 0.5) {
        VStack(alignment: .leading) {
          Text("Weight · kg").font(.caption2).foregroundStyle(.secondary)
          Text(controller.weightKG, format: .number.precision(.fractionLength(0...1))).font(.title3)
        }
      }
      .disabled(controller.labelsLockedForSaveRetry)
      if controller.labelsLockedForSaveRetry {
        Text(
          "Labels are finalized. Retry saving this file, then correct labels on iPhone if needed."
        )
        .font(.caption2).foregroundStyle(.orange)
      }
      if controller.quality.gapCount > 0 || controller.quality.rejectedSamples > 0 {
        Text(
          "Signal check: \(controller.quality.gapCount) gaps, \(controller.quality.rejectedSamples) rejected samples."
        )
        .font(.caption2).foregroundStyle(.orange)
      }
      Button("Save Set") { Task { await controller.saveSet() } }
        .buttonStyle(.borderedProminent).foregroundStyle(.black)
        .disabled(controller.actualReps <= 0 || controller.quality.sampleCount < 2)
      Button(
        controller.isContinuousRecording ? "Leave interval unlabelled" : "Keep unfinished draft"
      ) { confirmPreserve = true }
      .font(.caption2).tint(.gray).disabled(controller.labelsLockedForSaveRetry)
    }
  }

  private var exercises: some View {
    NavigationStack {
      List(ExerciseLibrary.all) { exercise in
        Button {
          controller.selectedExercise = exercise
          controller.equipmentVariant = ""
          showingExercises = false
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
            Text(exercise.equipment).font(.caption2).foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Exercise")
    }
  }

  private var recordings: some View {
    NavigationStack {
      List {
        if controller.recentRecordings.isEmpty {
          Text("Your saved sets will appear here.").foregroundStyle(.secondary)
        }
        ForEach(controller.recentRecordings) { metadata in
          VStack(alignment: .leading, spacing: 4) {
            Text(ExerciseLibrary.find(id: metadata.exerciseID ?? "")?.name ?? "Recording").font(
              .headline)
            Text(
              "\(metadata.actualReps.map(String.init) ?? "Unknown") reps · \(metadata.weightKG ?? 0, specifier: "%g") kg"
            ).font(.caption)
            Text(metadata.startedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
            if metadata.status == .interrupted {
              Text("Interrupted").font(.caption2).foregroundStyle(.orange)
            }
            Button("Delete Watch copy", role: .destructive) { recordingToDelete = metadata }
              .font(.caption2)
          }
        }
        Button("Retry iPhone transfer") { Task { await controller.retryTransfers() } }
      }
      .navigationTitle("Recordings")
      .task { await controller.refreshRecordings() }
      .confirmationDialog(
        "Delete this Watch copy?",
        isPresented: Binding(
          get: { recordingToDelete != nil }, set: { if !$0 { recordingToDelete = nil } }),
        titleVisibility: .visible
      ) {
        if let selected = recordingToDelete {
          Button("Delete Watch copy", role: .destructive) {
            recordingToDelete = nil
            Task { await controller.deleteSavedRecording(id: selected.id) }
          }
        }
        Button("Keep recording", role: .cancel) { recordingToDelete = nil }
      } message: {
        Text(
          "Unsent motion may be permanently lost. Queued transfers are cancelled where possible. iPhone copies and exports are separate."
        )
      }
    }
  }
}

private struct SyncStatusView: View {
  @ObservedObject var transfer: RecordingTransfer
  var body: some View {
    Text(transfer.status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(
      .center)
  }
}

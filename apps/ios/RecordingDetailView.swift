import Charts
import LIFTRCore
import SwiftUI

private struct MotionChartPoint: Identifiable {
  var id: Double { seconds }
  let seconds: Double
  let magnitude: Double
}

struct RecordingDetailView: View {
  let original: RecordingMetadata
  @EnvironmentObject private var library: PhoneLibrary
  @Environment(\.dismiss) private var dismiss
  @State private var recording: Recording?
  @State private var chartPoints: [MotionChartPoint] = []
  @State private var share: ShareFiles?
  @State private var showEditor = false
  @State private var showDelete = false
  @State private var loadError: String?
  @State private var observedHz: Double?
  @State private var gaps = 0

  private var metadata: RecordingMetadata { library.displayedMetadata(original) }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text(exerciseName(metadata.exerciseID)).font(.title2.weight(.bold))
          Text(metadata.startedAt, format: .dateTime.month().day().hour().minute()).foregroundStyle(
            .secondary)
          HStack(spacing: 24) {
            VStack(alignment: .leading) {
              Text(metadata.actualReps.map(String.init) ?? "?").font(
                .system(size: 38, weight: .bold, design: .rounded))
              Text("ACTUAL REPS").font(.caption2).foregroundStyle(.secondary)
            }
            if let weight = metadata.weightKG {
              VStack(alignment: .leading) {
                Text(weight, format: .number.precision(.fractionLength(0...1))).font(
                  .system(size: 38, weight: .bold, design: .rounded))
                Text("KILOGRAMS").font(.caption2).foregroundStyle(.secondary)
              }
            }
          }
        }.padding(.vertical, 8)
      }
      Section("Motion preview") {
        if let loadError {
          Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else if recording == nil {
          ProgressView("Loading raw motion")
        } else if chartPoints.isEmpty {
          Text("No motion samples were saved.").foregroundStyle(.secondary)
        } else {
          Chart(chartPoints) { point in
            LineMark(
              x: .value("Seconds", point.seconds), y: .value("Acceleration, g", point.magnitude)
            )
            .foregroundStyle(Color.liftrLime)
          }.frame(height: 150)
            .chartXAxisLabel("Seconds from first sample")
            .chartYAxisLabel("User acceleration, g")
            .accessibilityLabel("User acceleration magnitude over time")
          Text("Preview is downsampled for display. Export retains every raw sample.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if let recording {
        if recording.metadata.mode == .continuous, !recording.annotations.isEmpty {
          Section("Labelled sets") {
            ForEach(recording.annotations) { annotation in
              VStack(alignment: .leading, spacing: 5) {
                Text(exerciseName(annotation.exerciseID)).font(.headline)
                HStack {
                  Text(annotation.actualReps.map { "\($0) reps" } ?? "Reps unknown")
                  if let weight = annotation.weightKG { Text("\(weight.formatted()) kg") }
                }.font(.caption).foregroundStyle(.secondary)
                if let first = recording.samples.first {
                  Text(
                    "\((annotation.startTimestamp - first.timestamp).formatted(.number.precision(.fractionLength(1)))) to \((annotation.endTimestamp - first.timestamp).formatted(.number.precision(.fractionLength(1)))) seconds"
                  )
                  .font(.caption2).foregroundStyle(.secondary)
                }
              }.padding(.vertical, 3)
            }
          }
        }
        Section("Recording quality") {
          LabeledContent("Samples", value: "\(recording.samples.count)").accessibilityIdentifier(
            "quality.samples"
          ).accessibilityValue("\(recording.samples.count)")
          LabeledContent(
            "Target rate", value: "\(original.sensorConfiguration.targetHz.formatted()) Hz")
          if let observedHz {
            LabeledContent(
              "Observed rate",
              value: "\(observedHz.formatted(.number.precision(.fractionLength(1)))) Hz")
          }
          LabeledContent("Gaps above 2.5 intervals", value: "\(gaps)").accessibilityIdentifier(
            "quality.gaps"
          ).accessibilityValue("\(gaps)")
          LabeledContent("Set annotations", value: "\(recording.annotations.count)")
          LabeledContent("Capture status", value: original.status.rawValue.capitalized)
          Text(
            "Sampling rate is measured from timestamps. Gaps remain in the raw recording and need review before training."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      Section("Labels") {
        LabeledContent("Equipment", value: metadata.equipment ?? "Not entered")
        LabeledContent("Review", value: metadata.labelReviewStatus.rawValue.capitalized)
        LabeledContent("iPhone review history", value: "\(library.reviewCount(for: original.id))")
        Button("Review exercise, reps and weight") { showEditor = true }.accessibilityIdentifier(
          "recording.review"
        ).disabled(
          original.mode != .set)
        Text(
          "Review keeps the original recording. Exports include your latest labels and the original metadata with correction history."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Device") {
        LabeledContent("Watch", value: original.watchModel)
        LabeledContent("watchOS", value: original.watchOSVersion)
        LabeledContent("Wrist", value: original.watchWrist)
        LabeledContent(
          "Schema / taxonomy", value: "\(original.schemaVersion) / \(original.taxonomyVersion)")
        Text("Recording \(original.id.uuidString)").font(.caption.monospaced()).textSelection(
          .enabled)
      }
      Section {
        Button("Export recording", systemImage: "square.and.arrow.up") { Task { await export() } }
          .accessibilityIdentifier("recording.export")
        Button("Delete from iPhone", role: .destructive) { showDelete = true }
          .accessibilityIdentifier("recording.delete")
      }
    }
    .navigationTitle("Recording")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .sheet(item: $share) { NativeShareSheet(urls: $0.urls) }
    .sheet(isPresented: $showEditor) {
      ReviewRecordingView(metadata: metadata) { exerciseID, reps, weight in
        try library.saveReview(
          for: original.id, exerciseID: exerciseID, reps: reps, weightKG: weight)
      }
    }
    .confirmationDialog(
      "Delete this iPhone copy?", isPresented: $showDelete, titleVisibility: .visible
    ) {
      Button("Delete from iPhone", role: .destructive) {
        Task {
          if await library.deleteFromPhone(original.id) { dismiss() }
        }
      }.accessibilityIdentifier("recording.confirmDelete")
      Button("Cancel", role: .cancel) {}.accessibilityIdentifier("recording.cancelDelete")
    } message: {
      Text(
        "This also removes its iPhone review history. Watch recordings, exported files and backups are separate copies. A later Watch retry may send it again."
      )
    }
  }

  private func load() async {
    do {
      let loaded = try await library.load(original.id)
      recording = loaded
      let samples = loaded.samples
      guard let first = samples.first, let last = samples.last, last.timestamp > first.timestamp
      else { return }
      observedHz = Double(samples.count - 1) / (last.timestamp - first.timestamp)
      gaps =
        zip(samples, samples.dropFirst()).filter {
          $1.timestamp - $0.timestamp > 2.5 / original.sensorConfiguration.targetHz
        }.count
      let step = max(1, samples.count / 500)
      chartPoints = stride(from: 0, to: samples.count, by: step).map { index in
        let sample = samples[index]
        let acceleration = sample.userAcceleration
        return MotionChartPoint(
          seconds: sample.timestamp - first.timestamp,
          magnitude: sqrt(
            acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z
              * acceleration.z))
      }
    } catch { loadError = "Could not read recording: \(error.localizedDescription)" }
  }

  private func export() async {
    do { share = ShareFiles(urls: try await library.exportURLs(for: [original.id])) } catch {
      library.errorMessage = "Export failed: \(error.localizedDescription)"
    }
  }
}

private struct ReviewRecordingView: View {
  let metadata: RecordingMetadata
  let save: (String, Int, Double?) throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var exerciseID: String
  @State private var reps: String
  @State private var weight: String
  @State private var errorMessage: String?

  init(metadata: RecordingMetadata, save: @escaping (String, Int, Double?) throws -> Void) {
    self.metadata = metadata
    self.save = save
    _exerciseID = State(initialValue: metadata.exerciseID ?? ExerciseLibrary.all[0].id)
    _reps = State(initialValue: metadata.actualReps.map(String.init) ?? "")
    _weight = State(initialValue: metadata.weightKG.map { String($0) } ?? "")
  }

  private var parsedWeight: Double? { Double(weight.replacingOccurrences(of: ",", with: ".")) }
  private var valid: Bool {
    guard let reps = Int(reps), reps >= 0 else { return false }
    return weight.isEmpty || parsedWeight.map { $0.isFinite && $0 >= 0 } == true
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("What did you complete?") {
          Picker("Exercise", selection: $exerciseID) {
            ForEach(ExerciseLibrary.all) { Text($0.name).tag($0.id) }
          }.pickerStyle(.menu).accessibilityIdentifier("review.exercise")
          TextField("Actual repetitions", text: $reps).keyboardType(.numberPad)
            .accessibilityIdentifier("review.reps")
          TextField("Weight in kg, optional", text: $weight).keyboardType(.decimalPad)
            .accessibilityIdentifier("review.weight")
        }
        Section {
          Text(
            "The original labels stay untouched. LIFTR saves each review and includes it in the exported dataset."
          )
          .font(.footnote).foregroundStyle(.secondary)
          if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
      }
      .navigationTitle("Review set")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard valid, let count = Int(reps) else { return }
            do {
              try save(exerciseID, count, weight.isEmpty ? nil : parsedWeight)
              dismiss()
            } catch { errorMessage = error.localizedDescription }
          }.disabled(!valid).accessibilityIdentifier("review.save")
        }
      }
    }.tint(.liftrLime)
  }
}

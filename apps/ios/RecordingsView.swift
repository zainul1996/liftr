import LIFTRCore
import SwiftUI
import UIKit

struct ShareFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct NativeShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct RecordingsView: View {
    @EnvironmentObject private var library: PhoneLibrary
    @State private var share: ShareFiles?
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LIFT MORE. LOG LESS.").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Color.liftrLime)
                        Text("Your movement,\nready to review.").font(.largeTitle.weight(.bold))
                        Label(library.syncStatus, systemImage: "applewatch").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 12).listRowBackground(Color.clear)
                }
                if library.recordings.isEmpty {
                    Section {
                        ContentUnavailableView("Ready for your first set", systemImage: "waveform.path",
                            description: Text("Record a labelled set on your Watch. Keep LIFTR installed on both devices. Transfers arrive here when the system delivers them."))
                    }.listRowBackground(Color.clear)
                } else {
                    Section("On this iPhone · \(library.recordings.count)") {
                        ForEach(library.recordings) { original in
                            let metadata = library.displayedMetadata(original)
                            NavigationLink {
                                RecordingDetailView(original: original)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(exerciseName(metadata.exerciseID)).font(.headline)
                                    HStack {
                                        Text(metadata.startedAt, style: .date)
                                        Spacer()
                                        Text(metadata.actualReps.map { "\($0) reps" } ?? "Reps unknown")
                                        if let weight = metadata.weightKG { Text(weight, format: .number.precision(.fractionLength(0...1))) + Text(" kg") }
                                    }.font(.caption).foregroundStyle(.secondary)
                                    if library.reviewCount(for: metadata.id) > 0 {
                                        Label("Reviewed on iPhone", systemImage: "checkmark.circle").font(.caption2).foregroundStyle(Color.liftrLime)
                                    }
                                    if metadata.status == .interrupted {
                                        Label("Interrupted recording", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("LIFTR")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await exportAll() } } label: {
                        if isExporting { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                    }.disabled(library.recordings.isEmpty || isExporting).accessibilityLabel("Export all recordings")
                }
            }
            .refreshable { await library.refresh() }
            .sheet(item: $share) { NativeShareSheet(urls: $0.urls) }
        }
    }

    private func exportAll() async {
        isExporting = true
        defer { isExporting = false }
        do { share = ShareFiles(urls: try await library.exportURLs(for: library.recordings.map(\.id))) }
        catch { library.errorMessage = "Export failed: \(error.localizedDescription)" }
    }
}

func exerciseName(_ id: String?) -> String {
    guard let id else { return "Continuous recording" }
    return ExerciseLibrary.find(id: id)?.name ?? id
}

struct ExerciseListView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Run 1 collects labelled motion. Automatic recognition will be evaluated after real gym recordings are available.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Your exercise library") {
                    ForEach(ExerciseLibrary.all) { exercise in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(exercise.name).font(.headline)
                            Text(exercise.equipment).font(.caption).foregroundStyle(.secondary)
                            Text("Manual labelling").font(.caption2).foregroundStyle(Color.liftrLime)
                        }.padding(.vertical, 4)
                    }
                }
            }.navigationTitle("Exercises")
        }
    }
}

struct PhoneSettingsView: View {
    @EnvironmentObject private var library: PhoneLibrary
    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    LabeledContent("Watch", value: library.syncStatus)
                    Button("Refresh recordings") { Task { await library.refresh() } }
                    Text("Background file transfers need paired physical devices. Keep both apps installed. A disconnected phone does not stop Watch recording.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your data") {
                    Text("LIFTR has no account or backend. Intentional recordings stay in local app storage until you choose to export them.")
                    Text("Delete individual recordings from their detail screen. This removes the iPhone copy. Watch copies, exported files and system backups are separate.")
                    Text("Export uses the system share sheet. Choose Save to Files to keep a dataset, or another destination you trust.")
                }.font(.subheadline)
                Section("Research mode") {
                    Text("This build collects training labels. It does not predict exercises or count repetitions automatically. Enter the repetitions you actually completed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
        }
    }
}

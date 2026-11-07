import SwiftUI

@main
struct LIFTRPhoneApp: App {
    @StateObject private var library = PhoneLibrary()
    var body: some Scene {
        WindowGroup {
            TabView {
                RecordingsView().tabItem { Label("Recordings", systemImage: "waveform.path") }
                ExerciseListView().tabItem { Label("Exercises", systemImage: "dumbbell") }
                PhoneSettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environmentObject(library)
            .tint(.liftrLime)
            .preferredColorScheme(.dark)
            .task { await library.refresh() }
            .alert("LIFTR", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "") }
        }
    }
}

extension Color {
    static let liftrLime = Color(red: 0.78, green: 0.96, blue: 0.28)
}

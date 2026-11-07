import SwiftUI

@main
struct LIFTRWatchApp: App {
  var body: some Scene { WindowGroup { WatchStartupView() } }
}

private struct WatchStartupView: View {
  @State private var controller: RecordingController?
  @State private var storageError: String?

  var body: some View {
    Group {
      if let controller {
        RecordingHomeView(controller: controller)
      } else if let storageError {
        VStack(spacing: 12) {
          Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(.orange)
          Text("Storage unavailable").font(.headline)
          Text(storageError).font(.footnote)
          Button("Try again") { prepare() }
        }.padding()
      } else {
        ProgressView("Opening LIFTR")
      }
    }
    .task { if controller == nil { prepare() } }
  }

  private func prepare() {
    do {
      controller = try RecordingController()
      storageError = nil
    } catch { storageError = error.localizedDescription }
  }
}

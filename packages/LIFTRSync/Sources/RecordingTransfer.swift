import Foundation
import LIFTRCore
import LIFTRPersistence
#if canImport(WatchConnectivity)
import WatchConnectivity
import Combine

@MainActor
public final class RecordingTransfer: NSObject, ObservableObject, WCSessionDelegate {
    @Published public private(set) var status = "Not activated"
    @Published public private(set) var receivedCount = 0
    public var onReceive: (@MainActor () -> Void)?
    private let store: RecordingStore
    public init(store: RecordingStore) { self.store = store; super.init() }
    public func activate() {
        guard WCSession.isSupported() else { status = "WatchConnectivity unavailable"; return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    public func enqueue(fileURL: URL, recordingID: UUID) {
        guard WCSession.default.activationState == .activated else { status = "Waiting for connection activation"; return }
        guard !WCSession.default.outstandingFileTransfers.contains(where: { ($0.file.metadata?["recordingID"] as? String) == recordingID.uuidString }) else { return }
        WCSession.default.transferFile(fileURL, metadata: ["recordingID": recordingID.uuidString, "schemaVersion": 1])
        status = "Queued for iPhone"
    }
    public func retryPending() async {
        do { for metadata in try await store.list() { enqueue(fileURL: await store.fileURL(id: metadata.id), recordingID: metadata.id) } }
        catch { status = "Unable to load pending recordings: \(error.localizedDescription)" }
    }
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.status = error?.localizedDescription ?? (activationState == .activated ? "Ready" : "Not connected"); if activationState == .activated { await self.retryPending() } }
    }
    nonisolated public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WCSession deletes its temporary file after this callback returns.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".liftr.json")
        do { try FileManager.default.copyItem(at: file.fileURL, to: temporary) }
        catch { Task { @MainActor in self.status = "Receive failed: \(error.localizedDescription)" }; return }
        Task { @MainActor in
            defer { try? FileManager.default.removeItem(at: temporary) }
            do { _ = try await store.importFile(at: temporary); receivedCount += 1; status = "Recording received"; onReceive?() }
            catch { status = "Import failed: \(error.localizedDescription)" }
        }
    }
    nonisolated public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        Task { @MainActor in self.status = error.map { "Transfer failed: \($0.localizedDescription). Retry from settings." } ?? "Transferred" }
    }
    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif

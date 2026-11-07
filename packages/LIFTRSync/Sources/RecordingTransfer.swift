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
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    public func enqueue(fileURL: URL, recordingID: UUID) {
        #if os(watchOS)
        guard WCSession.default.activationState == .activated else {
            status = "Saved locally. Waiting for connection activation."
            return
        }
        guard !WCSession.default.outstandingFileTransfers.contains(where: {
            ($0.file.metadata?["recordingID"] as? String) == recordingID.uuidString
        }) else { return }
        WCSession.default.transferFile(fileURL, metadata: ["recordingID": recordingID.uuidString, "schemaVersion": 1])
        status = "Queued for iPhone"
        #endif
    }
    public func retryPending() async {
        #if os(watchOS)
        do {
            for metadata in try await store.pendingTransfers() {
                enqueue(fileURL: await store.fileURL(id: metadata.id), recordingID: metadata.id)
            }
        } catch { status = "Unable to load pending recordings: \(error.localizedDescription)" }
        #else
        status = "Ready to receive from Apple Watch"
        #endif
    }
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let message = error?.localizedDescription ?? (activationState == .activated ? "Ready" : "Not connected")
        let activated = activationState == .activated
        Task { @MainActor in
            self.status = message
            if activated { await self.retryPending() }
        }
    }
    nonisolated public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Apple deletes the temporary URL when this delegate callback returns.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".liftr.json")
        let declaredID = file.metadata?["recordingID"] as? String
        do { try FileManager.default.copyItem(at: file.fileURL, to: temporary) }
        catch {
            let message = error.localizedDescription
            Task { @MainActor in self.status = "Receive failed: \(message)" }
            return
        }
        Task { @MainActor in
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                let imported = try await store.importFile(at: temporary)
                let id = imported.deletingPathExtension().deletingPathExtension().lastPathComponent
                guard declaredID == nil || declaredID == id else { throw RecordingStore.StoreError.identityMismatch }
                WCSession.default.transferUserInfo(["kind": "recordingAcknowledged", "recordingID": id])
                receivedCount += 1
                status = "Recording received"
                onReceive?()
            } catch { status = "Import failed: \(error.localizedDescription)" }
        }
    }
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard userInfo["kind"] as? String == "recordingAcknowledged",
              let raw = userInfo["recordingID"] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in
            do { try await store.acknowledgeTransfer(id: id); status = "Saved on iPhone" }
            catch { status = "Acknowledgement could not be saved. Retry remains available." }
        }
    }
    nonisolated public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        let message = error.map { "Transfer failed: \($0.localizedDescription). Retry from settings." }
            ?? "Delivered. Waiting for iPhone import confirmation."
        Task { @MainActor in self.status = message }
    }
    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif

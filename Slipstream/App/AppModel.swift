import SwiftUI
import Observation
import Security

@MainActor @Observable final class AppModel {
    let downloads = DownloadManager()
    #if DEBUG
    var chatPreview = false
    #endif
    var emotes: [FPEmote] = []
    var sidebarHidden = false
    #if os(macOS)
    var windowFullscreen = false
    var immersiveVideo = false
    var playerControlsVisible = true
    var sidebarWidth: CGFloat = 260
    #endif
    var user: FPUser?
    var creators: [Creator] = []
    var channelsByCreator: [String: [CreatorChannel]] = [:]
    var channelsByID: [String: CreatorChannel] = [:]
    var api: FloatplaneAPI?
    var cookie: SessionCookie?
    var restoring = true
    var showLogin = false
    var needsKeychainApproval = false
    var error: String?
    var demo = ProcessInfo.processInfo.arguments.contains("--demo")

    func restore(allowKeychainUI: Bool = false) async {
        restoring = true
        defer { restoring = false }
        if demo { creators = DemoData.creators; return }
        do {
            if let cookie = try await SessionStore.load(allowUserInteraction: allowKeychainUI) { try await authenticate(cookie, persist: false) }
        } catch APIError.signedOut {
            try? await SessionStore.delete()
        } catch let error as SessionStore.StoreError where error.status == errSecInteractionNotAllowed {
            needsKeychainApproval = true
        } catch { self.error = error.localizedDescription }
    }
    func authenticate(_ cookie: SessionCookie, persist: Bool = true) async throws {
        let client = FloatplaneAPI(cookie: cookie)
        let user = try await client.user()
        try Task.checkCancellation()
        if persist { try await SessionStore.save(cookie) }
        self.emotes = []
        self.cookie = cookie
        self.api = client
        self.user = user
        needsKeychainApproval = false
        demo = false
        await loadCreators()
        showLogin = false
    }
    func loadCreators() async {
        guard let api else { return }
        do {
            creators = try await api.creators()
            let channels = try await api.channels(creators: creators.map(\.id))
            channelsByCreator = Dictionary(grouping: channels, by: \.creator).mapValues { $0.sorted { ($0.order ?? 0) < ($1.order ?? 0) } }
            channelsByID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        catch { handle(error) }
    }
    func handle(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if error as? APIError == .signedOut {
            Task { try? await SessionStore.delete() }
            api = nil; user = nil; cookie = nil; creators = []; emotes = []
        }
        self.error = error.localizedDescription
    }
    func signOut() async {
        if !demo {
            do { try await SessionStore.delete() }
            catch { self.error = error.localizedDescription; return }
        }
        downloads.cancel()
        api = nil; user = nil; cookie = nil; creators = []; emotes = []; channelsByCreator = [:]; channelsByID = [:]; demo = false
    }
}

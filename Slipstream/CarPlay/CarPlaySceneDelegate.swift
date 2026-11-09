#if os(iOS)
import CarPlay
import Observation

/// CarPlay supplies all layout and video-availability policy, including HomeView.
@available(iOS 26.4, *)
@MainActor final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private let model = AppModel.shared
    private let playback = CarPlayPlayback()
    private var controller: CPInterfaceController?
    private var operation: Task<Void, Never>?
    private var progressObserver: Any?
    private var playingVideoID: String?
    private var videoRows: [(String, CPListItem)] = []

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        playingVideoID = nil
        playback.onFailure = { [weak self] in
            self?.playingVideoID = nil
            self?.showError("Video playback failed. Select the video to retry.")
        }
        let loading = list(title: "Slipstream", items: [], empty: "Loading library…")
        interfaceController.setRootTemplate(loading, animated: false, completion: nil)
        progressObserver = playback.player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePlaybackRows() }
        }
        operation = Task { [weak self] in
            guard let self else { return }
            await model.restoreSession()
            guard !Task.isCancelled else { return }
            observeAccount()
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        operation?.cancel()
        operation = nil
        playback.stop()
        if let progressObserver { playback.player.removeTimeObserver(progressObserver) }
        progressObserver = nil
        controller = nil
        videoRows = []
        playingVideoID = nil
        playback.onFailure = nil
    }

    private func observeAccount() {
        guard controller != nil else { return }
        withObservationTracking {
            showLibrary()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.controller != nil else { return }
                self.operation?.cancel()
                self.playback.stop()
                self.playingVideoID = nil
                self.videoRows = []
                self.observeAccount()
            }
        }
    }

    private func showLibrary() {
        let signedIn = model.api != nil || model.demo
        let items: [CPListItem] = signedIn ? model.creators.map { creator in
            let item = CPListItem(text: creator.title, detailText: nil)
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.run(completion: completion) { [weak self] in try await self?.showPosts(creator: creator, offset: 0) }
            }
            return item
        } : []
        let root = list(title: "Slipstream", items: items,
                        empty: signedIn ? "No subscribed creators" : "Sign in on iPhone",
                        subtitle: signedIn ? "Refresh after updating your subscriptions." : "Open Slipstream on your iPhone to sign in or try the demo.")
        root.trailingNavigationBarButtons = [CPBarButton(title: "Refresh") { [weak self] _ in
            self?.run {
                guard let self else { return }
                await self.model.loadCreators()
                try Task.checkCancellation()
                self.showLibrary()
            }
        }]
        controller?.setRootTemplate(root, animated: false, completion: nil)
    }

    private func showPosts(creator: Creator, offset: Int, page existingPage: CPListTemplate? = nil) async throws {
        let posts: [Post]
        if model.demo { posts = DemoData.posts.filter { $0.creator.id == creator.id } }
        else if let api = model.api { posts = try await api.posts(creator: creator.id, offset: offset) }
        else { throw APIError.signedOut }
        try Task.checkCancellation()
        let items = posts.filter { $0.isAccessible != false }.map { post in
            let item = CPListItem(text: post.title, detailText: post.duration)
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.run(completion: completion) { [weak self] in try await self?.showVideos(post: post) }
            }
            return item
        }
        let page = existingPage ?? list(title: creator.title, items: [], empty: "No accessible posts")
        page.updateSections(items.isEmpty ? [] : [CPListSection(items: items)])
        page.trailingNavigationBarButtons = []
        if !model.demo, posts.count == 20 {
            page.trailingNavigationBarButtons = [CPBarButton(title: "More") { [weak self, weak page] _ in
                self?.run {
                    guard let self, let page, self.controller?.topTemplate === page else { return }
                    try await self.showPosts(creator: creator, offset: offset + posts.count, page: page)
                }
            }]
        }
        if existingPage == nil { try await controller?.pushTemplate(page, animated: true) }
    }

    private func showVideos(post: Post) async throws {
        videoRows = []
        let items: [CPListItem]
        if model.demo {
            let item = videoItem(id: post.id, title: post.title, post: post) { [weak self] in
                guard let self, let url = Bundle.main.url(forResource: "DemoPlayback", withExtension: "mp4") else { throw APIError.noVideo }
                return (url, self.model.cookie)
            }
            items = [item]
        } else {
            guard let api = model.api else { throw APIError.signedOut }
            let detail = try await api.post(id: post.id)
            try Task.checkCancellation()
            items = detail.playableVideos.map { video in
                videoItem(id: video.guid, title: video.title, post: post) { [weak self] in
                    let delivery = try await api.delivery(video: video.guid)
                    try Task.checkCancellation()
                    guard let url = delivery.qualities.first?.url else { throw APIError.noVideo }
                    return (url, self?.model.cookie)
                }
            }
        }
        try Task.checkCancellation()
        try await controller?.pushTemplate(list(title: post.title, items: items, empty: "No playable videos", subtitle: "This post may contain text, images, audio, or locked videos."), animated: true)
    }

    private func videoItem(id: String, title: String, post: Post,
                           source: @escaping @MainActor () async throws -> (URL, SessionCookie?)) -> CPListItem {
        let item = CPListItem(text: title, detailText: post.creator.title)
        item.playbackConfiguration = configuration(id: id)
        item.handler = { [weak self] _, completion in
            self?.run(completion: completion) { [weak self] in
                guard let self else { return }
                if self.playingVideoID == id, let currentItem = self.playback.player.currentItem {
                    if self.playback.player.rate == 0 {
                        if self.playback.player.currentTime() >= currentItem.duration {
                            await self.playback.player.seek(to: .zero)
                        }
                        try Task.checkCancellation()
                        self.playback.resume()
                    } else { self.playback.player.pause() }
                } else {
                    let (url, cookie) = try await source()
                    try Task.checkCancellation()
                    try await self.playback.play(url: url, title: post.title, creator: post.creator.title, cookie: cookie, model: self.model)
                    self.playingVideoID = id
                }
                self.updatePlaybackRows()
            }
        }
        videoRows.append((id, item))
        return item
    }

    private func configuration(id: String) -> CPPlaybackConfiguration {
        let active = id == playingVideoID
        let duration = active ? playback.player.currentItem?.duration ?? .zero : .zero
        let time = active ? playback.player.currentTime() : .zero
        let ended = duration.isNumeric && duration.seconds > 0 && time >= duration
        return CPPlaybackConfiguration(preferredPresentation: .video,
                                       playbackAction: ended ? .replay : active && playback.player.rate != 0 ? .pause : .play,
                                       elapsedTime: time.isNumeric ? time : .zero,
                                       duration: duration.isNumeric ? duration : .zero)
    }

    private func updatePlaybackRows() {
        for (id, item) in videoRows { item.playbackConfiguration = configuration(id: id) }
    }

    private func run(completion: @escaping () -> Void = {}, _ action: @escaping @MainActor () async throws -> Void) {
        operation?.cancel()
        operation = Task { [weak self] in
            defer { completion() }
            do { try await action() }
            catch {
                guard !Task.isCancelled, let self else { return }
                if error as? APIError == .signedOut { self.model.handle(error); return }
                self.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = CPAlertTemplate(titleVariants: [message], actions: [CPAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.controller?.dismissTemplate(animated: true, completion: nil)
        }])
        controller?.presentTemplate(alert, animated: true, completion: nil)
    }

    private func list(title: String, items: [CPListItem], empty: String, subtitle: String = "") -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: items.isEmpty ? [] : [CPListSection(items: items)])
        template.emptyViewTitleVariants = [empty]
        template.emptyViewSubtitleVariants = [subtitle]
        return template
    }
}
#endif

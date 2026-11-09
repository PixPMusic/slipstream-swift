import SwiftUI
import AVKit
import os

struct PlayerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let post: Post
    #if os(iOS)
    @State private var railSession: TouchPlayback?
    @State private var hasRail = false
    #endif
    @State private var controlsVisible = false
    @State private var presentingFullscreen = false
    @State private var playerScrolledAway = false
    @State private var titleScrolledAway = false
    @State private var playerHeight: CGFloat = 0
    @State private var playback: PostPlayback
    private let ownsPlayback: Bool

    init(post: Post, playback: PostPlayback? = nil) {
        self.post = post
        ownsPlayback = playback == nil
        _playback = State(initialValue: playback ?? PostPlayback(post: post))
    }

    private var isVideo: Bool { model.demo || selectedMedia?.kind == .video }
    private var readingPost: Bool { playback.loading || isVideo ? playerScrolledAway : titleScrolledAway }
    private var selectedMedia: PostAttachment? { playback.detail?.media.first { $0.id == playback.selectedMediaID } }
    private var downloadExtension: String {
        guard selectedMedia?.kind == .picture else { return "mp4" }
        guard let suffix = playback.pictureURL?.pathExtension, !suffix.isEmpty else { return "jpg" }
        return suffix
    }
    private var channelName: String {
        post.channel?.title ?? post.channel.flatMap { model.channelsByID[$0.id]?.title } ?? post.creator.title
    }
    private var channelIcon: URL? {
        post.channel.flatMap { model.channelsByID[$0.id]?.icon?.url } ?? post.creator.icon?.url
    }
    private var usesRail: Bool {
        #if os(iOS)
        hasRail
        #else
        false
        #endif
    }
    var body: some View {
        @Bindable var playback = playback
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.demo || playback.loading || selectedMedia?.isPlayable == true {
                    ZStack {
                        NativeVideoPlayer(player: playback.player, onControlsVisibility: { controlsVisible = $0 }, onPresentationChange: { presentingFullscreen = $0 }, qualities: playback.qualities, qualityID: Binding(get: { playback.qualityID }, set: { playback.qualityID = $0; play() }), backAction: { dismiss() }, windowChromeVisible: isVideo ? controlsVisible || playerScrolledAway || !model.sidebarHidden : nil)
                            #if os(iOS)
                            .onPlayerRailChange { session, enabled in railSession = session; hasRail = enabled }
                            #endif
                            .aspectRatio(selectedMedia?.kind == .audio ? 5 : 16 / 9, contentMode: .fit).background(.black)
                        if playback.loading || !playback.playerReady {
                            PostArtwork(url: post.thumbnail?.url)
                            Color.black.opacity(0.45)
                            ProgressView("Loading video…").tint(.white).foregroundStyle(.white)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { playerHeight = $0 }
                    .background { GeometryReader { geometry in Color.clear.preference(key: PlayerBottomKey.self, value: geometry.frame(in: .named("postScroll")).maxY) } }
                } else if selectedMedia?.kind == .picture {
                    AsyncImage(url: playback.pictureURL ?? selectedMedia?.file.thumbnail?.url) { image in image.resizable().scaledToFit() }
                        placeholder: { ProgressView().frame(height: 200) }
                        .frame(maxWidth: .infinity, maxHeight: 600)
                } else if selectedMedia?.kind == .gallery {
                    Link("View gallery on Floatplane", destination: URL(string: "https://www.floatplane.com/post/\(post.id)")!).padding(24)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text(post.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                        .onGeometryChange(for: Bool.self) { $0.frame(in: .named("postScroll")).maxY < 0 } action: { titleScrolledAway = $0 }
                    if let media = playback.detail?.media, media.count > 1 {
                        AttachmentPicker(media: media, selection: $playback.selectedMediaID)
                    }
                    PostMetadataRow(creator: channelName, icon: channelIcon, date: post.date) {
                        HStack(spacing: 10) {
                            if !usesRail {
                                if selectedMedia != nil {
                                    PostDownloadMenu(preparing: playback.preparingDownload, disabled: model.demo, qualities: playback.downloadQualities) { quality in
                                        model.downloads.start(url: quality.url, title: post.title, fileExtension: downloadExtension)
                                    }
                                }
                                #if os(macOS)
                                PostQualityPicker(qualities: playback.qualities, qualityID: Binding(get: { playback.qualityID }, set: { playback.qualityID = $0; play() }))
                                #endif
                                PostFeedbackControl(liked: playback.liked, disliked: playback.disliked, likes: playback.likeCount, dislikes: playback.dislikeCount, disabled: playback.liking || model.demo,
                                                    like: { Task { await toggleReaction(dislike: false) } }, dislike: { Task { await toggleReaction(dislike: true) } })
                            }
                        }.controlSize(.regular).fixedSize()
                    }
                    if playback.detail?.media.isEmpty == true, let text = playback.detail?.text ?? post.text { PostDescription(text: Self.plainText(text), collapsible: false) }
                    DownloadStatusView(download: model.downloads)
                    if let downloadError = playback.downloadError { Text(downloadError).font(.caption).foregroundStyle(.secondary) }
                    if let error = playback.error {
                        HStack { Text(error).foregroundStyle(.secondary); Button("Retry") { Task { await load() } }.disabled(model.demo) }
                    }
                    if playback.detail?.media.isEmpty != true, let text = playback.detail?.text ?? post.text { PostDescription(text: Self.plainText(text)) }
                    Divider().padding(.vertical, 4)
                    CommentsView(postID: post.id, count: playback.detail?.comments)
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.background {
                #if os(macOS)
                OverlayScrollerStyle()
                #endif
            }
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "postScroll")
        .modifier(PlayerScrollTracking(playerHeight: playerHeight, scrolledAway: $playerScrolledAway))
        .modifier(ReadingEdge(reading: readingPost))
        .modifier(PlayerChrome(hideBack: playback.loading || isVideo, title: post.title, reading: readingPost, immersive: (playback.loading || isVideo) && !playerScrolledAway, rail: usesRail))
        .modifier(PlayerBackToolbar(visible: (playback.loading || isVideo) && (controlsVisible || playerScrolledAway), nonVideo: !playback.loading && !isVideo, action: { dismiss() }))
        #if os(iOS)
        .modifier(PlayerRailToolbar(session: railSession, enabled: hasRail, close: { dismiss() }))
        .toolbar {
            if hasRail {
                ToolbarItem(placement: .bottomBar) { Spacer() }
                ToolbarItem(placement: .bottomBar) {
                    if selectedMedia != nil {
                        PostDownloadMenu(preparing: playback.preparingDownload, disabled: model.demo, qualities: playback.downloadQualities) { quality in
                            model.downloads.start(url: quality.url, title: post.title, fileExtension: downloadExtension)
                        }
                    }
                }
                if #available(iOS 26.0, *) { ToolbarSpacer(.fixed, placement: .bottomBar) }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(playback.liked ? "Unlike post" : "Like post", systemImage: playback.liked ? "hand.thumbsup.fill" : "hand.thumbsup") { Task { await toggleReaction(dislike: false) } }.disabled(playback.liking || model.demo).tint(.white).accessibilityValue(playback.likeCount.formatted())
                    Button(playback.disliked ? "Remove dislike" : "Dislike post", systemImage: playback.disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown") { Task { await toggleReaction(dislike: true) } }.disabled(playback.liking || model.demo).tint(.white).accessibilityValue(playback.dislikeCount.formatted())
                }
            }
        }
        #endif
        #if os(macOS)
        .onChange(of: controlsVisible) { _, value in model.playerControlsVisible = value || playerScrolledAway }
        .onChange(of: playerScrolledAway) { _, value in model.playerControlsVisible = value || controlsVisible }
        #endif
        .task { if playback.detail == nil && playback.player.currentItem == nil { await load() } }
        .task(id: playback.selectedMediaID) {
            if !playback.selectedMediaID.isEmpty && (playback.loadedMediaID != playback.selectedMediaID || playback.player.currentItem == nil) {
                await loadSelectedMedia()
            }
        }
        .onDisappear {
            if ownsPlayback && !presentingFullscreen { playback.stop() }
        }
    }
    private func toggleReaction(dislike: Bool) async {
        guard let api = model.api, !playback.liking else { return }
        playback.liking = true
        defer { playback.liking = false }
        do {
            let interactions = try await (dislike ? api.dislike(post: post.id) : api.like(post: post.id))
            let newLike = interactions.contains("like")
            let newDislike = interactions.contains("dislike")
            playback.likeCount = max(0, playback.likeCount + (newLike ? 1 : 0) - (playback.liked ? 1 : 0))
            playback.dislikeCount = max(0, playback.dislikeCount + (newDislike ? 1 : 0) - (playback.disliked ? 1 : 0))
            playback.liked = newLike; playback.disliked = newDislike
        } catch { report(error) }
    }
    private func prepareDownload() async {
        guard let api = model.api, !playback.videoID.isEmpty else { return }
        playback.preparingDownload = true
        defer { playback.preparingDownload = false }
        do {
            let delivery = try await api.delivery(video: playback.videoID, scenario: "download")
            try Task.checkCancellation()
            playback.downloadQualities = delivery.qualities
            guard !playback.downloadQualities.isEmpty else { throw APIError.noVideo }
            playback.downloadError = nil
        } catch { if !Task.isCancelled { playback.downloadError = "Downloads are unavailable for this video." } }
    }
    @MainActor private func load() async {
        guard let api = model.api else {
            if model.demo, !playback.closed, let url = Bundle.main.url(forResource: "DemoPlayback", withExtension: "mp4") {
                model.claimPlayer(playback.player)
                playback.player.replaceCurrentItem(with: AVPlayerItem(url: url))
                playback.playerReady = true
                playback.player.play()
            }
            return
        }
        playback.loading = true; playback.error = nil
        defer { playback.loading = false }
        do {
            let detail = try await api.post(id: post.id)
            try Task.checkCancellation()
            playback.detail = detail
            playback.liked = detail.userInteraction?.contains("like") == true
            playback.disliked = detail.userInteraction?.contains("dislike") == true
            playback.likeCount = detail.likes ?? 0
            playback.dislikeCount = detail.dislikes ?? 0
            guard let first = detail.media.first(where: { $0.file.isAccessible != false }) else { return }
            if playback.selectedMediaID == first.id { await loadSelectedMedia() }
            else { playback.selectedMediaID = first.id }
        } catch { report(error) }
    }
    @MainActor private func loadSelectedMedia() async {
        guard let media = selectedMedia, let api = model.api else { return }
        playback.loadedMediaID = playback.selectedMediaID
        playback.player.pause()
        playback.player.replaceCurrentItem(with: nil)
        playback.qualities = []; playback.downloadQualities = []; playback.pictureURL = nil; playback.error = nil
        playback.playbackObservation = nil; playback.playbackGeneration = UUID(); playback.playerReady = false
        if media.isPlayable {
            playback.videoID = media.file.guid
            await loadDelivery()
            await prepareDownload()
        } else {
            playback.videoID = ""
            if media.kind == .picture {
                do {
                    let image = try await api.picture(id: media.id)
                    try Task.checkCancellation()
                    playback.pictureURL = image.originalURL
                    if let pictureURL = playback.pictureURL {
                        playback.downloadQualities = [.init(id: media.id, label: "Original image", url: pictureURL, order: 0)]
                    }
                } catch { report(error) }
            }
        }
    }
    @MainActor private func loadDelivery() async {
        guard let api = model.api else { return }
        playback.player.pause()
        playback.player.replaceCurrentItem(with: nil)
        playback.loading = true; playback.error = nil
        defer { playback.loading = false }
        do {
            let delivery = try await api.delivery(video: playback.videoID)
            try Task.checkCancellation()
            playback.qualities = delivery.qualities
            guard let first = playback.qualities.first else { throw APIError.noVideo }
            playback.qualityID = first.id
            play()
        } catch { report(error) }
    }
    @MainActor private func play() {
        guard !playback.closed, let quality = playback.qualities.first(where: { $0.id == playback.qualityID }) else { return }
        model.claimPlayer(playback.player)
        let time = playback.player.currentTime()
        let resume = playback.player.currentItem == nil || playback.player.rate != 0
        let cookies = model.cookie?.httpCookie.map { [$0] } ?? []
        let asset = AVURLAsset(url: quality.url, options: [AVURLAssetHTTPCookiesKey: cookies])
        let item = AVPlayerItem(asset: asset)
        playback.playerReady = false
        let generation = UUID()
        playback.playbackGeneration = generation
        playback.playbackObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            let ready = item.status == .readyToPlay
            let failed = item.status == .failed
            Task { @MainActor in
                guard playback.playbackGeneration == generation else { return }
                playback.playerReady = ready
                if failed { playback.error = "Video playback failed. Try another quality or reload the video." }
            }
        }
        playback.player.replaceCurrentItem(with: item)
        if time.isNumeric && time.seconds > 0 { playback.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) }
        playback.player.isMuted = ProcessInfo.processInfo.arguments.contains("--mute")
        if resume { playback.player.play() }
    }
    @MainActor private func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        playback.error = error.localizedDescription
        if error as? APIError == .signedOut { model.handle(error) }
    }
    // Display a plain native description without executing HTML from posts.
    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The top edge of scrolling content under the navigation chrome: hard while
/// reading, soft and hidden while a banner or player sits behind the chrome.
struct ReadingEdge: ViewModifier {
    let reading: Bool
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, iOS 26.0, *) {
                content.scrollEdgeEffectStyle(reading ? .hard : .soft, for: .top).scrollEdgeEffectHidden(!reading, for: .top)
            } else { content }
        }
        #if os(macOS)
        .mask {
            VStack(spacing: 0) {
                Rectangle().fill(reading ? .clear : .white).frame(height: 52)
                Rectangle().fill(.white)
            }
        }
        #endif
    }
}

private struct PlayerScrollTracking: ViewModifier {
    let playerHeight: CGFloat
    @Binding var scrolledAway: Bool
    func body(content: Content) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                playerHeight > 0 && geometry.visibleRect.minY > playerHeight - 52
            } action: { _, away in scrolledAway = away }
        } else {
            content.onPreferenceChange(PlayerBottomKey.self) { scrolledAway = $0 < 52 }
        }
    }
}

private struct PlayerBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PlayerChrome: ViewModifier {
    @Environment(AppModel.self) private var model
    var hideBack = true
    var title = ""
    var reading = false
    var immersive = false
    var rail = false
    func body(content: Content) -> some View {
        content.navigationBarBackButtonHidden(hideBack)
            #if os(macOS)
            .toolbar(model.windowFullscreen ? .hidden : .visible, for: .windowToolbar)
            .onAppear { model.immersiveVideo = immersive }
            .onChange(of: immersive) { _, value in model.immersiveVideo = value }
            .onDisappear { model.immersiveVideo = false }
            .toolbarBackground(reading ? .visible : .hidden, for: .windowToolbar)
            .navigationTitle(title)
            .modifier(ToolbarTitleVisibility(hidden: !reading))
            .ignoresSafeArea(.container, edges: hideBack ? .top : [])
            #else
            .navigationBarBackButtonHidden(rail)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(immersive && !rail ? .hidden : .visible, for: .navigationBar)
            // Keep inline iPhone video below the notch, even with navigation chrome hidden.
            .ignoresSafeArea(.container, edges: immersive && Device.isPad ? .top : [])

            #endif
    }
}

struct PlayerBackToolbar: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    let visible: Bool
    var nonVideo = false
    let action: () -> Void
    func body(content: Content) -> some View {
        #if os(macOS)
        content.toolbar {
            if !model.windowFullscreen {
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .navigation) { backButton }.sharedBackgroundVisibility(.hidden)
                } else { ToolbarItem(placement: .navigation) { backButton } }
            }
        }
        .overlay(alignment: .topLeading) {
            if model.windowFullscreen {
                fullscreenBackButton.padding(.leading, model.sidebarHidden ? 156 : 12).padding(.top, 8)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        #else
        content
        #endif
    }
    #if os(macOS)
    private var fullscreenBackButton: some View {
        NativeChromeButton(title: "Back", symbol: "chevron.left", action: action)
            .frame(width: 36, height: 36).modifier(BackControlSurface())
            .onHover { hovering = $0 }
            .opacity(visible || nonVideo || hovering ? 1 : 0)
            .allowsHitTesting(visible || nonVideo || hovering)
    }
    private var backButton: some View {
        Button("Back", systemImage: "chevron.left", action: action)
            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .modifier(BackControlSurface())
            .onHover { hovering = $0 }
            .opacity(visible || hovering ? 1 : 0).allowsHitTesting(visible || hovering)
    }
    #endif
}
#if os(macOS)
private struct BackControlSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular, in: Circle()) }
        else { content.background(.regularMaterial, in: Circle()) }
    }
}
#endif

private struct PostMetadataRow<Actions: View>: View {
    let creator: String
    let icon: URL?
    let date: Date?
    @ViewBuilder let actions: Actions
    @State private var width: CGFloat = 600
    var body: some View {
        Group {
            if width >= Breakpoint.inlinePostActions {
                HStack(spacing: 16) {
                    PostByline(creator: creator, icon: icon, date: date)
                    Spacer(minLength: 8)
                    actions
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    PostByline(creator: creator, icon: icon, date: date)
                    HStack { Spacer(); actions }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

private struct PostByline: View {
    let creator: String
    let icon: URL?
    let date: Date?
    var body: some View {
        HStack(spacing: 8) {
            CreatorAvatar(url: icon, size: 24)
            Text(creator).font(.subheadline.weight(.medium)).lineLimit(1)
            if let date {
                Text("·").foregroundStyle(.tertiary)
                Text(date, format: .dateTime.month(.abbreviated).day().year()).font(.subheadline).foregroundStyle(Color.primary.opacity(0.7))
            }
        }
    }
}

private struct PostDownloadMenu: View {
    let preparing: Bool
    let disabled: Bool
    let qualities: [Delivery.Quality]
    let download: (Delivery.Quality) -> Void
    var body: some View {
        Menu {
            ForEach(qualities) { quality in Button(quality.label) { download(quality) } }
        } label: {
            Label(preparing ? "Preparing download" : "Download", systemImage: "arrow.down.to.line").labelStyle(.iconOnly)
        }.menuIndicator(.hidden).menuStyle(.automatic).tint(.primary)
            #if os(macOS)
            .buttonStyle(.bordered)
            #else
            .buttonStyle(.plain).frame(width: 44, height: 44).contentShape(Rectangle())
            #endif
            .disabled(disabled || preparing || qualities.isEmpty).help("Download")
            .accessibilityLabel("Download")
    }
}

private struct PostFeedbackControl: View {
    let liked: Bool
    let disliked: Bool
    let likes: Int
    let dislikes: Int
    let disabled: Bool
    let like: () -> Void
    let dislike: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            FeedbackButton(symbol: liked ? "hand.thumbsup.fill" : "hand.thumbsup", count: likes, selected: liked, label: liked ? "Unlike post" : "Like post", action: like)
            Divider().frame(height: 14)
            FeedbackButton(symbol: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown", count: dislikes, selected: disliked, label: disliked ? "Remove dislike" : "Dislike post", action: dislike)
        }.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6)).disabled(disabled)
    }
}

private struct FeedbackButton: View {
    let symbol: String
    let count: Int
    let selected: Bool
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(count.formatted()).monospacedDigit()
            }.padding(.horizontal, 10).frame(height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selected ? Color.accentColor : .primary)
            .accessibilityLabel(label).accessibilityValue(count.formatted()).help(label)
    }
}

private struct AttachmentPicker: View {
    let media: [PostAttachment]
    @Binding var selection: String
    var body: some View {
        Picker("Media", selection: $selection) {
            ForEach(media) { attachment in
                Label(attachment.title, systemImage: attachment.symbol).tag(attachment.id).disabled(attachment.file.isAccessible == false)
            }
        }.frame(maxWidth: 300, alignment: .leading)
    }
}

private struct PostQualityPicker: View {
    let qualities: [Delivery.Quality]
    @Binding var qualityID: String
    var body: some View {
        if !qualities.isEmpty {
            Picker("Quality", selection: $qualityID) { ForEach(qualities) { Text($0.label).tag($0.id) } }
                .labelsHidden().fixedSize().tint(.primary).help("Video quality").accessibilityLabel("Video quality")
        }
    }
}

struct PostDescription: View {
    let text: String
    var collapsible = true
    @State private var expanded = false
    private var displayedText: String {
        collapsible && !expanded ? text.replacingOccurrences(of: "\\s*\\n\\s*", with: " ", options: .regularExpression) : text
    }
    private var linkedText: AttributedString {
        let text = displayedText
        var result = AttributedString(text)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: result), let url = match.url { result[range].link = url }
            }
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(linkedText).font(.body).foregroundStyle(.primary).lineLimit(!collapsible || expanded ? nil : 3).textSelection(.enabled)
            if collapsible && text.count > 240 {
                Button(expanded ? "Show less" : "Show more") { expanded.toggle() }.buttonStyle(.plain).font(.callout.weight(.medium))
            }
        }
    }
}

#if os(macOS)
struct ToolbarTitleVisibility: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: hidden ? .title : nil)
        } else { content }
    }
}

struct OverlayScrollerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.scheduleApply() }
    final class Probe: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleApply() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleApply() }
        func scheduleApply() {
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }
        func apply() {
            guard let scroll = enclosingScrollView else { return }
            if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
            if !scroll.autohidesScrollers { scroll.autohidesScrollers = true }
            if scroll.hasVerticalScroller { scroll.hasVerticalScroller = false }
            if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
        }
    }
}

struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    var onControlsVisibility: ((Bool) -> Void)? = nil
    var onPresentationChange: ((Bool) -> Void)? = nil
    var qualities: [Delivery.Quality] = []
    var qualityID: Binding<String>? = nil
    var backAction: (() -> Void)? = nil
    var windowChromeVisible: Bool? = nil
    var liveSource: URL? = nil
    func makeNSView(context: Context) -> AVPlayerView {
        let view = HoverPlayerView()
        view.setAccessibilityLabel("Video player")
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.onControlsVisibility = onControlsVisibility
        view.setWindowChromeVisible(windowChromeVisible ?? true)
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
        (view as? HoverPlayerView)?.onControlsVisibility = onControlsVisibility
        (view as? HoverPlayerView)?.setWindowChromeVisible(windowChromeVisible ?? true)
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        (view as? HoverPlayerView)?.stopChromeMonitoring()
        view.player = nil
    }

}
/// AVKit owns playback controls; windowed navigation follows pointer activity.
@MainActor private final class HoverPlayerView: AVPlayerView {
    var onControlsVisibility: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    private var hideTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private var keyObserver: NSObjectProtocol?
    private weak var styledWindow: NSWindow?
    private var windowChromeVisible = true
    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    if let self, let window = self.window,
                       event.window === window || event.window === window.standardWindowButton(.closeButton)?.window {
                        self.revealControls()
                    }
                }
                return event
            }
            keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                let keyWindow = note.object as? NSWindow
                MainActor.assumeIsolated {
                    if let self, keyWindow === self.window { self.revealControls() }
                }
            }
        }
        applyWindowChrome(animated: false)
        DispatchQueue.main.async { [weak self] in self?.revealControls() }
    }
    func setWindowChromeVisible(_ visible: Bool) {
        let changed = visible != windowChromeVisible || styledWindow !== window
        windowChromeVisible = visible
        if changed { applyWindowChrome(animated: true) }
        // SwiftUI can replace the native toolbar item while collapsing the sidebar.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.eventMonitor != nil else { return }
            self.applyWindowChrome(animated: false)
        }
    }
    private func applyWindowChrome(animated: Bool) {
        guard let window else { return }
        if let old = styledWindow, old !== window { Self.setChrome(in: old, visible: true, animated: false) }
        styledWindow = window
        Self.setChrome(in: window, visible: windowChromeVisible, animated: animated)
    }
    private static func setChrome(in window: NSWindow, visible: Bool, animated: Bool) {
        // Keep the native toggle and its layout; fade the enclosing system glass too.
        let sidebar = window.toolbar?.items.first { $0.itemIdentifier.rawValue == "com.apple.SwiftUI.navigationSplitView.toggleSidebar" }
        var sidebarSurface = sidebar?.view
        if #available(macOS 26.0, *) {
            var ancestor = sidebarSurface?.superview
            while let view = ancestor {
                if view is NSGlassEffectView { sidebarSurface = view; break }
                ancestor = view.superview
            }
        }
        let alpha: CGFloat = visible ? 1 : 0
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        let trafficLights: [NSView]
        if let group = buttons.first?.superview, window.contentView?.isDescendant(of: group) != true {
            // Fading individual buttons makes AppKit reclaim their toolbar space.
            trafficLights = [group]
        } else { trafficLights = buttons }
        let surfaces: [NSView] = trafficLights + (sidebarSurface.map { [$0] } ?? [])
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.15 : 0
            for view in surfaces where view.alphaValue != alpha {
                if animated { view.animator().alphaValue = alpha }
                else { view.alphaValue = alpha }
            }
        }
    }
    func stopChromeMonitoring() {
        hideTask?.cancel()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver); self.keyObserver = nil }
        if let styledWindow { Self.setChrome(in: styledWindow, visible: true, animated: false) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); revealControls() }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if let window, !NSRect(origin: .zero, size: window.frame.size).contains(event.locationInWindow) {
            hideTask?.cancel()
            setControlsVisible(false)
        }
    }
    private func setControlsVisible(_ visible: Bool) { onControlsVisibility?(visible) }
    private func revealControls() {
        hideTask?.cancel()
        setControlsVisible(true)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.setControlsVisible(false)
        }
    }
}

#endif

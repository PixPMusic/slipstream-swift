import SwiftUI
import AVKit

struct LiveLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Creator?
    private var streams: [Creator] { model.creators.filter { $0.liveStream != nil || $0.lastLiveStream != nil } }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 440), spacing: 20)], spacing: 24) {
                ForEach(streams) { creator in
                    if let stream = creator.liveStream ?? creator.lastLiveStream {
                        Button { selected = creator } label: {
                            PostCard(title: stream.title, creator: creator.title, thumbnail: stream.thumbnail?.url, duration: nil, date: nil, locked: false, demo: false)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(20)
        }
        .overlay { if streams.isEmpty { ContentUnavailableView("No streams", systemImage: "dot.radiowaves.left.and.right") } }
        .navigationTitle("Live")
        #if os(macOS)
        .toolbar(model.windowFullscreen ? .hidden : .visible, for: .windowToolbar)
        .onAppear { model.immersiveVideo = false }
        #endif
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.loadCreators() } } }
        .navigationDestination(item: $selected) { creator in
            if let stream = creator.liveStream ?? creator.lastLiveStream { LivePlayerView(creator: creator.title, creatorID: creator.id, stream: stream) }
        }
    }
}

struct LivePlayerView: View {
    @Environment(AppModel.self) private var model
    let creator: String
    let creatorID: String
    let stream: LiveStream
    @State private var player = AVPlayer()
    @State private var presentingFullscreen = false
    @State private var qualities: [Delivery.Quality] = []
    @State private var qualityID = ""
    @State private var error: String?
    @State private var loading = true
    @State private var archive: Post?
    @State private var recentPosts: [Post] = []
    @State private var selectedArchive: Post?
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 850
            let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                LiveVideoView(player: player, presentationChanged: { presentingFullscreen = $0 }, creator: creator, title: stream.title, thumbnail: stream.thumbnail?.url, qualities: qualities, qualityID: Binding(get: { qualityID }, set: { value in
                    guard value != qualityID else { return }
                    qualityID = value; play()
                }), loading: loading, error: error, archive: archive, recentPosts: recentPosts, playArchive: { selectedArchive = archive }, openPost: { selectedArchive = $0 }, retry: { Task { await load() } })
                    #if os(iOS)
                    .frame(height: wide ? nil : min(geometry.size.height * 0.52, geometry.size.width * 9 / 16 + 100))
                    #endif
                Divider()
                LiveChatView(streamID: stream.id, streamOffline: error != nil).frame(width: wide ? min(360, max(320, geometry.size.width * 0.34)) : nil).frame(minHeight: wide ? nil : 240)
            }
        }
        .modifier(PlayerChrome(title: creator, immersive: error == nil))
        .navigationDestination(item: $selectedArchive) { post in PlayerSheet(post: post) }
        .task { if !presentingFullscreen { await load() } }
        .onDisappear { if !presentingFullscreen { player.pause(); player.replaceCurrentItem(with: nil) } }
    }
    private func load() async {
        guard let api = model.api else { loading = false; return }
        loading = true; error = nil
        defer { loading = false }
        do {
            qualities = try await api.delivery(video: stream.id, scenario: "live").qualities
            try Task.checkCancellation()
            guard let first = qualities.first else { throw APIError.noVideo }
            qualityID = first.id
            play()
        } catch {
            if !Task.isCancelled {
                self.error = "This stream is offline or unavailable. Try again when it’s live."
                if archive == nil, let posts = try? await api.posts(creator: creatorID, offset: 0, search: stream.title) {
                    guard !Task.isCancelled else { return }
                    archive = posts.first { $0.isAccessible != false && $0.duration != nil && $0.title.localizedCaseInsensitiveContains(stream.title) }
                }
                if recentPosts.isEmpty, let posts = try? await api.posts(creator: creatorID) {
                    guard !Task.isCancelled else { return }
                    recentPosts = Array(posts.filter { $0.isAccessible != false && $0.duration != nil && $0.id != archive?.id }
                        .sorted { $0.releaseDate > $1.releaseDate }.prefix(4))
                }
            }
        }
    }
    private func play() {
        guard let quality = qualities.first(where: { $0.id == qualityID }) else { return }
        let cookies = model.cookie?.httpCookie.map { [$0] } ?? []
        let asset = AVURLAsset(url: quality.url, options: [AVURLAssetHTTPCookiesKey: cookies])
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        #if os(macOS)
        player.play()
        #endif
    }
}

private struct LiveVideoView: View {
    let player: AVPlayer
    let presentationChanged: (Bool) -> Void
    let creator: String
    let title: String
    let thumbnail: URL?
    let qualities: [Delivery.Quality]
    @Binding var qualityID: String
    let loading: Bool
    let error: String?
    let archive: Post?
    let recentPosts: [Post]
    let playArchive: () -> Void
    let openPost: (Post) -> Void
    let retry: () -> Void
    @State private var controlsVisible = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if error != nil {
                OfflineStreamView(creator: creator, title: title, thumbnail: thumbnail, archive: archive, recentPosts: recentPosts, checking: loading, playArchive: playArchive, openPost: openPost, retry: retry)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let source = qualities.first?.url {
                            NativeVideoPlayer(player: player, onControlsVisibility: { controlsVisible = $0 }, onPresentationChange: presentationChanged, qualities: qualities, qualityID: $qualityID, backAction: { dismiss() }, windowChromeVisible: controlsVisible || !model.sidebarHidden, liveSource: source)
                                .aspectRatio(16 / 9, contentMode: .fit).background(.black)
                        } else {
                            Color.black.aspectRatio(16 / 9, contentMode: .fit)
                                .overlay { if loading { ProgressView().tint(.white) } }
                        }
                        HStack {
                            Text(title).font(.title2.weight(.semibold))
                            Spacer()
                            #if os(macOS)
                            if !qualities.isEmpty {
                                Picker("Quality", selection: $qualityID) { ForEach(qualities) { Text($0.label).tag($0.id) } }.fixedSize()
                            }
                            #endif
                        }.padding(20)
                    }
                }.scrollIndicators(.hidden)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        .onChange(of: controlsVisible) { _, value in model.playerControlsVisible = value || error != nil }
        #endif
        .modifier(PlayerBackToolbar(visible: error != nil || controlsVisible, action: { dismiss() }))
    }
}


private struct OfflineStreamView: View {
    let creator: String
    let title: String
    let thumbnail: URL?
    let archive: Post?
    let recentPosts: [Post]
    let checking: Bool
    let playArchive: () -> Void
    let openPost: (Post) -> Void
    let retry: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PostArtwork(url: thumbnail)
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Label("Offline", systemImage: "video.slash").font(.callout.weight(.medium)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule()).environment(\.colorScheme, .dark)
                            .padding(20)
                    }
                VStack(alignment: .leading, spacing: 16) {
                    Text(title).font(.title2.weight(.semibold)).textSelection(.enabled)
                    HStack(spacing: 12) {
                        if let archive {
                            Button(action: playArchive) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text("Watch last stream")
                                    if let duration = archive.duration { Text(duration).font(.callout.monospacedDigit()).opacity(0.8) }
                                }
                            }.buttonStyle(.borderedProminent)
                        }
                        Button(checking ? "Checking…" : "Check live status", systemImage: "arrow.clockwise", action: retry)
                            .buttonStyle(.bordered).tint(.primary).disabled(checking)
                    }
                    if let text = archive?.text, !text.isEmpty { PostDescription(text: PlayerSheet.plainText(text)) }
                    if !recentPosts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent videos").font(.headline)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 18) {
                                ForEach(recentPosts) { post in
                                    FeedPostButton(post: post, creator: post.channel?.title ?? post.creator.title, demo: false, titleLines: 2) { openPost(post) }
                                }
                            }
                        }.padding(.top, 8)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.background {
                #if os(macOS)
                OverlayScrollerStyle()
                #endif
            }
        }.scrollIndicators(.hidden)
    }
}

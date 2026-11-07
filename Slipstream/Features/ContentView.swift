import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var compactPath: [String] = []
    #endif
    @State private var selection = "all"
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    var body: some View {
        @Bindable var model = model
        Group {
            if model.restoring {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.user != nil || model.demo {
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    NavigationStack(path: $compactPath) {
                        LibrarySidebar(selection: sidebarSelection, navigate: { compactPath = [$0] })
                            .navigationDestination(for: String.self) { value in
                                LibraryDestination(selection: value)
                            }
                    }
                } else { splitLibrary }
                #else
                splitLibrary
                #endif
            } else { WelcomeView() }
        }
        #if os(iOS)
        .onChange(of: horizontalSizeClass) { _, sizeClass in
            if sizeClass == .compact { compactPath = [selection] }
        }
        #endif
        #if os(macOS)
        .background {
            WindowFullscreenObserver { fullscreen in
                if model.windowFullscreen != fullscreen { model.windowFullscreen = fullscreen }
            }
        }
        .overlay(alignment: .topLeading) {
            if model.windowFullscreen {
                FullscreenSidebarControls(width: model.sidebarHidden ? 144 : model.sidebarWidth,
                                          visible: !model.immersiveVideo || !model.sidebarHidden || model.playerControlsVisible,
                                          sidebarHidden: model.sidebarHidden) {
                    columnVisibility = model.sidebarHidden ? .all : .detailOnly
                }
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        #endif
        .sheet(isPresented: $model.showLogin) { LoginSheet().environment(model) }
        .alert("Slipstream", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    // List clears its optional selection when a compact destination is pushed.
    // Keep the active feed so expanding back to two columns restores it.
    private var sidebarSelection: Binding<String?> {
        Binding(get: { selection }, set: { if let value = $0 { selection = value } })
    }

    private var splitLibrary: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar(selection: sidebarSelection)
        } detail: {
            NavigationStack {
                LibraryDestination(selection: selection)
            }.id(selection)
        }
        .onChange(of: columnVisibility) { _, value in model.sidebarHidden = value == .detailOnly }
        #if os(iOS)
        .onChange(of: model.sidebarHidden) { _, hidden in
            let visibility: NavigationSplitViewVisibility = hidden ? .detailOnly : .all
            if columnVisibility != visibility { columnVisibility = visibility }
        }
        #endif
    }
}

private struct LibraryDestination: View {
    @Environment(AppModel.self) private var model
    let selection: String

    var body: some View {
        if selection == "live" { LiveLibraryView() }
        else {
            let channel = model.channelsByID[selection]
            FeedView(creatorID: channel?.creator ?? (selection == "all" ? nil : selection), channel: channel)
                .id("\(model.user?.id ?? "demo")-\(selection)")
        }
    }
}

#if os(macOS)
private struct WindowFullscreenObserver: NSViewRepresentable {
    let changed: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed; view.publish() }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stop() }
    final class Probe: NSView {
        var changed: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private weak var toolbarWindow: NSWindow?
        private var toolbarIgnoredMouseEvents = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.publish() }
                })
            }
            publish()
        }
        func publish() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                let fullscreen = window.styleMask.contains(.fullScreen)
                self.changed?(fullscreen)
                if fullscreen, let toolbar = window.standardWindowButton(.closeButton)?.window, toolbar !== window {
                    if self.toolbarWindow !== toolbar {
                        self.restoreToolbarMouseEvents()
                        self.toolbarWindow = toolbar
                        self.toolbarIgnoredMouseEvents = toolbar.ignoresMouseEvents
                    }
                    // Hidden AppKit fullscreen toolbars still own a transparent window over this area.
                    // Our native controls live in the content window underneath it.
                    if !toolbar.ignoresMouseEvents { toolbar.ignoresMouseEvents = true }
                } else { self.restoreToolbarMouseEvents() }
            }
        }
        private func restoreToolbarMouseEvents() {
            toolbarWindow?.ignoresMouseEvents = toolbarIgnoredMouseEvents
            toolbarWindow = nil
        }
        func stop() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            restoreToolbarMouseEvents()
        }
    }
}
private struct FullscreenSidebarControls: View {
    let width: CGFloat
    let visible: Bool
    let sidebarHidden: Bool
    let toggle: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            FullscreenWindowButtons().frame(width: 60, height: 16)
            Spacer(minLength: 0)
            if #available(macOS 26.0, *) {
                NativeChromeButton(title: sidebarHidden ? "Show Sidebar" : "Hide Sidebar", symbol: "sidebar.left", action: toggle)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: Circle())
            } else {
                NativeChromeButton(title: sidebarHidden ? "Show Sidebar" : "Hide Sidebar", symbol: "sidebar.left", action: toggle)
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: Circle())
            }
        }.padding(.horizontal, 12).frame(width: width, height: 52)
            .opacity(visible ? 1 : 0).allowsHitTesting(visible)
    }
}
/// AppKit controls opt out of the draggable region above a fullscreen SwiftUI view.
struct NativeChromeButton: NSViewRepresentable {
    let title: String
    let symbol: String
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> Control {
        let button = Control(frame: .zero)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.press)
        return button
    }
    func updateNSView(_ button: Control, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        button.setAccessibilityLabel(title)
        button.contentTintColor = .labelColor
    }
    final class Control: NSButton {
        override var mouseDownCanMoveWindow: Bool { false }
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}

/// Native AppKit window buttons, hosted over the sidebar when the fullscreen toolbar is absent.
private struct FullscreenWindowButtons: NSViewRepresentable {
    func makeNSView(context: Context) -> Buttons { Buttons() }
    func updateNSView(_ view: Buttons, context: Context) {}
    final class Buttons: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let button = NSWindow.standardWindowButton(type, for: [.titled, .closable, .miniaturizable, .resizable, .fullScreen]) else { continue }
                button.setFrameOrigin(NSPoint(x: index * 22, y: 1))
                button.target = self
                button.action = type == .closeButton ? #selector(closeWindow) : #selector(exitFullscreen)
                button.isEnabled = type != .miniaturizeButton
                button.setAccessibilityLabel(type == .closeButton ? "Close" : type == .zoomButton ? "Exit Full Screen" : "Minimize")
                addSubview(button)
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func closeWindow() { window?.performClose(nil) }
        @objc private func exitFullscreen() { window?.toggleFullScreen(nil) }
    }
}
#endif

private struct LibrarySidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?
    var navigate: ((String) -> Void)? = nil
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                SidebarRow(value: "all", selection: $selection, navigate: navigate) {
                    Label("Library", systemImage: "play.rectangle.on.rectangle")
                }.tag("all")
                SidebarRow(value: "live", selection: $selection, navigate: navigate) {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }.tag("live")
                Section {
                    ForEach(model.creators) { creator in
                        CreatorSidebarBranch(creator: creator, channels: model.channelsByCreator[creator.id] ?? [], selection: $selection, navigate: navigate)
                    }
                } header: { Text("Creators").foregroundStyle(Color.primary.opacity(0.7)) }
            }
            .listStyle(.sidebar)
            .labelStyle(.titleAndIcon)
            .clipped()
            AccountFooter()
                #if os(iOS)
                .padding(.bottom, 16)
                #endif
        }
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .bottom)
        #endif
        .navigationTitle("Slipstream")
        .frame(minWidth: 240)
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        #if os(macOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.sidebarWidth = $0 }
        #endif
    }
}

private struct CreatorSidebarBranch: View {
    let creator: Creator
    let channels: [CreatorChannel]
    @Binding var selection: String?
    var navigate: ((String) -> Void)? = nil
    @State private var expanded = true
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(channels) { channel in
                SidebarRow(value: channel.id, selection: $selection, navigate: navigate) {
                    Label {
                        Text(channel.title).lineLimit(1)
                    } icon: { CreatorAvatar(url: channel.icon?.url, size: 20) }
                }.tag(channel.id)
            }
        } label: {
            SidebarRow(value: creator.id, selection: $selection, navigate: navigate) {
                Label { Text(creator.title) } icon: { CreatorAvatar(url: creator.icon?.url, size: 22) }
            }.tag(creator.id)
        }
    }
}

private struct SidebarRow<Label: View>: View {
    let value: String
    @Binding var selection: String?
    let navigate: ((String) -> Void)?
    @ViewBuilder var label: () -> Label

    var body: some View {
        if let navigate {
            Button { selection = value; navigate(value) } label: { label() }
        } else {
            NavigationLink(value: value) { label() }
        }
    }
}

private struct AccountFooter: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                CreatorAvatar(url: model.user?.profileImage?.url, size: 28)
                Text(model.demo ? "Demo" : model.user?.username ?? "Floatplane")
                    .font(.subheadline.weight(.semibold)).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 4)
                Menu {
                    Button(model.demo ? "Leave demo" : "Sign out") { Task { await model.signOut() } }
                } label: { Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.white).frame(width: 20, height: 24) }
                    .menuStyle(.automatic).buttonStyle(.borderless).menuIndicator(.hidden).tint(.white).frame(width: 24, height: 28).accessibilityLabel("Account options")
            }.padding(14)
        }
    }
}

struct CreatorAvatar: View {
    let url: URL?
    var size: CGFloat = 24
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() }
        placeholder: { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "water.waves").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Slipstream").font(.largeTitle.weight(.semibold))
            if model.needsKeychainApproval {
                Button("Restore saved sign-in") { Task { await model.restore(allowKeychainUI: true) } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Button("Sign in to Floatplane") { model.showLogin = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Try Demo") { model.demo = true; model.creators = DemoData.creators }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeedView: View {
    @Environment(AppModel.self) private var model
    let creatorID: String?
    var channel: CreatorChannel? = nil
    @State private var posts: [Post] = []
    @State private var offsets: [String: Int] = [:]
    @State private var exhausted: Set<String> = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    @State private var requestID = UUID()
    @State private var selected: Post?
    @State private var feedWidth: CGFloat = 0
    @State private var bannerHeight: CGFloat = 0
    @State private var bannerScrolledAway = false
    private var creators: [Creator] { model.creators.filter { creatorID == nil || $0.id == creatorID } }
    private var title: String { channel?.title ?? creatorID.flatMap { id in model.creators.first { $0.id == id }?.title } ?? "Library" }
    private var gridColumns: [GridItem] {
        let available = max(0, feedWidth - 40)
        #if os(iOS)
        let count = max(1, Int((available + 12) / 252))
        #else
        let count = available >= 440 ? max(2, Int((available + 12) / 280)) : 1
        #endif
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: count)
    }
    private var banner: FPImage? { channel?.cover ?? creators.first.flatMap { creatorID == nil ? nil : $0.cover } }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let banner, let url = banner.url {
                    ChannelBanner(url: url, aspectRatio: banner.width.flatMap { width in banner.height.map { CGFloat(width) / CGFloat(max(1, $0)) } } ?? 3.83)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bannerHeight = $0 }
                }
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                    ForEach(posts) { post in
                        FeedPostButton(post: post, creator: channel == nil ? (post.channel?.title ?? post.channel.flatMap { model.channelsByID[$0.id]?.title } ?? post.creator.title) : nil, demo: model.demo, titleLines: cardTitleLines) { selected = post }
                    }
                }.padding(20)
                if loading { ProgressView().padding(24) }
                else if !posts.isEmpty && !model.demo && creators.contains(where: { !exhausted.contains($0.id) }) {
                    Button("Load more") { Task { await load(reset: false) } }.padding(.bottom, 24)
                }
            }.background {
                #if os(macOS)
                OverlayScrollerStyle()
                #endif
            }
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { feedWidth = $0 }
        .coordinateSpace(name: "feedScroll")
        .overlay {
            if let error {
                ContentUnavailableView {
                    Label("Couldn’t load posts", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: { Button("Try again") { Task { await load(reset: true) } } }
            } else if posts.isEmpty && !loading {
                ContentUnavailableView(search.isEmpty ? "No posts" : "No results", systemImage: "play.rectangle")
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(FeedSearch(text: $search, width: feedWidth < 700 ? 160 : 240, refresh: {
            Task { await model.loadCreators(); await load(reset: true) }
        }))
        .task(id: [search, channel?.id ?? ""] + creators.map(\.id)) {
            do {
                if !search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                await load(reset: true)
            } catch {}
        }
        .navigationDestination(item: $selected) { post in PlayerSheet(post: post) }
        .refreshable { await load(reset: true) }
        .modifier(ReadingContentClip(reading: banner != nil && bannerScrolledAway))
        .modifier(ReadingScrollEdge(reading: banner != nil && bannerScrolledAway))
        .modifier(FeedBannerChrome(title: title, enabled: banner != nil, bannerHeight: bannerHeight, scrolledAway: $bannerScrolledAway))
    }
    private var cardTitleLines: Int {
        #if os(iOS)
        2
        #else
        feedWidth < 700 ? 3 : 2
        #endif
    }
    @MainActor private func load(reset: Bool) async {
        if model.demo {
            posts = DemoData.posts.filter { (creatorID == nil || $0.creator.id == creatorID) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
            return
        }
        guard let api = model.api else { return }
        let currentRequest = UUID()
        requestID = currentRequest
        loading = true
        error = nil
        defer { if requestID == currentRequest { loading = false } }
        var nextOffsets = reset ? [:] : offsets
        var nextExhausted: Set<String> = reset ? [] : exhausted
        if reset { posts = [] }
        do {
            var next = posts
            for creator in creators where !nextExhausted.contains(creator.id) {
                let batch = try await api.posts(creator: creator.id, channel: channel?.id, offset: nextOffsets[creator.id] ?? 0, search: search)
                try Task.checkCancellation()
                guard requestID == currentRequest else { return }
                nextOffsets[creator.id, default: 0] += batch.count
                if batch.count < 20 { nextExhausted.insert(creator.id) }
                next.append(contentsOf: batch)
            }
            guard requestID == currentRequest else { return }
            offsets = nextOffsets
            exhausted = nextExhausted
            var seen = Set<String>()
            posts = next.filter { seen.insert($0.id).inserted }.sorted { $0.releaseDate > $1.releaseDate }
        } catch is CancellationError {} catch let e as URLError where e.code == .cancelled {} catch {
            guard requestID == currentRequest else { return }
            self.error = error.localizedDescription
            if error as? APIError == .signedOut { model.handle(error) }
        }
    }}

struct FeedPostButton: View {
    let post: Post
    let creator: String?
    let demo: Bool
    let titleLines: Int
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            PostCard(title: post.title, creator: creator, thumbnail: post.thumbnail?.url,
                     duration: post.duration, date: post.date, text: post.text, locked: post.isAccessible == false, demo: demo, titleLines: titleLines)
        }
        .buttonStyle(.plain).disabled(post.isAccessible == false)
        .accessibilityLabel(Text(post.title))
    }
}

struct PostCard: View {
    let title: String
    let creator: String?
    let thumbnail: URL?
    let duration: String?
    let date: Date?
    var text: String? = nil
    let locked: Bool
    let demo: Bool
    var titleLines = 2
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostArtwork(url: thumbnail, demo: demo, text: text)
                .overlay(alignment: .bottomTrailing) {
                    if locked { Image(systemName: "lock.fill").padding(6).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.white).padding(8) }
                    else if let duration {
                        Text(duration).font(.caption.monospacedDigit().weight(.medium)).padding(.horizontal, 5).padding(.vertical, 3)
                            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.white).padding(8)
                    }
                }
            Text(title).font(.body.weight(.medium)).lineLimit(titleLines, reservesSpace: true).foregroundStyle(.primary).help(title)
            HStack(spacing: 6) {
                if let creator { Text(creator).lineLimit(1) }
                if let date {
                    if creator != nil { Text("·") }
                    Text(date, format: .dateTime.month(.abbreviated).day()).fixedSize()
                }
            }.font(.subheadline).foregroundStyle(Color.primary.opacity(0.7))
        }
        .padding(6)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .modifier(ThumbnailHover(url: thumbnail))
    }
}

struct PostArtwork: View {
    let url: URL?
    var demo = false
    var text: String? = nil
    var body: some View {
        Rectangle().fill(url == nil && text != nil ? Color.primary.opacity(0.035) : Color.secondary.opacity(0.08))
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let url {
                    GeometryReader { geometry in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure:
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.exclamationmark").font(.title2)
                                    Text("Image unavailable").font(.caption)
                                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                            case .empty:
                                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                            @unknown default: Color.clear
                            }
                        }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                } else if let text {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "text.quote").font(.title3).foregroundStyle(.secondary)
                        Text(PlayerSheet.plainText(text)).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(4)
                    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ChannelBanner: View {
    let url: URL
    let aspectRatio: CGFloat
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Color.secondary.opacity(0.08) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .aspectRatio(max(2.8, min(4.5, aspectRatio)), contentMode: .fit)
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.30), .clear], startPoint: .top, endPoint: .bottom).frame(height: 100)
        }
        .accessibilityHidden(true)
    }
}

private struct FeedBannerChrome: ViewModifier {
    let title: String
    @Environment(AppModel.self) private var model
    let enabled: Bool
    let bannerHeight: CGFloat
    @Binding var scrolledAway: Bool
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 15.0, iOS 18.0, *) {
                content.onScrollGeometryChange(for: Bool.self) { geometry in
                    enabled && bannerHeight > 0 && geometry.visibleRect.minY > bannerHeight - 52
                } action: { _, away in scrolledAway = away }
            } else { content }
        }
        #if os(macOS)
        .ignoresSafeArea(.container, edges: enabled || model.windowFullscreen ? .top : [])
        .toolbar(model.windowFullscreen ? .hidden : .visible, for: .windowToolbar)
        .toolbarBackground(enabled && !scrolledAway ? .hidden : .visible, for: .windowToolbar)
        .modifier(ToolbarTitleVisibility(hidden: enabled && !scrolledAway))
        #else
        .ignoresSafeArea(.container, edges: enabled ? .top : [])
        .toolbarBackground(enabled && !scrolledAway ? .hidden : .automatic, for: .navigationBar)
        .navigationTitle(enabled && !scrolledAway ? "" : title)
        .toolbar {
            if enabled && !scrolledAway {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            }
        }
        #endif
    }
}

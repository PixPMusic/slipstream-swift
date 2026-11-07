#if os(iOS)
import SwiftUI
import AVKit
import Observation
@preconcurrency import AmazonIVSPlayer

/// One playback session shared by the inline and fullscreen surfaces.
@MainActor @Observable private final class TouchPlayback: NSObject, @preconcurrency IVSPlayer.Delegate {
    let player: AVPlayer
    @ObservationIgnored let live: IVSPlayer?
    @ObservationIgnored private let liveSource: URL?
    @ObservationIgnored private var routeObservation: NSObjectProtocol?
    var casting = false
    var playbackError: String?
    var time = 0.0
    var duration = 0.0
    var playing = false
    var visible = true
    var scrubbing = false
    var interacting = false
    var muted = false
    var speed: Float = 1
    var subtitleGroup: AVMediaSelectionGroup?
    var subtitle: AVMediaSelectionOption?
    var qualities: [Delivery.Quality] = []
    var qualityID = ""
    var selectQuality: ((String) -> Void)?
    var back: (() -> Void)?
    var sidebarHidden = false
    var revealSidebar: (() -> Void)?
    var visibilityChanged: ((Bool) -> Void)?
    var presentationChanged: ((Bool) -> Void)?
    @ObservationIgnored private var tick: Any?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var mediaTask: Task<Void, Never>?
    @ObservationIgnored private var status: NSKeyValueObservation?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(player: AVPlayer, liveSource: URL? = nil) {
        self.player = player
        self.liveSource = liveSource
        live = liveSource == nil ? nil : IVSPlayer()
        super.init()
        if let live, let liveSource {
            live.delegate = self
            live.load(liveSource)
            live.play()
            routeObservation = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateAirPlayRoute() }
            }
            status = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let playing = player.timeControlStatus != .paused
                Task { @MainActor [weak self] in
                    guard let self, self.casting else { return }
                    self.playing = playing; self.reveal()
                }
            }
            return
        }
        muted = player.isMuted
        playing = player.rate != 0
        tick = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.scrubbing { self.time = time.seconds.isFinite ? time.seconds : 0 }
                let length = self.player.currentItem?.duration.seconds ?? 0
                self.duration = length.isFinite ? max(0, length) : 0
            }
        }
        itemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.loadSubtitles() }
        }
        status = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor [weak self] in self?.playing = playing; self?.reveal() }
        }
    }
    private func loadSubtitles() {
        mediaTask?.cancel(); subtitleGroup = nil; subtitle = nil
        guard let item = player.currentItem else { return }
        mediaTask = Task { [weak self] in
            let group = try? await item.asset.loadMediaSelectionGroup(for: .legible)
            guard !Task.isCancelled, let self, self.player.currentItem === item else { return }
            self.subtitleGroup = group
            if let group { self.subtitle = item.currentMediaSelection.selectedMediaOption(in: group) }
        }
    }
    func selectSubtitle(_ option: AVMediaSelectionOption?) {
        guard let subtitleGroup else { return }
        player.currentItem?.select(option, in: subtitleGroup); subtitle = option; reveal()
    }
    func changeSpeed(_ value: Float) {
        speed = value; player.defaultRate = value
        if let live, !casting { live.playbackRate = value }
        else if playing { player.rate = value }
        reveal()
    }
    func reveal() {
        setVisible(true)
        hideTask?.cancel()
        guard playing, !scrubbing, !interacting else { return }
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.setVisible(false)
        }
    }
    func setVisible(_ value: Bool) { visible = value; visibilityChanged?(value) }
    func toggle() {
        if let live, !casting { playing ? live.pause() : live.play() }
        else { playing ? player.pause() : player.play() }
        reveal()
    }
    func toggleMute() {
        muted.toggle(); player.isMuted = muted; live?.muted = muted; reveal()
    }
    func seek(_ seconds: Double) {
        guard live == nil else { return }
        let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, seconds))
        time = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        reveal()
    }
    func stopObserving() {
        hideTask?.cancel(); mediaTask?.cancel(); status = nil; itemObservation = nil
        if let tick { player.removeTimeObserver(tick); self.tick = nil }
        live?.pause(); live?.delegate = nil
        if let routeObservation { NotificationCenter.default.removeObserver(routeObservation); self.routeObservation = nil }
    }

    func player(_ player: IVSPlayer, didChangeState state: IVSPlayer.State) {
        guard !casting else { return }
        playing = state == .playing || state == .buffering
        if state == .ready, let liveSource {
            qualities = [Delivery.Quality(id: "auto", label: "Auto", url: liveSource, order: .max)] + player.qualities.enumerated().map { index, quality in
                Delivery.Quality(id: String(index), label: quality.name, url: liveSource, order: player.qualities.count - index)
            }
        }
        reveal()
    }
    func player(_ player: IVSPlayer, didFailWithError error: Error) {
        playing = false; playbackError = "Live playback interrupted."; reveal()
    }
    func selectLiveQuality(_ id: String) {
        guard let live, id != qualityID else { return }
        if id == "auto" { live.quality = nil }
        else if let index = Int(id), live.qualities.indices.contains(index) {
            live.setQuality(live.qualities[index], adaptive: true)
        } else { return }
        qualityID = id; reveal()
    }
    func retryLive() {
        guard let live, let liveSource else { return }
        playbackError = nil; live.load(liveSource); live.play(); reveal()
    }
    func updateAirPlayRoute() {
        guard let live else { return }
        let external = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
        guard casting != external else { return }
        casting = external
        if external { live.pause(); if playing { player.play() } }
        else { player.pause(); if playing { live.play() } }
        reveal()
    }
}

struct NativeVideoPlayer: UIViewControllerRepresentable {
    @Environment(AppModel.self) private var model
    let player: AVPlayer
    var onControlsVisibility: ((Bool) -> Void)? = nil
    var onPresentationChange: ((Bool) -> Void)? = nil
    var qualities: [Delivery.Quality] = []
    var qualityID: Binding<String>? = nil
    var backAction: (() -> Void)? = nil
    var windowChromeVisible: Bool? = nil
    var liveSource: URL? = nil

    func makeUIViewController(context: Context) -> TouchPlayerController {
        let session = TouchPlayback(player: player, liveSource: liveSource)
        configure(session)
        return TouchPlayerController(session: session)
    }
    func updateUIViewController(_ controller: TouchPlayerController, context: Context) { configure(controller.session) }
    private func configure(_ session: TouchPlayback) {
        if session.live == nil {
            session.qualities = qualities
            session.qualityID = qualityID?.wrappedValue ?? ""
            session.selectQuality = { [weak session] id in session?.qualityID = id; qualityID?.wrappedValue = id }
        } else {
            if session.qualityID.isEmpty { session.qualityID = "auto" }
            session.selectQuality = { [weak session] id in session?.selectLiveQuality(id) }
        }
        session.back = backAction
        session.sidebarHidden = model.sidebarHidden
        session.revealSidebar = { model.sidebarHidden = false }
        session.visibilityChanged = onControlsVisibility
        session.presentationChanged = onPresentationChange
    }
    static func dismantleUIViewController(_ controller: TouchPlayerController, coordinator: ()) {
        if controller.presentedViewController == nil { controller.session.stopObserving() }
    }
}

private final class PlaybackSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

@MainActor final class TouchPlayerController: UIViewController, @preconcurrency AVPictureInPictureControllerDelegate, @preconcurrency UIViewControllerTransitioningDelegate {
    fileprivate let session: TouchPlayback
    private let fullscreen: Bool
    private let surface = PlaybackSurface()
    private var liveSurface: IVSPlayerView?
    private var pip: AVPictureInPictureController?
    private var controls: UIHostingController<TouchPlayerControls>?
    private var closing = false
    private var inlineFrame = CGRect.zero
    private var controlArea: UILayoutGuide?
    private weak var controlWindow: UIWindow?

    fileprivate init(session: TouchPlayback, fullscreen: Bool = false) {
        self.session = session; self.fullscreen = fullscreen
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var prefersStatusBarHidden: Bool { fullscreen }
    override var prefersHomeIndicatorAutoHidden: Bool { fullscreen && !session.visible }
    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
        view.backgroundColor = .black
        if let live = session.live {
            let liveView = IVSPlayerView(frame: view.bounds)
            liveView.player = live
            liveView.videoGravity = .resizeAspect
            liveView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(liveView); liveSurface = liveView
        } else {
            surface.playerLayer.player = session.player
            surface.playerLayer.videoGravity = .resizeAspect
            surface.frame = view.bounds
            surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(surface)
        }
        if AVPictureInPictureController.isPictureInPictureSupported() {
            if let liveSurface { pip = AVPictureInPictureController(ivsPlayerLayer: liveSurface.playerLayer) }
            else { pip = AVPictureInPictureController(playerLayer: surface.playerLayer) }
            pip?.delegate = self
        }
        let controls = UIHostingController(rootView: TouchPlayerControls(session: session, fullscreen: fullscreen, canPiP: pip != nil,
            close: { [weak self] in self?.goBack() }, expand: { [weak self] in self?.toggleFullscreen() },
            pictureInPicture: { [weak self] in self?.togglePiP() }))
        self.controls = controls
        addChild(controls)
        // Insets are applied once, in player coordinates, below.
        controls.safeAreaRegions = []
        controls.view.backgroundColor = .clear
        controls.view.frame = view.bounds
        controls.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controls.view)
        controls.didMove(toParent: self)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let window = view.window else { return }
        if #available(iOS 26, *), controlWindow !== window {
            controlWindow = window
            controlArea = window.layoutGuide(for: .margins(cornerAdaptation: .horizontal))
        }
        // The video fills the view; only the chrome stays inside its safe area.
        // Window corner margins can be very large on a folded phone, so reserve
        // those only for the inline iPad window controls that need them.
        let safe = view.safeAreaInsets
        let windowMargin = !fullscreen && traitCollection.userInterfaceIdiom == .pad
            ? controlArea.map { view.convert($0.layoutFrame, from: window).minX } ?? 0 : 0
        let insets = EdgeInsets(top: max(12, safe.top + 8),
                                leading: max(16, safe.left + 12, windowMargin),
                                bottom: max(12, safe.bottom + 8),
                                trailing: max(16, safe.right + 12))
        if controls?.rootView.insets != insets { controls?.rootView.insets = insets }
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); session.reveal() }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        liveSurface?.player = session.live
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        liveSurface?.player = nil
    }
    private func goBack() { fullscreen ? leaveFullscreen() : session.back?() }
    private func toggleFullscreen() {
        if fullscreen { leaveFullscreen(); return }
        guard presentedViewController == nil else { return }
        session.presentationChanged?(true)
        inlineFrame = view.convert(view.bounds, to: view.window)
        let expanded = TouchPlayerController(session: session, fullscreen: true)
        expanded.transitioningDelegate = self
        present(expanded, animated: true)
    }
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed || gesture.state == .ended else { return }
        if !fullscreen && gesture.scale > 1.15 { toggleFullscreen() }
        else if fullscreen && gesture.scale < 0.85 { leaveFullscreen() }
    }
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        PlayerExpansionTransition(inlineFrame: inlineFrame, expanding: true)
    }
    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        let frame = view.window != nil ? view.convert(view.bounds, to: view.window) : inlineFrame
        return PlayerExpansionTransition(inlineFrame: frame, expanding: false)
    }
    private func leaveFullscreen() {
        guard !closing else { return }; closing = true
        dismiss(animated: true) { [session] in session.presentationChanged?(false); session.reveal() }
    }
    private func togglePiP() {
        guard let pip else { return }
        pip.isPictureInPictureActive ? pip.stopPictureInPicture() : pip.startPictureInPicture()
        session.reveal()
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(true) }
}

/// Animate the live video surface from its inline rectangle, rather than using a sheet slide.
@MainActor private final class PlayerExpansionTransition: NSObject, @preconcurrency UIViewControllerAnimatedTransitioning {
    let inlineFrame: CGRect
    let expanding: Bool
    init(inlineFrame: CGRect, expanding: Bool) { self.inlineFrame = inlineFrame; self.expanding = expanding }
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.35
    }
    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        let container = context.containerView
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let destination = context.viewController(forKey: .to) else { context.completeTransition(false); return }
        let rect = container.convert(inlineFrame, from: container.window)
        let moving = expanding ? to : from
        if expanding {
            container.addSubview(to)
            to.frame = rect
        } else {
            to.frame = context.finalFrame(for: destination)
            container.insertSubview(to, belowSubview: from)
        }
        moving.layoutIfNeeded()
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        if reducedMotion && expanding { moving.frame = context.finalFrame(for: destination); moving.alpha = 0 }
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: [.curveEaseInOut]) {
            if reducedMotion { moving.alpha = self.expanding ? 1 : 0 }
            else { moving.frame = self.expanding ? context.finalFrame(for: destination) : rect }
            moving.layoutIfNeeded()
        } completion: { _ in
            moving.alpha = 1
            if !self.expanding && !context.transitionWasCancelled { from.removeFromSuperview() }
            context.completeTransition(!context.transitionWasCancelled)
        }
    }
}

private struct TouchPlayerControls: View {
    var insets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    @Bindable var session: TouchPlayback
    let fullscreen: Bool
    let canPiP: Bool
    let close: () -> Void
    let expand: () -> Void
    let pictureInPicture: () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var seekDirection = 0
    @State private var seekGeneration = 0
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - insets.leading - insets.trailing
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 2, coordinateSpace: .local) { point in
                        guard session.live == nil else { session.reveal(); return }
                        seekDirection = point.x < geometry.size.width / 2 ? -1 : 1
                        seekGeneration += 1
                        session.seek(session.time + Double(seekDirection * 15))
                    }
                    .onTapGesture {
                        if session.visible { session.setVisible(false) } else { session.reveal() }
                    }
                    .accessibilityLabel("Video").accessibilityAction { session.reveal() }
                    .accessibilityAction(named: Text("Back 15 seconds")) { session.seek(session.time - 15) }
                    .accessibilityAction(named: Text("Forward 15 seconds")) { session.seek(session.time + 15) }
                if seekDirection != 0 {
                    HStack {
                        if seekDirection > 0 { Spacer() }
                        Label(seekDirection > 0 ? "+15s" : "−15s", systemImage: seekDirection > 0 ? "goforward.15" : "gobackward.15")
                            .font(.headline).padding(12).modifier(TouchGlassSurface())
                        if seekDirection < 0 { Spacer() }
                    }.padding(.horizontal, 24).allowsHitTesting(false).accessibilityHidden(true)
                }
                if let error = session.playbackError {
                    VStack(spacing: 12) {
                        Text(error)
                        Button("Try again") { session.retryLive() }.buttonStyle(.bordered)
                    }.padding(20).modifier(TouchGlassSurface())
                }
                VStack {
                    HStack {
                        if !fullscreen && session.sidebarHidden && UIDevice.current.userInterfaceIdiom == .pad {
                            TouchPlayerButton(title: "Show Sidebar", symbol: "sidebar.left") {
                                session.revealSidebar?(); session.reveal()
                            }
                        }
                        TouchPlayerButton(title: fullscreen ? "Exit fullscreen" : "Back", symbol: fullscreen ? "xmark" : "chevron.left", action: close)
                        Spacer()
                        TouchPlayerButton(title: session.muted ? "Unmute" : "Mute", symbol: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                            session.toggleMute()
                        }
                    }
                    Spacer()
                    TouchTransportBar(session: session, fullscreen: fullscreen, canPiP: canPiP, compact: availableWidth < 900, showTotalTime: availableWidth >= 380, expand: expand, pictureInPicture: pictureInPicture)
                }
                .padding(insets)
                .opacity(session.visible || voiceOver ? 1 : 0)
                .allowsHitTesting(session.visible || voiceOver)
                .accessibilityHidden(!session.visible && !voiceOver)
            }.foregroundStyle(.white).environment(\.colorScheme, .dark)
                .task(id: seekGeneration) {
                    guard seekDirection != 0 else { return }
                    do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                    seekDirection = 0
                }
        }
    }
}

private struct TouchTransportBar: View {
    @Bindable var session: TouchPlayback
    let fullscreen: Bool
    let canPiP: Bool
    let compact: Bool
    let showTotalTime: Bool
    @State private var showingOverflow = false
    let expand: () -> Void
    let pictureInPicture: () -> Void
    var body: some View {
        HStack(spacing: compact ? 0 : 6) {
            TouchTransportButton(title: session.playing ? "Pause" : "Play", symbol: session.playing ? "pause.fill" : "play.fill") { session.toggle() }
            if session.duration > 0 {
                Text(timestamp(session.time)).monospacedDigit().font(.caption).fixedSize()
                TouchSeekSlider(session: session)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .padding(.horizontal, compact ? 6 : 0)
                if showTotalTime { Text(timestamp(session.duration)).monospacedDigit().font(.caption).fixedSize() }
            } else {
                if session.live != nil { Label("Live", systemImage: "circle.fill").font(.caption).foregroundStyle(.red) }
                Spacer(minLength: 0)
            }
            if compact {
                TouchTransportButton(title: "More controls", symbol: "ellipsis") { showingOverflow = true }
                    .popover(isPresented: $showingOverflow) {
                        TouchControlOverflow(session: session, canPiP: canPiP, pictureInPicture: pictureInPicture)
                            .presentationCompactAdaptation(.popover)
                    }
            } else {
                if !session.qualities.isEmpty { TouchQualityMenu(session: session) }
                TouchPlaybackSettings(session: session)
                TouchRoutePicker(routeChanged: session.updateAirPlayRoute).frame(width: 44, height: 44).accessibilityLabel("AirPlay")
                if canPiP { TouchTransportButton(title: "Picture in Picture", symbol: "pip.enter", action: pictureInPicture) }
            }
            TouchTransportButton(title: fullscreen ? "Exit fullscreen" : "Fullscreen", symbol: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", action: expand)
        }.padding(.horizontal, 6).buttonStyle(.plain)
            // Keep glass behind the controls rather than around their common
            // ancestor, so presenting a menu cannot morph away the entire bar.
            .background {
                Color.clear.modifier(TouchGlassSurface(interactive: false)).allowsHitTesting(false)
            }
            .onChange(of: showingOverflow) { _, showing in session.interacting = showing; session.reveal() }
            .onDisappear { session.interacting = false }
    }
    private func timestamp(_ time: Double) -> String {
        let seconds = Int(max(0, time.isFinite ? time : 0))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Keep native slider dragging and accessibility, while also allowing a tap
/// anywhere along the track to move the playhead.
private struct TouchSeekSlider: UIViewRepresentable {
    let session: TouchPlayback

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> TrackSlider {
        let slider = TrackSlider()
        slider.minimumValue = 0
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = .white.withAlphaComponent(0.25)
        slider.thumbTintColor = .white
        slider.accessibilityLabel = String(localized: "Playback position")
        slider.editingChanged = { [weak coordinator = context.coordinator] editing in
            if editing { coordinator?.began() } else { coordinator?.ended() }
        }
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return slider
    }
    func updateUIView(_ slider: TrackSlider, context: Context) {
        slider.maximumValue = Float(max(1, session.duration))
        if !slider.isTracking { slider.value = Float(session.time) }
        let seconds = Int(max(0, session.time.isFinite ? session.time : 0))
        slider.accessibilityValue = seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @MainActor final class Coordinator: NSObject {
        let session: TouchPlayback
        init(session: TouchPlayback) { self.session = session }
        @objc func began() { session.scrubbing = true; session.reveal() }
        @objc func changed(_ slider: UISlider) {
            session.time = Double(slider.value)
            if !session.scrubbing { session.seek(session.time) }
        }
        @objc func ended() { session.scrubbing = false; session.seek(session.time) }
    }

    final class TrackSlider: UISlider {
        var editingChanged: ((Bool) -> Void)?
        private var dragOffset: CGFloat = 0
        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            editingChanged?(true)
            let point = touch.location(in: self)
            let track = trackRect(forBounds: bounds)
            let thumb = thumbRect(forBounds: bounds, trackRect: track, value: value)
            let onThumb = thumb.insetBy(dx: -8, dy: -8).contains(point)
            dragOffset = onThumb ? point.x - thumb.midX : 0
            if !onThumb { movePlayhead(to: point.x) }
            return true
        }
        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            movePlayhead(to: touch.location(in: self).x - dragOffset)
            return true
        }
        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            super.endTracking(touch, with: event)
            editingChanged?(false)
        }
        override func cancelTracking(with event: UIEvent?) {
            super.cancelTracking(with: event)
            editingChanged?(false)
        }
        private func movePlayhead(to x: CGFloat) {
            let track = trackRect(forBounds: bounds)
            let start = thumbRect(forBounds: bounds, trackRect: track, value: minimumValue).midX
            let end = thumbRect(forBounds: bounds, trackRect: track, value: maximumValue).midX
            let fraction = max(0, min(1, (x - start) / max(1, end - start)))
            value = minimumValue + Float(fraction) * (maximumValue - minimumValue)
            sendActions(for: .valueChanged)
        }
    }
}

private struct TouchQualityMenu: View {
    let session: TouchPlayback
    var body: some View {
                Menu {
                    ForEach(session.qualities) { quality in
                        Button { session.selectQuality?(quality.id); session.reveal() } label: {
                            if quality.id == session.qualityID { Label(quality.label, systemImage: "checkmark") }
                            else { Text(quality.label) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(session.qualities.first { $0.id == session.qualityID }?.label ?? "Quality").font(.callout).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }.frame(minWidth: 66, minHeight: 44)
                }.accessibilityLabel("Video quality")
    }
}
private struct TouchPlaybackSettings: View {
    let session: TouchPlayback
    var body: some View {
            Menu {
                Menu("Playback speed") {
                    ForEach([Float(0.5), 1, 1.25, 1.5, 2], id: \.self) { rate in
                        Button { session.changeSpeed(rate) } label: {
                            if session.speed == rate { Label("\(rate.formatted())×", systemImage: "checkmark") }
                            else { Text("\(rate.formatted())×") }
                        }
                    }
                }
                if let group = session.subtitleGroup {
                    Menu("Subtitles") {
                        Button("Off") { session.selectSubtitle(nil) }
                        ForEach(group.options, id: \.self) { option in
                            Button { session.selectSubtitle(option) } label: {
                                if session.subtitle === option { Label(option.displayName, systemImage: "checkmark") }
                                else { Text(option.displayName) }
                            }
                        }
                    }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Playback settings")
    }
}
private struct TouchControlOverflow: View {
    let session: TouchPlayback
    let canPiP: Bool
    let pictureInPicture: () -> Void
    var body: some View {
        VStack(spacing: 4) {
            if !session.qualities.isEmpty {
                HStack { Text("Quality"); Spacer(); TouchQualityMenu(session: session) }
            }
            HStack { Text("Playback settings"); Spacer(); TouchPlaybackSettings(session: session) }
            HStack { Text("AirPlay"); Spacer(); TouchRoutePicker(routeChanged: session.updateAirPlayRoute).frame(width: 44, height: 44) }
            if canPiP {
                Button("Picture in Picture", systemImage: "pip.enter", action: pictureInPicture).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            Button(session.muted ? "Unmute" : "Mute", systemImage: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                session.toggleMute()
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain).padding(16).frame(width: 260).environment(\.colorScheme, .dark)
    }
}

private struct TouchPlayerButton: View {
    let title: String
    let symbol: String
    var size: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).labelStyle(.iconOnly)
                .font(.system(size: size == 56 ? 24 : 18, weight: .medium))
                .frame(width: size, height: size).contentShape(Rectangle())
        }.buttonStyle(.plain).modifier(TouchGlassSurface())
    }
}
private struct TouchTransportButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).labelStyle(.iconOnly)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
    }
}
private struct TouchGlassSurface: ViewModifier {
    var interactive = true
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.glassEffect(.regular.interactive(interactive), in: RoundedRectangle(cornerRadius: 22)) }
        else { content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)) }
    }
}
private struct TouchRoutePicker: UIViewRepresentable {
    var routeChanged: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(routeChanged: routeChanged) }
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.delegate = context.coordinator
        view.tintColor = .white; view.activeTintColor = .systemBlue; view.prioritizesVideoDevices = true
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        let routeChanged: () -> Void
        init(routeChanged: @escaping () -> Void) { self.routeChanged = routeChanged }
        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) { routeChanged() }
    }
}
#endif

#if os(iOS)
import AVFoundation
import MediaPlayer

/// A scene-owned AirPlay-capable player; no phone view needs to remain mounted.
@MainActor final class CarPlayPlayback {
    let player = AVPlayer()
    private let session: MPNowPlayingSession
    private weak var model: AppModel?
    private var statusObservation: NSKeyValueObservation?
    var onFailure: (() -> Void)?

    init() {
        session = MPNowPlayingSession(players: [player])
        session.automaticallyPublishesNowPlayingInfo = true
        let commands = session.remoteCommandCenter
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.player.rate == 0 { self.resume() } else { self.player.pause() }
            }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
            return .success
        }
    }

    func play(url: URL, title: String, creator: String, cookie: SessionCookie?, model: AppModel) async throws {
        self.model = model
        let cookies = cookie?.httpCookie.map { [$0] } ?? []
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
        guard try await asset.load(.isPlayable) else { throw APIError.noVideo }
        try Task.checkCancellation()
        let item = AVPlayerItem(asset: asset)
        item.nowPlayingInfo = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: creator,
                               MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue]
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)
        model.claimPlayer(player)
        player.allowsExternalPlayback = true
        player.isMuted = ProcessInfo.processInfo.arguments.contains("--mute")
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                self.stop()
                self.onFailure?()
            }
        }
        player.replaceCurrentItem(with: item)
        _ = await session.becomeActiveIfPossible()
        try Task.checkCancellation()
        player.play()
    }

    func resume() {
        guard player.currentItem != nil else { return }
        model?.claimPlayer(player)
        player.play()
    }

    func stop() {
        statusObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
#endif

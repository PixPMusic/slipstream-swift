import AVFoundation
import Observation

/// Owns media and player state for an open post, independent of its layout's view tree.
@MainActor @Observable final class PostPlayback: Hashable {
    nonisolated let id = UUID()
    let post: Post
    private(set) var closed = false
    var detail: PostDetail?
    var qualities: [Delivery.Quality] = []
    var videoID = ""
    var selectedMediaID = ""
    var loadedMediaID = ""
    var pictureURL: URL?
    var qualityID = ""
    var player = AVPlayer()
    var loading = false
    var playerReady = false
    var playbackGeneration = UUID()
    var error: String?
    var playbackObservation: NSKeyValueObservation?
    var liked = false
    var disliked = false
    var likeCount = 0
    var dislikeCount = 0
    var liking = false
    var downloadQualities: [Delivery.Quality] = []
    var downloadError: String?
    var preparingDownload = false

    init(post: Post) { self.post = post }

    func stop() {
        closed = true
        player.pause()
        player.replaceCurrentItem(with: nil)
        playbackObservation = nil
        playbackGeneration = UUID()
    }

    nonisolated static func == (lhs: PostPlayback, rhs: PostPlayback) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

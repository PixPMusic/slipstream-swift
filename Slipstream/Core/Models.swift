import Foundation

struct FPUser: Codable, Sendable {
    let id: String
    let username: String
    let displayName: String?
    var profileImage: FPImage? = nil
    var name: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? username }
}

struct FPImage: Codable, Hashable, Sendable {
    let path: String
    var width: Int? = nil
    var height: Int? = nil
    var url: URL? { URL(string: path) }
}

struct Creator: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let icon: FPImage?
    var liveStream: LiveStream? = nil
    var lastLiveStream: LiveStream? = nil
    var cover: FPImage? = nil
}

struct Subscription: Decodable, Sendable { let creator: String }

struct Post: Decodable, Identifiable, Hashable, Sendable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: String
    let title: String
    let text: String?
    let creator: Creator
    let thumbnail: FPImage?
    let releaseDate: String
    let isAccessible: Bool?
    let metadata: Metadata?
    let channel: ChannelReference?
    struct Metadata: Decodable, Sendable { let videoDuration: Double? }
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: releaseDate) ?? ISO8601DateFormatter().date(from: releaseDate)
    }
    var duration: String? {
        guard let seconds = metadata?.videoDuration, seconds.isFinite, seconds > 0 else { return nil }
        let n = Int(min(seconds, 10_000_000))
        return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%d:%02d", n / 60, n % 60)
    }
}

struct PostDetail: Decodable, Sendable {
    let id: String
    let title: String
    let text: String?
    let videoAttachments: [VideoAttachment]?
    let audioAttachments: [VideoAttachment]?
    let pictureAttachments: [VideoAttachment]?
    let galleryAttachments: [VideoAttachment]?
    let attachmentOrder: [String]?
    let likes: Int?
    let dislikes: Int?
    let userInteraction: [String]?
    let comments: Int?
    var media: [PostAttachment] {
        let groups: [(PostAttachment.Kind, [VideoAttachment])] = [
            (.video, videoAttachments ?? []), (.audio, audioAttachments ?? []),
            (.picture, pictureAttachments ?? []), (.gallery, galleryAttachments ?? [])
        ]
        let files = groups.flatMap { kind, files in files.map { PostAttachment(file: $0, kind: kind) } }
        guard let order = attachmentOrder else { return files }
        return files.sorted { (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max) }
    }
    /// Video-only surfaces must preserve editorial order and exclude locked attachments.
    var playableVideos: [VideoAttachment] { videos.filter { $0.isAccessible != false } }

    var videos: [VideoAttachment] {
        let attachments = videoAttachments ?? []
        guard let order = attachmentOrder else { return attachments }
        return attachments.sorted { (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max) }
    }
}
struct VideoAttachment: Decodable, Identifiable, Sendable {
    let id: String
    let guid: String
    let title: String
    let isAccessible: Bool?
    let thumbnail: FPImage?
    private enum CodingKeys: String, CodingKey { case id, guid, title, isAccessible, thumbnail }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let id = try? value.decode(String.self) {
            self.id = id; guid = id; title = "Attachment"; isAccessible = nil; thumbnail = nil
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            guid = try container.decodeIfPresent(String.self, forKey: .guid) ?? id
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Attachment"
            isAccessible = try container.decodeIfPresent(Bool.self, forKey: .isAccessible)
            thumbnail = try container.decodeIfPresent(FPImage.self, forKey: .thumbnail)
        }
    }
}

struct Delivery: Decodable, Sendable {
    let groups: [Group]
    struct Origin: Decodable, Sendable { let url: String }
    struct Group: Decodable, Sendable {
        let origins: [Origin]?
        let variants: [Variant]
    }
    struct Variant: Decodable, Sendable {
        let name: String
        let label: String
        let url: String
        let origins: [Origin]?
        let order: Int?
        let enabled: Bool?
        let hidden: Bool?
        let mimeType: String?
    }
    struct Quality: Identifiable, Sendable {
        let id: String
        let label: String
        let url: URL
        let order: Int
    }
    var qualities: [Quality] {
        groups.enumerated().flatMap { index, group in
            group.variants.compactMap { variant -> Quality? in
                guard variant.enabled == true, variant.hidden != true else { return nil }
                let origin = variant.origins?.first?.url ?? group.origins?.first?.url ?? "https://www.floatplane.com"
                guard let base = URL(string: origin),
                      let url = URL(string: variant.url, relativeTo: base)?.absoluteURL,
                      url.scheme == "https", url.host != nil else { return nil }
                return Quality(id: "\(index)-\(variant.name)", label: variant.label, url: url, order: variant.order ?? 0)
            }
        }.sorted { $0.order > $1.order }
    }
}

struct LiveStream: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let thumbnail: FPImage?
}

struct FPComment: Decodable, Identifiable, Sendable {
    let id: String
    let text: String
    let user: Author
    let postDate: String
    let likes: Int?
    let userInteraction: [String]?
    let totalReplies: Int?
    let replies: [FPComment]?
    var emotes: [FPEmote]? = nil
    struct Author: Decodable, Sendable {
        let id: String
        let username: String
        let profileImage: FPImage?
    }
}

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let channel: String
    let username: String
    let message: String
    let userType: String?
    var emotes: [FPEmote]? = nil
}

struct CreatorChannel: Decodable, Identifiable, Sendable {
    let id: String
    let creator: String
    let title: String
    let icon: FPImage?
    let order: Int?
    var cover: FPImage? = nil
}

struct ChannelReference: Decodable, Sendable {
    let id: String
    let title: String?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(String.self) { self.id = id; title = nil }
        else {
            let object = try container.decode(Object.self)
            id = object.id; title = object.title
        }
    }
    private struct Object: Decodable { let id: String; let title: String? }
}

struct PostAttachment: Identifiable, Sendable {
    enum Kind: String, Sendable { case video, audio, picture, gallery }
    let file: VideoAttachment
    let kind: Kind
    var id: String { file.id }
    var title: String { file.title }
    var isPlayable: Bool { kind == .video || kind == .audio }
    var symbol: String {
        switch kind { case .video: "play.rectangle"; case .audio: "waveform"; case .picture: "photo"; case .gallery: "photo.on.rectangle" }
    }
}
struct PictureContent: Decodable, Sendable {
    let imageFiles: [FPImage]
    var originalURL: URL? { imageFiles.max { ($0.width ?? 0) < ($1.width ?? 0) }?.url }
}

import Foundation
import OSLog

enum APIError: LocalizedError, Equatable {
    case signedOut, forbidden, rateLimited, server(Int), invalidResponse, noVideo
    var errorDescription: String? {
        switch self {
        case .signedOut: "Your session has expired. Sign in to Floatplane again."
        case .forbidden: "Your subscription does not have access to this content."
        case .rateLimited: "Floatplane is receiving too many requests. Try again shortly."
        case .server(let status): "Floatplane returned an error (\(status)). Try again."
        case .invalidResponse: "Floatplane returned an unexpected response."
        case .noVideo: "No playable video is available for this post."
        }
    }
}

// A private cookie jar keeps the session out of shared URLSession storage.
actor FloatplaneAPI {
    private let session: URLSession
    init(cookie: SessionCookie, configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["Cookie": "sails.sid=\(cookie.value)", "Accept": "application/json", "Referer": "https://www.floatplane.com/"]
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
    }
    func request<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var url = URLComponents(string: "https://www.floatplane.com\(path)")!
        if !query.isEmpty { url.queryItems = query.filter { $0.value != nil } }
        let (data, response) = try await session.data(from: url.url!)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch response.statusCode {
        case 200..<300: break
        case 401: throw APIError.signedOut
        case 403: throw APIError.forbidden
        case 429: throw APIError.rateLimited
        default: throw APIError.server(response.statusCode)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.invalidResponse }
    }
    func user() async throws -> FPUser { try await request("/api/v3/user/self") }
    func creators() async throws -> [Creator] {
        let subscriptions: [Subscription] = try await request("/api/v3/user/subscriptions")
        var creators: [Creator] = []
        for id in Set(subscriptions.map(\.creator)).sorted() {
            let creator: Creator = try await request("/api/v3/creator/info", query: [.init(name: "id", value: id)])
            creators.append(creator)
        }
        return creators.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func posts(creator: String, channel: String? = nil, offset: Int = 0, search: String = "") async throws -> [Post] {
        try await request("/api/v3/content/creator", query: [
            .init(name: "channel", value: channel),
            .init(name: "id", value: creator), .init(name: "limit", value: "20"),
            .init(name: "fetchAfter", value: String(offset)), .init(name: "search", value: search)
        ])
    }
    func post(id: String) async throws -> PostDetail {
        let detail: PostDetail = try await request("/api/v3/content/post", query: [.init(name: "id", value: id)])
        #if DEBUG
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Slipstream", category: "attachments").notice("Post media: videos=\(detail.videoAttachments?.count ?? 0), audio=\(detail.audioAttachments?.count ?? 0), pictures=\(detail.pictureAttachments?.count ?? 0), galleries=\(detail.galleryAttachments?.count ?? 0)")
        #endif
        return detail
    }
    func picture(id: String) async throws -> PictureContent {
        try await request("/api/v3/content/picture", query: [.init(name: "id", value: id)])
    }
    func delivery(video: String, scenario: String = "onDemand") async throws -> Delivery {
        var query: [URLQueryItem] = [.init(name: "scenario", value: scenario), .init(name: "entityId", value: video)]
        if scenario == "live" {
            // Let the service choose its live format, as the web player does.
            // Forcing the on-demand fMP4 format can return no live variants.
            query.append(.init(name: "entityKind", value: "livestream"))
        } else {
            query.append(.init(name: "outputKind", value: scenario == "download" ? "flat" : "hls.fmp4"))
        }
        let delivery: Delivery = try await request("/api/v3/delivery/info", query: query)
        return delivery
    }
    func channels(creators: [String]) async throws -> [CreatorChannel] {
        guard !creators.isEmpty else { return [] }
        return try await request("/api/v3/creator/channels/list", query: creators.map { .init(name: "ids", value: $0) })
    }
    func comments(post: String, after: String? = nil) async throws -> [FPComment] {
        var query = [URLQueryItem(name: "blogPost", value: post), .init(name: "limit", value: "20")]
        if let after { query.append(.init(name: "fetchAfter", value: after)) }
        return try await request("/api/v3/comment", query: query)
    }
    func replies(post: String, comment: String, after: String = "") async throws -> [FPComment] {
        try await request("/api/v3/comment/replies", query: [.init(name: "blogPost", value: post), .init(name: "comment", value: comment), .init(name: "limit", value: "20"), .init(name: "rid", value: after)])
    }
    func addComment(post: String, text: String) async throws -> FPComment {
        let data = try await send("/api/v3/comment", body: ["blogPost": post, "text": text])
        return try JSONDecoder().decode(FPComment.self, from: data)
    }
    func like(post: String) async throws -> [String] {
        let data = try await send("/api/v3/content/like", body: ["contentType": "blogPost", "id": post])
        return try JSONDecoder().decode([String]?.self, from: data) ?? []
    }
    func dislike(post: String) async throws -> [String] {
        let data = try await send("/api/v3/content/dislike", body: ["contentType": "blogPost", "id": post])
        return try JSONDecoder().decode([String]?.self, from: data) ?? []
    }
    func likeComment(post: String, comment: String) async throws -> Bool {
        let data = try await send("/api/v3/comment/like", body: ["blogPost": post, "comment": comment])
        let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        return result == "like"
    }
    private func send(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://www.floatplane.com\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.floatplane.com", forHTTPHeaderField: "Origin")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw APIError.signedOut
        case 403: throw APIError.forbidden
        case 429: throw APIError.rateLimited
        default: throw APIError.server(response.statusCode)
        }
    }

}

private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the session header to a redirect on another host.
        completionHandler(request.url?.scheme == "https" && request.url?.host == "www.floatplane.com" ? request : nil)
    }
}

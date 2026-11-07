import Foundation
import Testing
@testable import SlipstreamCore

@Test func channelAndCreatorCoversPreserveBannerDimensions() throws {
    let channel = Data(#"{"id":"shortcircuit","creator":"ltt","title":"ShortCircuit","icon":null,"order":2,"cover":{"path":"https://pbs.floatplane.com/cover_images/channel.jpg","width":1245,"height":325}}"#.utf8)
    let decoded = try JSONDecoder().decode(CreatorChannel.self, from: channel)
    #expect(decoded.cover?.width == 1245)
    #expect(decoded.cover?.height == 325)
    #expect(decoded.cover?.url?.host == "pbs.floatplane.com")
    let creator = Data(#"{"id":"ltt","title":"Linus Tech Tips","icon":null,"cover":null}"#.utf8)
    #expect(try JSONDecoder().decode(Creator.self, from: creator).cover == nil)
}

@Test func creatorCoverUpdatesKeepStableIdentityButChangeValue() {
    let original = Creator(id: "ltt", title: "Linus Tech Tips", icon: nil, cover: FPImage(path: "https://pbs.floatplane.com/old.jpg"))
    let updated = Creator(id: "ltt", title: "Linus Tech Tips", icon: nil, cover: FPImage(path: "https://pbs.floatplane.com/new.jpg"))
    #expect(original.id == updated.id)
    #expect(original != updated)
}

@Test func emotesPreserveUnicodeUnknownCodesAndAdjacentRuns() {
    let wave = FPEmote(code: "wave", image: "https://cdn.floatplane.com/emotes/wave.png")
    #expect(EmotePart.parse("👋 :wave::wave: :unknown: café", emotes: [wave]) == [
        .text("👋 "), .emote(wave), .emote(wave), .text(" :unknown: café")
    ])
    #expect(EmotePart.parse(":Wave:", emotes: [wave]) == [.text(":Wave:")])
    #expect(EmotePart.parse("plain text", emotes: [wave]) == [.text("plain text")])
}

@Test func emoteImagesRequireTrustedHTTPSAndNormalizeTokens() {
    let safe = FPEmote(code: ":hello:", image: "https://cdn.floatplane.com/emotes/hello.png")
    #expect(safe.token == ":hello:")
    for path in ["http://cdn.floatplane.com/e.png", "https://floatplane.com.evil.example/e.png", "file:///tmp/e.png"] {
        let unsafe = FPEmote(code: "hello", image: path)
        #expect(unsafe.imageURL == nil)
        #expect(EmotePart.parse(":hello:", emotes: [unsafe]) == [.text(":hello:")])
    }
}

@Test func chatDecodesServerEmotesAndRemainsCompatibleWithoutThem() throws {
    let data = Data(#"{"id":"m1","channel":"/live/test","username":"Demo","message":":wave:","userType":"pilot","emotes":[{"code":"wave","image":"https://cdn.floatplane.com/emotes/wave.png"}]}"#.utf8)
    let message = try JSONDecoder().decode(ChatMessage.self, from: data)
    #expect(message.emotes?.first?.token == ":wave:")
    let old = Data(#"{"id":"m2","channel":"/live/test","username":"Demo","message":"hello"}"#.utf8)
    #expect(try JSONDecoder().decode(ChatMessage.self, from: old).emotes == nil)
}

@Test func sessionAcceptsOnlySecureFloatplaneCookies() throws {
    func cookie(_ domain: String, secure: Bool = true, name: String = "sails.sid") throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "fixture-session", .domain: domain, .path: "/"]
        if secure { properties[.secure] = "TRUE" }
        return try #require(HTTPCookie(properties: properties))
    }
    #expect(SessionCookie(cookie: try cookie(".floatplane.com")) != nil)
    #expect(SessionCookie(cookie: try cookie("www.floatplane.com")) != nil)
    #expect(SessionCookie(cookie: try cookie("evilfloatplane.com")) == nil)
    #expect(SessionCookie(cookie: try cookie("floatplane.com.evil.example")) == nil)
    #expect(SessionCookie(cookie: try cookie("floatplane.com", secure: false)) == nil)
    #expect(SessionCookie(cookie: try cookie("floatplane.com", name: "other")) == nil)
}

@Test func sessionRoundTripPreservesExpiryAndScope() throws {
    let cookie = try #require(HTTPCookie(properties: [.name: "sails.sid", .value: "fixture-session", .domain: ".floatplane.com", .path: "/", .secure: "TRUE", .expires: Date().addingTimeInterval(3600)]))
    let session = try #require(SessionCookie(cookie: cookie))
    let restored = try JSONDecoder().decode(SessionCookie.self, from: JSONEncoder().encode(session))
    #expect(!restored.isExpired)
    #expect(restored.httpCookie?.domain == "www.floatplane.com")
    #expect(restored.httpCookie?.isSecure == true)
    #expect(restored.httpCookie?.value == "fixture-session")
    let expired = Data(#"{"value":"fixture","expires":0}"#.utf8)
    #expect(try JSONDecoder().decode(SessionCookie.self, from: expired).isExpired)
}

@Test func deliveryResolvesEachOriginAndExcludesUnavailableVariants() throws {
    let fixture = #"""
    {"groups":[{"origins":[{"url":"https://cdn.example.com"}],"variants":[
    {"name":"1080","label":"1080p","url":"/video.m3u8?token=fixture","enabled":true,"order":100},
    {"name":"720","label":"720p","url":"/720.m3u8","enabled":true,"order":50,"origins":[{"url":"https://alternate.example.com"}]},
    {"name":"absolute","label":"360p","url":"https://absolute.example.com/360.m3u8","enabled":true,"order":10},
    {"name":"hidden","label":"Hidden","url":"/hidden","enabled":true,"hidden":true},
    {"name":"disabled","label":"Disabled","url":"/disabled","enabled":false},
    {"name":"missing","label":"Missing","url":"/missing"},
    {"name":"insecure","label":"HTTP","url":"http://cdn.example.com/insecure","enabled":true}
    ]}]}
    """#
    let qualities = try JSONDecoder().decode(Delivery.self, from: Data(fixture.utf8)).qualities
    #expect(qualities.map(\.label) == ["1080p", "720p", "360p"])
    #expect(qualities[0].url.absoluteString == "https://cdn.example.com/video.m3u8?token=fixture")
    #expect(qualities[1].url.host == "alternate.example.com")
    #expect(qualities[2].url.host == "absolute.example.com")
}

@Test func feedIDsAndDetailAttachmentsAreSeparateModels() throws {
    let feed = #"{"id":"post","title":"Example","creator":{"id":"creator","title":"Studio"},"releaseDate":"2026-11-05T12:00:00.000Z","videoAttachments":["video"],"metadata":{"videoDuration":3661}}"#
    let post = try JSONDecoder().decode(Post.self, from: Data(feed.utf8))
    #expect(post.duration == "1:01:01")
    #expect(post.date != nil)
    let detail = #"{"id":"post","title":"Example","attachmentOrder":["b","a"],"videoAttachments":[{"id":"a","guid":"guid-a","title":"First"},{"id":"b","guid":"guid-b","title":"Second"}]}"#
    #expect(try JSONDecoder().decode(PostDetail.self, from: Data(detail.utf8)).videos.map(\.guid) == ["guid-b", "guid-a"])
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let status = path.hasSuffix("unauthorized") ? 401 : path.hasSuffix("forbidden") ? 403 : path.hasSuffix("limited") ? 429 : 200
        let body = path.hasSuffix("malformed") ? "{}" : #"{"id":"fixture","username":"demo","displayName":"Demo"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func apiMapsAuthenticationAccessAndSchemaFailures() async throws {
    let cookie = try #require(HTTPCookie(properties: [.name: "sails.sid", .value: "fixture", .domain: "www.floatplane.com", .path: "/", .secure: "TRUE"]))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureProtocol.self]
    let api = FloatplaneAPI(cookie: try #require(SessionCookie(cookie: cookie)), configuration: configuration)
    #expect(try await api.user().name == "Demo")
    for (path, expected) in [("unauthorized", APIError.signedOut), ("forbidden", .forbidden), ("limited", .rateLimited), ("malformed", .invalidResponse)] {
        do {
            let _: FPUser = try await api.request("/\(path)")
            Issue.record("Expected an error for \(path)")
        } catch { #expect(error as? APIError == expected) }
    }
}

@Test func cloudflareFramesCanLoadWithoutOpeningTopLevelNavigation() throws {
    func allows(_ url: String, subframe: Bool) throws -> Bool {
        LoginNavigationPolicy.allows(try #require(URL(string: url)), isSubframe: subframe)
    }
    #expect(try allows("about:blank", subframe: true))
    #expect(try allows("about:srcdoc", subframe: true))
    #expect(try !allows("about:blank", subframe: false))
    #expect(try !allows("about:config", subframe: true))
    #expect(try allows("https://challenges.cloudflare.com/cdn-cgi/challenge-platform/", subframe: true))
    #expect(try allows("https://challenges.cloudflare.com/cdn-cgi/challenge-platform/", subframe: false))
    #expect(try allows("https://linustechtips.com/login/", subframe: false))
    #expect(try !allows("https://floatplane.com.attacker.example/", subframe: false))
    #expect(try !allows("file:///etc/passwd", subframe: true))
    #expect(try !allows("javascript:alert(1)", subframe: true))
}

private final class SocialFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var bodyData = request.httpBody ?? Data()
        if bodyData.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bodyData.append(contentsOf: buffer.prefix(count))
            }
        }
        let input = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: String] ?? [:]
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value: (String) -> String? = { name in query.first { $0.name == name }?.value }
        let comment = #"{"id":"comment","text":"A test comment","user":{"id":"user","username":"Viewer"},"postDate":"2026-11-05T12:00:00Z","likes":2,"userInteraction":[],"totalReplies":1,"replies":[{"id":"reply","text":"A reply","user":{"id":"user2","username":"Creator"},"postDate":"2026-11-05T12:01:00Z"}]}"#
        var valid = true
        var output = "{}"
        switch url.path {
        case "/api/v3/comment":
            if request.httpMethod == "POST" {
                valid = input == ["blogPost": "post", "text": "A test comment"] && request.value(forHTTPHeaderField: "Origin") == "https://www.floatplane.com"
                output = comment
            } else {
                valid = value("blogPost") == "post" && value("fetchAfter") == "cursor" && value("limit") == "20"
                output = "[\(comment)]"
            }
        case "/api/v3/content/like":
            valid = request.httpMethod == "POST" && input["contentType"] == "blogPost"
            output = input["id"] == "unlike" ? "null" : #"["like"]"#
        case "/api/v3/content/dislike":
            valid = request.httpMethod == "POST" && input["contentType"] == "blogPost" && ["post", "undislike"].contains(input["id"] ?? "")
            output = input["id"] == "undislike" ? "null" : #"["dislike"]"#
        case "/api/v3/comment/like":
            valid = input == ["blogPost": "post", "comment": "comment"]
            output = "like"
        case "/api/v3/creator/channels/list":
            valid = query.filter { $0.name == "ids" }.compactMap(\.value) == ["one", "two"]
            output = #"[{"id":"channel","creator":"one","title":"TechLinked","order":2}]"#
        case "/api/v3/content/creator":
            valid = value("id") == "one" && value("channel") == "channel" && value("fetchAfter") == "20"
            output = "[]"
        case "/api/v3/delivery/info":
            if value("scenario") == "live" {
                valid = value("outputKind") == nil && value("entityKind") == "livestream" && value("entityId") == "stream"
                output = #"{"groups":[{"origins":[{"url":"https://live.example.com"}],"variants":[{"name":"adaptive","label":"Auto","url":"/live/master.m3u8?token=fixture","enabled":true}]}]}"#
            } else {
                valid = value("scenario") == "download" && value("outputKind") == "flat" && value("entityId") == "video"
                output = #"{"groups":[{"variants":[{"name":"360","label":"360p","url":"https://cdn.example.com/file.mp4?token=fixture","enabled":true}]}]}"#
            }
        default: valid = false
        }
        let response = HTTPURLResponse(url: url, statusCode: valid ? 200 : 400, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(output.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func socialAPI() throws -> FloatplaneAPI {
    let cookie = try #require(HTTPCookie(properties: [.name: "sails.sid", .value: "fixture", .domain: "www.floatplane.com", .path: "/", .secure: "TRUE"]))
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SocialFixtureProtocol.self]
    return FloatplaneAPI(cookie: try #require(SessionCookie(cookie: cookie)), configuration: config)
}

@Test func commentsUseServerPaginationAndCorrectPostPayload() async throws {
    let api = try socialAPI()
    let comments = try await api.comments(post: "post", after: "cursor")
    #expect(comments.first?.replies?.first?.id == "reply")
    #expect(comments.first?.totalReplies == 1)
    #expect(try await api.addComment(post: "post", text: "A test comment").id == "comment")
}
@Test func likesHandleBothLikedAndNullableUnlikedResponses() async throws {
    let api = try socialAPI()
    #expect(try await api.like(post: "post") == ["like"])
    #expect(try await api.like(post: "unlike").isEmpty)
    #expect(try await api.likeComment(post: "post", comment: "comment"))
}
@Test func dislikesUseTheNativeToggleEndpointAndAcceptClearedState() async throws {
    let api = try socialAPI()
    #expect(try await api.dislike(post: "post") == ["dislike"])
    #expect(try await api.dislike(post: "undislike").isEmpty)
}
@Test func channelsAreBatchedAndFeedFilteringReachesTheServer() async throws {
    let api = try socialAPI()
    let channels = try await api.channels(creators: ["one", "two"])
    #expect(channels.first?.title == "TechLinked")
    #expect(try await api.posts(creator: "one", channel: "channel", offset: 20).isEmpty)
}
@Test func downloadsRequestFlatDeliveryAndKeepSignedURLIntact() async throws {
    let qualities = try await socialAPI().delivery(video: "video", scenario: "download").qualities
    #expect(qualities.first?.url.absoluteString == "https://cdn.example.com/file.mp4?token=fixture")
}

@Test func liveStreamsUseTheServiceFormatAndKeepTheAdaptivePlaylist() async throws {
    let qualities = try await socialAPI().delivery(video: "stream", scenario: "live").qualities
    #expect(qualities.first?.label == "Auto")
    #expect(qualities.first?.url.absoluteString == "https://live.example.com/live/master.m3u8?token=fixture")
}

@Test func feedAcceptsChannelObjectsAndChannelIDs() throws {
    let base = #"{"id":"post","title":"Video","creator":{"id":"creator","title":"Creator"},"releaseDate":"2026-11-05T12:00:00Z","channel":CHANNEL}"#
    let object = base.replacingOccurrences(of: "CHANNEL", with: #"{"id":"shortcircuit","title":"ShortCircuit"}"#)
    let identifier = base.replacingOccurrences(of: "CHANNEL", with: #""shortcircuit""#)
    #expect(try JSONDecoder().decode(Post.self, from: Data(object.utf8)).channel?.title == "ShortCircuit")
    #expect(try JSONDecoder().decode(Post.self, from: Data(identifier.utf8)).channel?.id == "shortcircuit")
}

@Test func mixedMediaPreservesTextAndEveryAttachmentInServerOrder() throws {
    let fixture = #"""
    {"id":"post","title":"Mixed post","text":"A text update and several attachments.",
     "attachmentOrder":["picture","video-two","audio","video-one","gallery"],
     "videoAttachments":[{"id":"video-one","guid":"v1","title":"First video"},{"id":"video-two","guid":"v2","title":"Second video"}],
     "audioAttachments":[{"id":"audio","guid":"a1","title":"Audio version"}],
     "pictureAttachments":[{"id":"picture","title":"Photo","thumbnail":{"path":"https://example.com/preview.jpg"}}],
     "galleryAttachments":[{"id":"gallery","title":"Gallery"}]}
    """#
    let post = try JSONDecoder().decode(PostDetail.self, from: Data(fixture.utf8))
    #expect(post.text == "A text update and several attachments.")
    #expect(post.media.map(\.id) == ["picture", "video-two", "audio", "video-one", "gallery"])
    #expect(post.media.map(\.kind) == [.picture, .video, .audio, .video, .gallery])
    #expect(post.media.filter(\.isPlayable).map(\.file.guid) == ["v2", "a1", "v1"])
}
@Test func imageSelectionUsesTheLargestAvailableFile() throws {
    let fixture = #"{"imageFiles":[{"path":"https://example.com/small.jpg","width":320},{"path":"https://example.com/original.jpg","width":2400}]}"#
    #expect(try JSONDecoder().decode(PictureContent.self, from: Data(fixture.utf8)).originalURL?.lastPathComponent == "original.jpg")
}

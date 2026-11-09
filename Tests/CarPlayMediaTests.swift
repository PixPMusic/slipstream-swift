import Foundation
import Testing
@testable import SlipstreamCore

@Test func carPlayVideosRespectAttachmentOrderAndAccess() throws {
    let data = Data(#"{"id":"post","title":"Mixed post","videoAttachments":[{"id":"locked","isAccessible":false},{"id":"first","guid":"video-first"},{"id":"second","isAccessible":true}],"audioAttachments":["audio"],"pictureAttachments":["picture"],"attachmentOrder":["audio","second","locked","picture","first"]}"#.utf8)
    let detail = try JSONDecoder().decode(PostDetail.self, from: data)
    #expect(detail.playableVideos.map(\.id) == ["second", "first"])
    #expect(detail.playableVideos.last?.guid == "video-first")
}

@Test func carPlayTextAndLockedPostsHaveNoVideos() throws {
    for json in [#"{"id":"text","title":"Text"}"#, #"{"id":"locked","title":"Locked","videoAttachments":[{"id":"video","isAccessible":false}]}"#] {
        let detail = try JSONDecoder().decode(PostDetail.self, from: Data(json.utf8))
        #expect(detail.playableVideos.isEmpty)
    }
}

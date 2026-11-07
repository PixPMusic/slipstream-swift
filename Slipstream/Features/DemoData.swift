import Foundation

enum DemoData {
    static let creators = [Creator(id: "studio", title: "The Workshop", icon: nil), Creator(id: "fieldnotes", title: "Field Notes", icon: nil)]
    static let posts: [Post] = {
        let titles = ["A quieter kind of workstation", "Behind the build: the details that matter", "One camera, a whole new perspective", "The studio tour you asked for", "Taking the long way home", "Small experiments, surprising results"]
        return titles.enumerated().map { index, title in
            let json: [String: Any] = [
                "id": "demo-\(index)", "title": title,
                "text": "A sample post from the Slipstream demo library. Your subscribed creators and their videos appear here after sign-in.",
                "creator": ["id": creators[index % 2].id, "title": creators[index % 2].title],
                "releaseDate": "2026-11-0\(5 - index % 4)T12:00:00.000Z", "isAccessible": true,
                "metadata": ["videoDuration": 60]
            ]
            // Static, local fixtures; never mixed with an authenticated account.
            return try! JSONDecoder().decode(Post.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }()
}

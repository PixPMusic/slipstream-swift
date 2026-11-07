import Foundation

struct FPEmote: Codable, Hashable, Identifiable, Sendable {
    let code: String
    let image: String
    var id: String { code }
    var token: String { ":\(code.trimmingCharacters(in: CharacterSet(charactersIn: ":"))):" }
    var imageURL: URL? {
        guard let url = URL(string: image), url.scheme == "https", let host = url.host?.lowercased(),
              host == "floatplane.com" || host.hasSuffix(".floatplane.com") else { return nil }
        return url
    }
}

enum EmotePart: Equatable, Sendable {
    case text(String)
    case emote(FPEmote)

    static func parse(_ text: String, emotes: [FPEmote]) -> [EmotePart] {
        var catalog: [String: FPEmote] = [:]
        for emote in emotes where emote.imageURL != nil { catalog[emote.token] = emote }
        guard !catalog.isEmpty,
              let expression = try? NSRegularExpression(pattern: ":[^:\\s]{1,100}:") else { return [.text(text)] }
        let source = text as NSString
        var result: [EmotePart] = []
        var cursor = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard let emote = catalog[source.substring(with: match.range)] else { continue }
            if cursor < match.range.location { result.append(.text(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))) }
            result.append(.emote(emote))
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length { result.append(.text(source.substring(from: cursor))) }
        return result.isEmpty ? [.text(text)] : result
    }
}

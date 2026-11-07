import Foundation

/// Keeps top-level sign-in on Floatplane and its identity providers while
/// allowing the document frames used by Cloudflare's verification widget.
enum LoginNavigationPolicy {
    static func allows(_ url: URL, isSubframe: Bool) -> Bool {
        if isSubframe && url.scheme == "about" {
            return url.absoluteString == "about:blank" || url.absoluteString == "about:srcdoc"
        }
        guard url.scheme == "https", let host = url.host else { return false }
        if isSubframe { return true }
        return allowsTopLevelHost(host)
    }

    static func allowsTopLevelHost(_ host: String) -> Bool {
        ["floatplane.com", "discord.com", "linustechtips.com", "linusmediagroup.com", "challenges.cloudflare.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }
}

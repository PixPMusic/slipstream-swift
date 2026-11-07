import SwiftUI

/// The hardware family selects platform conventions: navigation style, safe
/// areas, and system chrome. It never implies available space, because an iPad
/// window can be narrower than an iPhone; width-driven layout uses `Breakpoint`.
/// Duo is phone hardware, recognized from its first hinge update (`AppModel.isDuo`).
@MainActor enum Device {
    #if os(iOS)
    static let isPhone = UIDevice.current.userInterfaceIdiom == .phone
    static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    #else
    static let isPhone = false
    static let isPad = false
    #endif
}

/// Widths measured from the pane that lays out the content, never the screen.
enum Breakpoint {
    /// Narrower feeds use compact search and, on Mac, three-line card titles.
    static let compactFeed: CGFloat = 700
    /// Post metadata keeps its actions on the byline row from this width.
    static let inlinePostActions: CGFloat = 520
    /// Live chat sits beside the video from this width.
    static let sideBySideLive: CGFloat = 850
}

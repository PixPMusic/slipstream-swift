import SwiftUI

/// Keep the Mac's search appearance and editing behavior in toolbars and popovers.
#if os(macOS)
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focusRequested: Bool
    var prompt = "Search"

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(prompt)
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if focusRequested, let window = field.window {
            window.makeFirstResponder(field)
            DispatchQueue.main.async { focusRequested = false }
        }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { text.wrappedValue = field.stringValue }
        }
    }
}
#endif

struct FeedSearch: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var text: String
    var compact = false
    var refresh: (() -> Void)? = nil
    @State private var focusRequested = false
    #if os(macOS)
    private var searchWidth: CGFloat { compact ? 160 : 240 }
    #endif
    func body(content: Content) -> some View {
        #if os(macOS)
        content.toolbar {
            if !model.windowFullscreen {
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.flexible)
                    if let refresh {
                        ToolbarItem { FeedRefreshButton(action: refresh) }.sharedBackgroundVisibility(.hidden)
                    }
                    ToolbarItem {
                        FeedSearchControl(text: $text, focusRequested: $focusRequested, width: searchWidth)
                    }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .principal) { Spacer() }
                    if let refresh { ToolbarItem { FeedRefreshButton(action: refresh) } }
                    ToolbarItem {
                        FeedSearchControl(text: $text, focusRequested: $focusRequested, width: searchWidth)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.windowFullscreen {
                HStack(spacing: 8) {
                    if let refresh { FeedRefreshButton(action: refresh) }
                    FeedSearchControl(text: $text, focusRequested: $focusRequested, width: searchWidth)
                }.padding(.top, 8).padding(.trailing, 12).ignoresSafeArea(.container, edges: .top)
            }
        }
        .background {
            Button("Search") { focusRequested = true }
                .keyboardShortcut("f", modifiers: .command).hidden().accessibilityHidden(true)
        }
        #else
        // Keep content actions blue while the system search controls use neutral chrome.
        if #available(iOS 26.0, *) {
            searchContent(content)
                .searchToolbarBehavior(Device.isPad && compact ? .minimize : .automatic)
        } else {
            searchContent(content)
        }
        #endif
    }

    #if os(iOS)
    private func searchContent(_ content: Content) -> some View {
        content.tint(.blue)
            .searchable(text: $text, placement: Device.isPad ? .toolbar : .automatic, prompt: "Search")
            .tint(.primary)
    }
    #endif
}

#if os(macOS)
private struct FeedSearchControl: View {
    @Binding var text: String
    @Binding var focusRequested: Bool
    let width: CGFloat
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color(nsColor: .labelColor)).accessibilityHidden(true)
            TextField("Search", text: $text)
                .textFieldStyle(.plain).focused($focused)
                .frame(minWidth: 50).accessibilityLabel("Search")
            if !text.isEmpty {
                NativeChromeButton(title: "Clear search", symbol: "xmark.circle.fill", action: { text = "" }).frame(width: 18, height: 24)
            }
        }.padding(.horizontal, 12).frame(width: width, height: 36).modifier(SearchGlass())
            .onChange(of: focusRequested) { _, requested in
                if requested { focused = true; focusRequested = false }
            }
    }
}
private struct FeedRefreshButton: View {
    let action: () -> Void
    var body: some View {
        NativeChromeButton(title: "Refresh", symbol: "arrow.clockwise", action: action)
            .frame(width: 36, height: 36).modifier(RefreshGlass()).help("Refresh")
    }
}
private struct RefreshGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular, in: Circle()) }
        else { content.background(.regularMaterial, in: Circle()) }
    }
}
private struct SearchGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular, in: Capsule()) }
        else { content.background(.regularMaterial, in: Capsule()) }
    }
}
#endif

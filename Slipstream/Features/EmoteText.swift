import SwiftUI
import Observation

#if os(macOS)
private typealias EmoteImage = NSImage
#else
private typealias EmoteImage = UIImage
#endif

@MainActor @Observable private final class EmoteImages {
    static let shared = EmoteImages()
    var images: [URL: EmoteImage] = [:]
    @ObservationIgnored private var requests: [URL: Task<Data?, Never>] = [:]
    @ObservationIgnored private let session = URLSession(configuration: .ephemeral)

    func load(_ emotes: [FPEmote]) async {
        for emote in emotes {
            guard !Task.isCancelled, let url = emote.imageURL, images[url] == nil else { continue }
            let request: Task<Data?, Never>
            if let pending = requests[url] { request = pending }
            else {
                request = Task { [session] in
                    guard let (data, response) = try? await session.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000 else { return nil }
                    return data
                }
                requests[url] = request
            }
            if let data = await request.value, let image = EmoteImage(data: data) {
                if images.count >= 300 { images.removeAll(keepingCapacity: true) }
                images[url] = image
            }
            requests[url] = nil
        }
    }
}

/// Text image runs preserve normal wrapping and selection, including mixed Unicode.
struct EmoteText: View {
    let text: String
    let emotes: [FPEmote]
    var username: String? = nil
    var markdown = false
    @Environment(\.colorScheme) private var colorScheme
    private var parts: [EmotePart] { EmotePart.parse(text.trimmingCharacters(in: .whitespacesAndNewlines), emotes: emotes) }
    private var usedEmotes: [FPEmote] { parts.compactMap { if case .emote(let emote) = $0 { emote } else { nil } } }
    var body: some View {
        rendered.textSelection(.enabled)
            .task(id: usedEmotes) { await EmoteImages.shared.load(usedEmotes) }
    }
    private var rendered: Text {
        var result = username.map { Text($0).fontWeight(.semibold).foregroundColor(colorScheme == .dark ? Color(red: 0.48, green: 0.73, blue: 1) : .accentColor) + Text("  ") } ?? Text("")
        let tokens = parts
        for (index, part) in tokens.enumerated() {
            switch part {
            case .text(let raw):
                let original = username == nil ? raw : raw.replacingOccurrences(of: "(?<=\\p{L})-(?=\\p{L})", with: "\u{2011}", options: .regularExpression)
                let followedByEmote = tokens.indices.contains(index + 1) && { if case .emote = tokens[index + 1] { true } else { false } }()
                let string = followedByEmote && original.last?.isWhitespace == true
                    ? original.replacingOccurrences(of: "[ \t]+$", with: "\u{00a0}\u{2060}", options: .regularExpression) : original
                if markdown, let formatted = try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    result = result + Text(formatted)
                } else { result = result + Text(string) }
            case .emote(let emote):
                if let url = emote.imageURL, let source = EmoteImages.shared.images[url] {
                    #if os(macOS)
                    let image = NSImage(size: NSSize(width: 15, height: 15), flipped: false) { rect in
                        source.draw(in: rect)
                        return true
                    }
                    result = result + Text(Image(nsImage: image)).baselineOffset(-2)
                    #else
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { _ in source.draw(in: CGRect(x: 0, y: 0, width: 18, height: 18)) }
                    result = result + Text(Image(uiImage: image)).baselineOffset(-3)
                    #endif
                } else { result = result + Text(emote.token) }
            }
        }
        return result
    }
}

struct EmotePicker: View {
    let emotes: [FPEmote]
    let insert: (String) -> Void
    var visibilityChanged: (Bool) -> Void = { _ in }
    @State private var showing = false
    var body: some View {
        Button("Emotes", systemImage: "face.smiling") { showing.toggle() }
            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            .font(.system(size: 17)).frame(width: 24, height: 28).help("Emotes").disabled(emotes.isEmpty)
            .onChange(of: showing) { _, value in visibilityChanged(value) }
            .onDisappear { if showing { visibilityChanged(false) } }
            .popover(isPresented: $showing) {
                EmotePickerPanel(emotes: emotes) { token in insert(token); showing = false }
            }
    }
}

private struct EmotePickerPanel: View {
    let emotes: [FPEmote]
    let insert: (String) -> Void
    @State private var search = ""
    @State private var hovered: FPEmote?
    @State private var focusRequested = false
    private var filtered: [FPEmote] { emotes.filter { search.isEmpty || $0.code.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 12) {
            #if os(macOS)
            NativeSearchField(text: $search, focusRequested: $focusRequested, prompt: "Find emote").frame(height: 28)
            #else
            TextField("Find emote", text: $search).textFieldStyle(.roundedBorder)
            #endif
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 5), spacing: 8) {
                    ForEach(filtered) { emote in
                        EmoteCell(emote: emote, hovered: hovered?.id == emote.id, action: { insert(emote.token) })
                            .onHover { inside in if inside { hovered = emote } }
                    }
                }.padding(2)
                #if os(macOS)
                .background { OverlayScrollerStyle() }
                #endif
            }.scrollIndicators(.hidden).frame(height: CGFloat(min(5, max(1, (emotes.count + 4) / 5))) * 60 - 4)
                .overlay { if filtered.isEmpty { Text("No emotes found").foregroundStyle(.secondary) } }
            Divider()
            if let emote = hovered ?? filtered.first {
                HStack(spacing: 12) {
                    EmoteArtwork(url: emote.imageURL).frame(width: 56, height: 56)
                    Text(emote.token).font(.callout.monospaced()).lineLimit(2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.frame(height: 56)
            } else { Color.clear.frame(height: 56) }
        }.padding(16).frame(width: 344)
            .onChange(of: search) { _, _ in hovered = nil }
    }
}

private struct EmoteCell: View {
    let emote: FPEmote
    let hovered: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            EmoteArtwork(url: emote.imageURL).frame(width: 44, height: 44).frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.primary.opacity(hovered ? 0.16 : 0.035), in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(hovered ? 0.15 : 0.025)) }
        }.buttonStyle(.plain).help(emote.token).accessibilityLabel(emote.token)
    }
}

private struct EmoteArtwork: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFit() }
            placeholder: { Image(systemName: "face.smiling").foregroundStyle(.secondary) }
    }
}

import SwiftUI
import Observation
@preconcurrency import SocketIO

@MainActor @Observable final class LiveChat {
    var messages: [ChatMessage] = []
    var emotes: [FPEmote] = []
    var connected = false
    var connecting = false
    var sending = false
    private(set) var previewing = false
    var error: String?
    @ObservationIgnored private var manager: SocketManager?
    @ObservationIgnored private var socket: SocketIOClient?
    @ObservationIgnored private var channel = ""
    @ObservationIgnored private var generation = UUID()

    func connect(stream: String, cookie: SessionCookie) {
        disconnect()
        let generation = UUID()
        self.generation = generation
        channel = "/live/\(stream)"
        messages = []; emotes = []
        connecting = true; error = nil
        let manager = SocketManager(socketURL: URL(string: "https://chat.floatplane.com")!, config: [
            .log(false), .forceWebsockets(true), .secure(true), .version(.two),
            .handleQueue(.main), .reconnects(true), .reconnectAttempts(8), .reconnectWait(3),
            .extraHeaders(["Origin": "https://www.floatplane.com", "Cookie": "sails.sid=\(cookie.value)"]),
            .connectParams(["__sails_io_sdk_version": "1.2.1", "__sails_io_sdk_platform": "browser", "__sails_io_sdk_language": "javascript"])
        ])
        self.manager = manager
        let socket = manager.defaultSocket
        self.socket = socket
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.join(generation: generation)
            }
        }
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.connected = false; self.connecting = false
                self.error = "Chat disconnected. Reconnecting…"
            }
        }
        socket.on(clientEvent: .error) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.connecting = false
                self.error = "Couldn’t connect to chat."
            }
        }
        socket.on("radioChatter") { [weak self] args, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation,
                      let object = args.first, let data = try? JSONSerialization.data(withJSONObject: object),
                      let message = try? JSONDecoder().decode(ChatMessage.self, from: data), message.channel == self.channel else { return }
                self.append(message)
            }
        }
        socket.connect(timeoutAfter: 20) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.connecting = false
                self.error = "Chat connection timed out."
            }
        }
    }
    private func join(generation: UUID) {
        let request: [String: Any] = ["method": "get", "url": "/RadioMessage/joinLivestreamRadioFrequency", "headers": [String: String](), "data": ["channel": channel, "message": NSNull()]]
        socket?.emitWithAck("get", request).timingOut(after: 15) { [weak self] args in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.connecting = false
                guard let ack = args.first as? [String: Any], let status = ack["statusCode"] as? Int,
                      (200..<300).contains(status), (ack["body"] as? [String: Any])?["success"] as? Bool == true else {
                    self.error = "Couldn’t join this stream’s chat."
                    return
                }
                if let body = ack["body"] as? [String: Any], let list = body["emotes"],
                   let data = try? JSONSerialization.data(withJSONObject: list),
                   let decoded = try? JSONDecoder().decode([FPEmote].self, from: data) {
                    var codes = Set<String>()
                    self.emotes = decoded.filter { $0.imageURL != nil && codes.insert($0.code).inserted }
                }
                self.connected = true; self.error = nil
            }
        }
    }
    func send(_ text: String, completion: @escaping @MainActor (Bool) -> Void) {
        guard connected, !sending else { completion(false); return }
        #if DEBUG
        if previewing {
            append(ChatMessage(id: UUID().uuidString, channel: channel, username: "You", message: text, userType: "pilot", emotes: emotes))
            completion(true)
            return
        }
        #endif
        let generation = generation
        sending = true
        let request: [String: Any] = ["method": "post", "url": "/RadioMessage/sendLivestreamRadioChatter/", "headers": [String: String](), "data": ["channel": channel, "message": text]]
        socket?.emitWithAck("post", request).timingOut(after: 15) { [weak self] args in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { completion(false); return }
                self.sending = false
                guard let ack = args.first as? [String: Any], let status = ack["statusCode"] as? Int,
                      (200..<300).contains(status), let body = ack["body"] as? [String: Any], body["success"] as? Bool != false else {
                    self.error = "Message wasn’t sent. Your draft is preserved."
                    completion(false)
                    return
                }
                if let data = try? JSONSerialization.data(withJSONObject: body),
                   let message = try? JSONDecoder().decode(ChatMessage.self, from: data) { self.append(message) }
                self.error = nil
                completion(true)
            }
        }
    }
    private func append(_ message: ChatMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        if messages.count > 300 { messages.removeFirst(messages.count - 300) }
    }
    #if DEBUG
    func loadPreview(stream: String, emotes: [FPEmote]) {
        disconnect()
        self.emotes = emotes
        channel = "/live/\(stream)"
        previewing = true; connected = true; error = nil
        let users = ["Maya", "Eli", "Nora", "Theo", "Avery", "Sam"]
        let lines = [
            "That side-by-side comparison makes it much easier to see.",
            "Can we get a closer look at the connectors?",
            "The small details in this build are fantastic.",
            "Interesting point about the display coating.",
            "I went back to check the first example. Much clearer now.",
            "This is why I like the longer follow-up videos."
        ]
        messages = (0..<72).map { index in
            let emote = index.isMultiple(of: 5) ? emotes.first?.token ?? "" : ""
            return ChatMessage(id: "preview-\(index)", channel: channel, username: users[index % users.count], message: lines[index % lines.count] + " " + emote, userType: "pilot", emotes: emotes)
        }
    }
    #endif
    func disconnect() {
        generation = UUID()
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil; manager = nil
        connected = false; connecting = false; sending = false; previewing = false
    }
}

struct LiveChatView: View {
    @Environment(AppModel.self) private var model
    let streamID: String
    var streamOffline = false
    @State private var chat = LiveChat()
    @State private var draft = ""
    @State private var followLatest = true
    @State private var emotePickerVisible = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat").font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(chat.connected && !chat.previewing ? Color.green : .secondary).frame(width: 5, height: 5)
                    if chat.previewing || !chat.connected {
                        Text(chat.previewing ? "Preview" : chat.connecting ? "Connecting…" : "Disconnected")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(chat.previewing ? "Chat preview" : chat.connected ? "Connected to chat" : chat.connecting ? "Connecting to chat" : "Chat disconnected")
                    .help(chat.connected && !chat.previewing ? "Connected to chat" : "Chat connection status")
            }.padding(.horizontal, 16).frame(height: 52)
            Divider()
            ScrollViewReader { proxy in
                GeometryReader { viewport in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(chat.messages) { message in
                                EmoteText(text: message.message, emotes: message.emotes ?? chat.emotes, username: message.username)
                                    .font(.body).frame(maxWidth: .infinity, alignment: .leading).id(message.id)
                            }
                            Color.clear.frame(height: 1).id("chatBottom")
                                .background { GeometryReader { geometry in Color.clear.preference(key: ChatBottomKey.self, value: geometry.frame(in: .named("chatScroll")).maxY) } }
                        }.padding(16)
                    }
                    .coordinateSpace(name: "chatScroll")
                    .clipped()
                    .defaultScrollAnchor(.bottom)
                    .modifier(ChatScrollTracking(viewportHeight: viewport.size.height, following: $followLatest, contentChanged: { proxy.scrollTo("chatBottom", anchor: .bottom) }))
                    .onChange(of: chat.messages.last?.id) { _, _ in
                        if followLatest { proxy.scrollTo("chatBottom", anchor: .bottom) }
                    }
                    .overlay {
                        if chat.messages.isEmpty {
                            if chat.connecting { ProgressView("Connecting…") }
                            else {
                                VStack(spacing: 8) {
                                    Text(chat.connected ? "No messages yet" : "Chat unavailable")
                                }.foregroundStyle(.secondary).multilineTextAlignment(.center).padding(20)
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if !followLatest && !chat.messages.isEmpty && !emotePickerVisible {
                            ChatJumpButton {
                                followLatest = true
                                proxy.scrollTo("chatBottom", anchor: .bottom)
                            }.padding(.bottom, 12)
                        }
                    }
                }
            }
            if let error = chat.error {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { connect() }.buttonStyle(.borderless)
                }.padding(12)
            }
            Divider()
            VStack(spacing: 10) {
                HStack {
                    EmotePicker(emotes: chat.emotes, insert: { token in draft += (draft.isEmpty || draft.last?.isWhitespace == true ? "" : " ") + token + " " }, visibilityChanged: { emotePickerVisible = $0 }).disabled(!chat.connected || chat.sending)
                    TextField(chat.previewing ? "Message in preview" : chat.connected ? "Message" : "Chat unavailable", text: $draft, axis: .vertical).lineLimit(1...4).modifier(ComposerFieldStyle()).disabled(!chat.connected || chat.sending)
                    Button("Send", systemImage: "arrow.up") {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        chat.send(text) { success in if success && draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" } }
                    }.labelStyle(.iconOnly).buttonStyle(ComposerButtonStyle()).disabled(!chat.connected || chat.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(12)
        }
        .onChange(of: chat.emotes) { _, emotes in if !emotes.isEmpty { model.emotes = emotes } }
        .task(id: "\(streamID)-\(previewing)") {
            #if DEBUG
            if previewing { chat.loadPreview(stream: streamID, emotes: model.emotes) }
            else { connect() }
            #else
            connect()
            #endif
        }
        .onDisappear { chat.disconnect() }
    }
    private var previewing: Bool {
        #if DEBUG
        model.chatPreview
        #else
        false
        #endif
    }
    private func connect() { if let cookie = model.cookie { chat.connect(stream: streamID, cookie: cookie) } }
}

private struct ChatScrollPosition: Equatable {
    let offset: CGFloat
    let height: CGFloat
    let atBottom: Bool
}

private struct ChatScrollTracking: ViewModifier {
    let viewportHeight: CGFloat
    @Binding var following: Bool
    let contentChanged: () -> Void
    func body(content: Content) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            content.onScrollGeometryChange(for: ChatScrollPosition.self) { geometry in
                ChatScrollPosition(offset: geometry.visibleRect.minY, height: geometry.contentSize.height,
                                   atBottom: geometry.visibleRect.maxY >= geometry.contentSize.height - 32)
            } action: { old, new in
                if old.height == new.height && old.offset != new.offset { following = new.atBottom }
                else if following && old.height != new.height { contentChanged() }
                else if new.atBottom { following = true }
            }
        } else {
            content.onPreferenceChange(ChatBottomKey.self) { following = $0 <= viewportHeight + 32 }
        }
    }
}

private struct ChatBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ChatJumpButton: View {
    let action: () -> Void
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            button.glassEffect(.regular, in: Capsule())
        } else { button.background(.regularMaterial, in: Capsule()) }
    }
    private var button: some View {
        Button("Jump to latest", systemImage: "arrow.down", action: action)
            .buttonStyle(.plain).font(.callout.weight(.medium)).padding(.horizontal, 12).frame(height: 32).help("Jump to latest")
    }
}

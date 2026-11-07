import SwiftUI

struct CommentsView: View {
    @Environment(AppModel.self) private var model
    let postID: String
    var count: Int? = nil
    @State private var added = 0
    @State private var comments: [FPComment] = []
    @State private var draft = ""
    @State private var loading = false
    @State private var sending = false
    @State private var hasMore = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Comments").font(.title3.weight(.semibold))
                if let count { Text((count + added).formatted()).font(.title3).foregroundStyle(.secondary) }
            }
            HStack(alignment: .center, spacing: 12) {
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .lineLimit(1...6).modifier(ComposerFieldStyle())
                if !model.emotes.isEmpty { EmotePicker(emotes: model.emotes) { token in draft += (draft.isEmpty || draft.last?.isWhitespace == true ? "" : " ") + token + " " } }
                Button("Post") { Task { await send() } }.buttonStyle(ComposerButtonStyle()).disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.demo)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            ForEach(comments) { comment in
                CommentThread(postID: postID, comment: comment)
                Divider()
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            else if hasMore { Button("More comments") { Task { await load(more: true) } } }
            else if comments.isEmpty { Text("No comments yet.").foregroundStyle(.secondary) }
        }.task { await load(more: false) }
    }
    private func load(more: Bool) async {
        guard let api = model.api else { return }
        loading = true
        defer { loading = false }
        do {
            let batch = try await api.comments(post: postID, after: more ? comments.last?.id : nil)
            try Task.checkCancellation()
            var seen = Set(comments.map(\.id))
            if more { comments += batch.filter { seen.insert($0.id).inserted } }
            else { comments = batch }
            hasMore = batch.count == 20
            error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func send() async {
        guard let api = model.api else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            let comment = try await api.addComment(post: postID, text: text)
            comments.insert(comment, at: 0)
            added += 1
            if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct CommentThread: View {
    @Environment(AppModel.self) private var model
    let postID: String
    let comment: FPComment
    @State private var replies: [FPComment] = []
    @State private var expanded = false
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommentRow(postID: postID, comment: comment)
            if (comment.totalReplies ?? 0) > 0 || !(comment.replies ?? []).isEmpty {
                Button(expanded ? "Hide replies" : "View replies (\(comment.totalReplies ?? comment.replies?.count ?? 0))") {
                    expanded.toggle()
                    if expanded { Task { await load() } }
                }.buttonStyle(.plain).font(.callout).foregroundStyle(.secondary).padding(.leading, 42)
            }
            if expanded {
                ForEach(replies) { reply in CommentRow(postID: postID, comment: reply) }.padding(.leading, 42)
                if loading { ProgressView().padding(.leading, 42) }
                if replies.count < (comment.totalReplies ?? 0) && !loading && error == nil {
                    Button("More replies") { Task { await load(more: true) } }.padding(.leading, 42)
                }
                if let error { Text(error).foregroundStyle(.secondary) }
            }
        }
    }
    private func load(more: Bool = false) async {
        guard let api = model.api else { return }
        if !more, let embedded = comment.replies, !embedded.isEmpty {
            replies = embedded
            return
        }
        loading = true
        defer { loading = false }
        do {
            let batch = try await api.replies(post: postID, comment: comment.id, after: more ? replies.last?.id ?? comment.id : comment.id)
            if more { var ids = Set(replies.map(\.id)); replies += batch.filter { ids.insert($0.id).inserted } }
            else { replies = batch }
        } catch { self.error = error.localizedDescription }
    }
}

private struct CommentRow: View {
    @Environment(AppModel.self) private var model
    let postID: String
    let comment: FPComment
    @State private var liked = false
    @State private var count = 0
    @State private var busy = false
    @State private var error: String?
    private var commentDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: comment.postDate) ?? ISO8601DateFormatter().date(from: comment.postDate)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CreatorAvatar(url: comment.user.profileImage?.url, size: 30)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(comment.user.username).font(.subheadline.weight(.semibold))
                    if let date = commentDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(Color.primary.opacity(0.7))
                    }
                }
                EmoteText(text: comment.text, emotes: comment.emotes ?? model.emotes, markdown: true).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        guard let api = model.api, !busy else { return }
                        busy = true
                        defer { busy = false }
                        do {
                            let newValue = try await api.likeComment(post: postID, comment: comment.id)
                            count = max(0, count + (newValue == liked ? 0 : newValue ? 1 : -1))
                            liked = newValue
                        } catch { self.error = error.localizedDescription }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        if count > 0 { Text(count.formatted()) }
                    }
                }
                    .buttonStyle(.plain).font(.callout).foregroundStyle(liked ? Color.accentColor : .primary).disabled(busy || model.demo)
                    .accessibilityLabel(liked ? "Unlike comment" : "Like comment").accessibilityValue(count.formatted())
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.onAppear { liked = comment.userInteraction?.contains("like") == true; count = comment.likes ?? 0 }
    }
}

struct ComposerFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 8)
            #if os(iOS)
            .frame(minHeight: 44)
            #endif
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary) }
    }
}

struct ComposerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body).frame(minWidth: 16)
            #if os(macOS)
            .frame(height: 16)
            #endif
            .padding(.horizontal, 10).padding(.vertical, 8)
            #if os(iOS)
            .frame(minHeight: 44)
            #endif
            .foregroundStyle(enabled ? .primary : .secondary)
            .background(.quaternary.opacity(configuration.isPressed ? 0.7 : 0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary) }
    }
}

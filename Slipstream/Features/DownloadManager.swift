import SwiftUI
import Observation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

@MainActor @Observable final class DownloadManager {
    var progress: Double?
    var error: String?
    var savedURL: URL?
    var task: Task<Void, Never>?
    private var generation = UUID()
    func start(url: URL, title: String, fileExtension: String = "mp4") {
        guard task == nil else { return }
        let contentType = UTType(filenameExtension: fileExtension) ?? .data
        let suffix = contentType.preferredFilenameExtension ?? "dat"
        let name = String(title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init).prefix(120))
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + "." + suffix
        task = Task { [self] in
            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [contentType]
            panel.allowsOtherFileTypes = false
            panel.isExtensionHidden = false
            NSApp.activate()
            let response = await panel.begin()
            guard response == .OK, let destination = panel.url else { task = nil; return }
            #else
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
            #endif
            let generation = UUID()
            self.generation = generation
            progress = 0; error = nil; savedURL = nil
            let scoped = destination.startAccessingSecurityScopedResource()
            defer {
                if scoped { destination.stopAccessingSecurityScopedResource() }
                progress = nil; task = nil
            }
            do {
                let observer = DownloadProgress { [weak self] value in
                    guard let self, self.generation == generation, self.task != nil else { return }
                    if abs((self.progress ?? 0) - value) >= 0.005 { self.progress = value }
                }
                let session = URLSession(configuration: .ephemeral)
                defer { session.invalidateAndCancel() }
                let (temporary, response) = try await session.download(from: url, delegate: observer)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      http.mimeType != "text/html", http.mimeType != "application/json" else { throw APIError.invalidResponse }
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                // The save panel has already confirmed replacement if a file exists.
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                } else { try FileManager.default.moveItem(at: temporary, to: destination) }
                savedURL = destination
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    func cancel() { task?.cancel() }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let update: @MainActor @Sendable (Double) -> Void
    init(update: @escaping @MainActor @Sendable (Double) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in update(progress) }
    }
}

struct DownloadStatusView: View {
    let download: DownloadManager
    var body: some View {
        if let progress = download.progress {
            HStack {
                ProgressView(value: progress).frame(maxWidth: 180)
                Text(progress, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit())
                Button("Cancel") { download.cancel() }.buttonStyle(.borderless)
            }
        } else if let url = download.savedURL {
            #if os(macOS)
            Button("Show download in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .buttonStyle(.borderless)
            #else
            ShareLink("Save or share download", item: url)
            #endif
        }
        if let error = download.error { Text(error).font(.caption).foregroundStyle(.red) }
    }
}

import SwiftUI
import CoreImage.CIFilterBuiltins
import ImageIO

/// Sample only hovered thumbnails; the feed never waits for decorative color work.
private actor ThumbnailColors {
    static let shared = ThumbnailColors()
    private let context = CIContext(options: [.useSoftwareRenderer: true])
    private var colors: [URL: RGB] = [:]
    struct RGB: Sendable {
        let red: Double
        let green: Double
        let blue: Double
        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    func color(for url: URL) async -> RGB? {
        if let color = colors[url] { return color }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000,
              !Task.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32
              ] as CFDictionary) else { return nil }
        let image = CIImage(cgImage: thumbnail)
        let average = CIFilter.areaAverage()
        average.inputImage = image
        average.extent = image.extent
        guard let output = average.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let peak = Double(max(pixel[0], pixel[1], pixel[2], 1))
        let floor = Double(min(pixel[0], pixel[1], pixel[2])) * 0.65
        let scale = max(1, peak - floor)
        let color = RGB(red: max(0, Double(pixel[0]) - floor) / scale,
                        green: max(0, Double(pixel[1]) - floor) / scale,
                        blue: max(0, Double(pixel[2]) - floor) / scale)
        if colors.count >= 256 { colors.removeAll(keepingCapacity: true) }
        colors[url] = color
        return color
    }
}

struct ThumbnailHover: ViewModifier {
    let url: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var hovering = false
    @State private var tint = Color.primary

    func body(content: Content) -> some View {
        content
            .background(tint.opacity(hovering ? (colorScheme == .dark ? 0.17 : 0.10) : 0), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tint.opacity(hovering ? 0.15 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onHover { hovering = $0 }
            .onDisappear { hovering = false }
            .onChange(of: scenePhase) { _, phase in if phase != .active { hovering = false } }
            .task(id: hovering) {
                guard hovering, let url, let sampled = await ThumbnailColors.shared.color(for: url), !Task.isCancelled else { return }
                tint = sampled.color
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: tint)
    }
}

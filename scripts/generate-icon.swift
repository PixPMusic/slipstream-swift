import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: "Slipstream/Resources")
func writeIcon(pixels: Int, ios: Bool, to url: URL) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space, bitmapInfo: (ios ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    let dark = CGColor(red: 0.04, green: 0.18, blue: 0.26, alpha: 1)
    if ios {
        context.setFillColor(dark)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }
    context.saveGState()
    // iOS supplies the icon mask. Only Mac assets include their own rounded silhouette.
    if !ios {
        context.addPath(CGPath(roundedRect: CGRect(x: 72, y: 72, width: 880, height: 880), cornerWidth: 198, cornerHeight: 198, transform: nil))
        context.clip()
    }
    let colors = [dark, CGColor(red: 0.04, green: 0.47, blue: 0.59, alpha: 1)]
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: ios ? .zero : CGPoint(x: 80, y: 80), end: ios ? CGPoint(x: 1024, y: 1024) : CGPoint(x: 940, y: 940), options: [])
    context.restoreGState()
    context.setStrokeColor(CGColor(red: 0.49, green: 0.94, blue: 0.98, alpha: 1))
    context.setLineWidth(38)
    context.setLineCap(.round)
    for row in 0..<3 {
        let y = CGFloat(350 + row * 132)
        context.move(to: CGPoint(x: 260, y: y))
        context.addCurve(to: CGPoint(x: 512, y: y), control1: CGPoint(x: 360, y: y + 90), control2: CGPoint(x: 412, y: y - 90))
        context.addCurve(to: CGPoint(x: 764, y: y), control1: CGPoint(x: 612, y: y + 90), control2: CGPoint(x: 664, y: y - 90))
        context.strokePath()
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}
for ios in [false, true] {
    let catalog = root.appendingPathComponent(ios ? "iOS.xcassets" : "Assets.xcassets")
    let icons = catalog.appendingPathComponent("AppIcon.appiconset")
    try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    if ios {
        try writeIcon(pixels: 1024, ios: true, to: icons.appendingPathComponent("ios-1024.png"))
        images.append(["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "ios-1024.png"])
    } else {
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon-\(points)@\(scale)x.png"
                try writeIcon(pixels: points * scale, ios: false, to: icons.appendingPathComponent(name))
                images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
            }
        }
    }
    try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: icons.appendingPathComponent("Contents.json"))
    try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: catalog.appendingPathComponent("Contents.json"))
}

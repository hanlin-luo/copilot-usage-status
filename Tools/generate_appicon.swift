import Foundation
import AppKit

struct IconSpec { let size: Int; let scale: Int; let filename: String }

let specs: [IconSpec] = [
    .init(size: 16, scale: 1, filename: "icon_16.png"),
    .init(size: 16, scale: 2, filename: "icon_16@2x.png"),
    .init(size: 32, scale: 1, filename: "icon_32.png"),
    .init(size: 32, scale: 2, filename: "icon_32@2x.png"),
    .init(size: 128, scale: 1, filename: "icon_128.png"),
    .init(size: 128, scale: 2, filename: "icon_128@2x.png"),
    .init(size: 256, scale: 1, filename: "icon_256.png"),
    .init(size: 256, scale: 2, filename: "icon_256@2x.png"),
    .init(size: 512, scale: 1, filename: "icon_512.png"),
    .init(size: 512, scale: 2, filename: "icon_512@2x.png"),
]

let baseSize: CGFloat = 1024

let fm = FileManager.default
let projectRoot = URL(fileURLWithPath: fm.currentDirectoryPath)
let appIconPath = projectRoot
    .appendingPathComponent("CopilotUsageStatus")
    .appendingPathComponent("CopilotUsageStatus")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")

try fm.createDirectory(at: appIconPath, withIntermediateDirectories: true)

func drawBaseIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // Background gradient (blue -> cyan)
    let colors = [
        NSColor(calibratedRed: 0.15, green: 0.47, blue: 0.99, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.10, green: 0.82, blue: 0.78, alpha: 1.0).cgColor
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    // Large squircle
    let radius = size * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    ctx.saveGState()
    path.addClip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    ctx.restoreGState()

    // Inner ring
    let ringInset = size * 0.08
    let ringRect = rect.insetBy(dx: ringInset, dy: ringInset)
    let ringPath = NSBezierPath(roundedRect: ringRect, xRadius: radius * 0.8, yRadius: radius * 0.8)
    NSColor.white.withAlphaComponent(0.25).setStroke()
    ringPath.lineWidth = size * 0.02
    ringPath.stroke()

    // Center glyph: letter C
    let glyph = "C"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let font = NSFont.systemFont(ofSize: size * 0.55, weight: .heavy)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]
    let attr = NSAttributedString(string: glyph, attributes: attributes)
    let textSize = attr.size()
    let textRect = CGRect(x: (size - textSize.width) / 2,
                          y: (size - textSize.height) / 2,
                          width: textSize.width,
                          height: textSize.height)
    attr.draw(in: textRect)

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateIcon", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try png.write(to: url)
}

let baseImage = drawBaseIcon(size: baseSize)

for spec in specs {
    let px = CGFloat(spec.size * spec.scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)

    let resized = NSImage(size: NSSize(width: px, height: px))
    resized.addRepresentation(rep)
    resized.lockFocus()
    baseImage.draw(in: CGRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1.0)
    resized.unlockFocus()

    try writePNG(resized, to: appIconPath.appendingPathComponent(spec.filename))
}

// Write Contents.json with filenames
let json: [String: Any] = [
    "images": specs.map { spec in
        [
            "idiom": "mac",
            "size": "\(spec.size)x\(spec.size)",
            "scale": "\(spec.scale)x",
            "filename": spec.filename
        ]
    },
    "info": ["author": "codex", "version": 1]
]

let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
try data.write(to: appIconPath.appendingPathComponent("Contents.json"))

print("Generated app icon set at \(appIconPath.path)")


import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210)
        NSColor(srgbRed: 0.06, green: 0.14, blue: 0.21, alpha: 1).setFill(); background.fill()
        let shadow = NSShadow(); shadow.shadowOffset = NSSize(width: 0, height: -18); shadow.shadowBlurRadius = 35
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
        let screen = NSBezierPath(roundedRect: NSRect(x: 180, y: 266, width: 664, height: 492), xRadius: 62, yRadius: 62)
        NSColor(srgbRed: 0.25, green: 0.54, blue: 0.66, alpha: 1).setFill(); screen.fill()
        NSShadow().set()
        screen.lineWidth = 12; NSColor(srgbRed: 0.67, green: 0.87, blue: 0.94, alpha: 1).setStroke(); screen.stroke()
        let page = NSBezierPath(roundedRect: NSRect(x: 260, y: 340, width: 328, height: 332), xRadius: 28, yRadius: 28)
        NSColor(srgbRed: 0.92, green: 0.97, blue: 0.98, alpha: 0.9).setFill(); page.fill()
        NSColor(srgbRed: 0.35, green: 0.58, blue: 0.65, alpha: 0.6).setStroke()
        for y in [420, 480, 540, 600] {
            let rule = NSBezierPath(); rule.lineWidth = 13
            rule.move(to: NSPoint(x: 306, y: y)); rule.line(to: NSPoint(x: 530, y: y)); rule.stroke()
        }
        let inset = NSBezierPath(roundedRect: NSRect(x: 556, y: 220, width: 330, height: 250), xRadius: 48, yRadius: 48)
        NSColor(srgbRed: 0.09, green: 0.22, blue: 0.3, alpha: 1).setFill(); inset.fill()
        inset.lineWidth = 13; NSColor.white.withAlphaComponent(0.9).setStroke(); inset.stroke()
        let lens = NSBezierPath(ovalIn: NSRect(x: 650, y: 278, width: 134, height: 134))
        NSColor(srgbRed: 0.62, green: 0.87, blue: 0.94, alpha: 1).setFill(); lens.fill()
        let inner = NSBezierPath(ovalIn: NSRect(x: 684, y: 312, width: 66, height: 66))
        NSColor(srgbRed: 0.12, green: 0.3, blue: 0.4, alpha: 1).setFill(); inner.fill()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon-\(size)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let json: [String: Any] = ["images": entries, "info": ["author": "Belweave", "version": 1]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
let assetInfo: [String: Any] = ["info": ["author": "Belweave", "version": 1]]
try JSONSerialization.data(withJSONObject: assetInfo, options: [.prettyPrinted, .sortedKeys]).write(to: folder.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Generated native Mac icon assets.")

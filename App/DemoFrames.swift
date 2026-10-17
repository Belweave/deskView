import AppKit
import CoreGraphics

/// Deliberately abstract test charts, distinct from a real camera feed.
@MainActor
enum DemoFrames {
    static func makeCamera() -> CGImage { make(isDesk: false) }
    static func makeDesk() -> CGImage { make(isDesk: true) }

    private static func make(isDesk: Bool) -> CGImage {
        let size = CGSize(width: 1280, height: 960)
        let image = NSImage(size: size)
        image.lockFocus()
        let bounds = CGRect(origin: .zero, size: size)
        NSColor(srgbRed: isDesk ? 0.18 : 0.08, green: isDesk ? 0.26 : 0.19, blue: isDesk ? 0.25 : 0.28, alpha: 1).setFill()
        bounds.fill()
        let colors: [NSColor] = [.systemTeal, .systemBlue, .systemIndigo, .systemOrange, .systemPink, .systemYellow]
        for (index, color) in colors.enumerated() {
            color.withAlphaComponent(0.7).setFill()
            CGRect(x: CGFloat(index) * size.width / 6, y: 0, width: size.width / 6 + 1, height: 180).fill()
        }
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let line = NSBezierPath(); line.lineWidth = 2
        line.move(to: CGPoint(x: 640, y: 220)); line.line(to: CGPoint(x: 640, y: 800))
        line.move(to: CGPoint(x: 200, y: 480)); line.line(to: CGPoint(x: 1080, y: 480)); line.stroke()
        let symbol = NSImage(systemSymbolName: isDesk ? "square.and.pencil" : "person.crop.rectangle", accessibilityDescription: nil)!
        let white = symbol.withSymbolConfiguration(.init(paletteColors: [.white]))!
        white.draw(in: CGRect(x: 500, y: 470, width: 280, height: 220))
        let title = isDesk ? "DESK VIEW" : "CAMERA"
        title.draw(at: CGPoint(x: 90, y: 340), withAttributes: [
            .font: NSFont.systemFont(ofSize: 70, weight: .semibold), .foregroundColor: NSColor.white
        ])
        "DEMO TEST CHART · NO LIVE CAMERA".draw(at: CGPoint(x: 94, y: 280), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 25, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.8)
        ])
        image.unlockFocus()
        var rect = bounds
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }
}

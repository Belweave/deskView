import DeskViewKit
import MetalKit
import OSLog
import SwiftUI

/// Video redraws on Metal's display cadence without publishing frame images
/// through ObservableObject or rebuilding the surrounding SwiftUI controls.
struct MetalPreview: NSViewRepresentable {
    let stream: PreviewStream
    var content: PreviewContent = .composed
    var label = "Composed recording preview"

    func makeCoordinator() -> Coordinator { Coordinator(stream: stream, content: content) }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = true
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel(label)
        context.coordinator.renderer = view.device.flatMap { MetalPreviewRenderer(device: $0) }
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.content = content
        view.setAccessibilityLabel(label)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        let stream: PreviewStream
        var content: PreviewContent
        var renderer: MetalPreviewRenderer?
        private let logger = Logger(subsystem: "org.belweave.deskView", category: "preview-performance")
        private var reportStart: TimeInterval?
        private var renderedFrames = 0
        private var previousCompleted = 0
        private var previousGPUSeconds: Double = 0
        init(stream: PreviewStream, content: PreviewContent) { self.stream = stream; self.content = content }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard view.window?.isVisible == true, view.window?.isMiniaturized == false,
                  let renderer, let frame = stream.snapshot(), let drawable = view.currentDrawable else { return }
            let image = switch content {
            case .composed: frame.image
            case .camera: frame.camera
            case .desk: frame.desk
            }
            if renderer.render(image, to: drawable.texture, fitting: content == .composed, drawable: drawable) {
                renderedFrames += 1
            }
            let now = ProcessInfo.processInfo.systemUptime
            if reportStart == nil { reportStart = now }
            if let start = reportStart, now - start >= 5 {
                let stats = renderer.statistics
                let completed = stats.completedFrames - previousCompleted
                let fps = Double(renderedFrames) / (now - start)
                let gpuMS = (stats.gpuSeconds - previousGPUSeconds) * 1000 / Double(max(completed, 1))
                logger.info("\(String(describing: self.content), privacy: .public): \(fps, format: .fixed(precision: 2)) fps, GPU \(gpuMS, format: .fixed(precision: 3)) ms, skipped \(stats.skippedFrames)")
                reportStart = now; renderedFrames = 0
                previousCompleted = stats.completedFrames; previousGPUSeconds = stats.gpuSeconds
            }
        }
    }
}

import CoreImage
import Metal
import QuartzCore
import Synchronization

/// Encodes directly into an IOSurface-backed drawable. At most two frames can
/// be in flight; the UI never waits for the GPU or an encoder to catch up.
public final class MetalPreviewRenderer: @unchecked Sendable {
    // These retained Metal resources belong to one queue submission. Only the
    // encoder/GPU writes the texture; CPU-side resource metadata is immutable.
    private struct Destination: @unchecked Sendable {
        let texture: MTLTexture
        let drawable: CAMetalDrawable?
    }
    public struct Statistics: Sendable {
        public var completedFrames = 0
        public var skippedFrames = 0
        public var gpuSeconds: Double = 0
        public var maximumGPUSeconds: Double = 0
    }
    private let queue: MTLCommandQueue
    private let encodingQueue = DispatchQueue(label: "org.belweave.deskView.preview-encoding", qos: .userInteractive)
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let inFlight = DispatchSemaphore(value: 2)
    private let counters = Mutex(Statistics())

    public init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        context = CIContext(mtlCommandQueue: queue, options: [.cacheIntermediates: false, .name: "deskView preview"])
    }

    public var statistics: Statistics { counters.withLock { $0 } }

    @discardableResult
    public func render(_ image: CIImage?, to texture: MTLTexture, fitting: Bool = true,
                       drawable: CAMetalDrawable? = nil) -> Bool {
        guard inFlight.wait(timeout: .now()) == .success else {
            counters.withLock { $0.skippedFrames += 1 }
            return false
        }
        let destination = Destination(texture: texture, drawable: drawable)
        encodingQueue.async { [self, destination] in
            autoreleasepool { encode(image, to: destination.texture, fitting: fitting, drawable: destination.drawable) }
        }
        return true
    }

    private func encode(_ image: CIImage?, to texture: MTLTexture, fitting: Bool, drawable: CAMetalDrawable?) {
        guard let command = queue.makeCommandBuffer() else { inFlight.signal(); return }
        let bounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        var result = CIImage(color: .black).cropped(to: bounds)
        if let image, image.extent.width > 0, image.extent.height > 0 {
            let sx = bounds.width / image.extent.width
            let sy = bounds.height / image.extent.height
            let scale = fitting ? min(sx, sy) : max(sx, sy)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let centered = scaled.transformed(by: CGAffineTransform(
                translationX: bounds.midX - scaled.extent.midX,
                y: bounds.midY - scaled.extent.midY))
            result = centered.composited(over: result).cropped(to: bounds)
        }
        context.render(result, to: texture, commandBuffer: command, bounds: bounds, colorSpace: colorSpace)
        if let drawable { command.present(drawable) }
        command.addCompletedHandler { [self, result] completed in
            // Keep the source CVPixelBuffers alive for asynchronous GPU work.
            withExtendedLifetime(result) {}
            counters.withLock {
                $0.completedFrames += 1
                let duration = max(0, completed.gpuEndTime - completed.gpuStartTime)
                $0.gpuSeconds += duration
                $0.maximumGPUSeconds = max($0.maximumGPUSeconds, duration)
            }
            inFlight.signal()
        }
        command.commit()
    }
}

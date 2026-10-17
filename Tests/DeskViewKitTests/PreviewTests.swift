import CoreImage
import CoreVideo
import Metal
import Synchronization
import Testing
@testable import DeskViewKit

@Suite(.serialized)
struct PreviewTests {
    @Test func incomingFramesReplaceBacklogAndExpireFromArrivalTime() throws {
        let frames = LatestVideoFrames()
        let old = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let newest = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 64))
        for index in 0..<10_000 { frames.receive(old, channel: .camera, at: Double(index) / 10_000) }
        frames.receive(newest, channel: .camera, at: 1)
        frames.receive(old, channel: .desk, at: 0)
        #expect(frames.fresh(at: 2.5).0?.extent.width == 128)
        #expect(frames.fresh(at: 2.5).1 == nil)
        #expect(frames.fresh(at: 3).0 == nil)
        frames.clear(.camera)
        #expect(frames.fresh(at: 1).0 == nil)
    }

    @Test func previewPublishesAtSixtyHzWithoutPerFrameUIObservation() async throws {
        let pipeline = StudioPipeline()
        let updates = Mutex(0)
        pipeline.onPreview = { _ in updates.withLock { $0 += 1 } }
        let context = CIContext()
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let cg = try #require(context.createCGImage(source, from: source.extent))
        pipeline.setDemo(camera: cg, desk: cg)
        pipeline.start()
        defer { pipeline.shutdown() }
        try await Task.sleep(for: .milliseconds(200))
        let start = pipeline.previewStream.sequence
        try await Task.sleep(for: .seconds(1))
        let published = pipeline.previewStream.sequence - start
        // Allow scheduler contention in virtualized CI, while rejecting the old
        // 15/30 Hz paths. The hardware benchmark reports the actual cadence.
        #expect(published >= 45 && published <= 75)
        #expect(pipeline.previewStream.snapshot()?.image.extent.size == CGSize(width: 1920, height: 1080))
        #expect(updates.withLock { $0 } == 1)
        let frame = try #require(pipeline.previewStream.snapshot())
        let buffer = try #require(frame.camera?.pixelBuffer)
        #expect(CVPixelBufferGetIOSurface(buffer) != nil)
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Requires a Metal device"))
    func metalPreviewRendersCompositionPixelsAndLetterboxing() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalPreviewRenderer(device: device))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 128, height: 128, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 64))
        #expect(renderer.render(image, to: texture))
        for _ in 0..<500 {
            if renderer.statistics.completedFrames == 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(renderer.statistics.completedFrames == 1)
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: 4, from: MTLRegionMake2D(64, 64, 1, 1), mipmapLevel: 0)
        }
        #expect(pixel[2] > 240 && pixel[0] < 10)
        pixel.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: 4, from: MTLRegionMake2D(64, 4, 1, 1), mipmapLevel: 0)
        }
        #expect(pixel[0] < 10 && pixel[1] < 10 && pixel[2] < 10)
    }
}

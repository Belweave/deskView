import AVFoundation
import CoreImage
import DeskViewKit
import Metal

/// Synthetic-only performance harness. It never discovers or opens a camera.
@main struct DeskViewBench {
    static func main() async throws {
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                                                             reason: "Measure real-time video rendering and encoding")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        guard let device = MTLCreateSystemDefaultDevice() else { throw StudioError.unavailable("Metal is unavailable.") }
        let seconds = min(30, max(2, Double(CommandLine.arguments.dropFirst().first ?? "5") ?? 5))
        let camera = try chart(alternate: false), desk = try chart(alternate: true)
        for quality in OutputQuality.allCases {
            let pipeline = StudioPipeline()
            var config = StudioConfiguration(); config.quality = quality; config.framesPerSecond = 60
            pipeline.update(config); pipeline.setDemo(camera: camera, desk: desk); pipeline.start()
            let renderers = try (0..<3).map { _ -> MetalPreviewRenderer in
                guard let renderer = MetalPreviewRenderer(device: device) else { throw StudioError.unavailable("Metal queue is unavailable.") }
                return renderer
            }
            let textures = try [(1920, 1080), (432, 252), (432, 252)].map { size -> MTLTexture in
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size.0, height: size.1, mipmapped: false)
                descriptor.storageMode = .private; descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
                guard let texture = device.makeTexture(descriptor: descriptor) else { throw StudioError.unavailable("Metal texture is unavailable.") }
                return texture
            }
            func draw() {
                guard let frame = pipeline.previewStream.snapshot() else { return }
                for (index, image) in [frame.image, frame.camera, frame.desk].enumerated() {
                    renderers[index].render(image, to: textures[index], fitting: index == 0)
                }
            }
            // Warm up Core Image's shaders and source texture uploads.
            for _ in 0..<60 { draw(); try await Task.sleep(for: .nanoseconds(16_666_667)) }
            let beforeRecording = renderers.map(\.statistics)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("deskview-benchmark-\(UUID().uuidString).mov")
            defer { pipeline.shutdown(); try? FileManager.default.removeItem(at: url) }
            try await pipeline.startRecording(to: url, includesAudio: false)
            // Report cold encoder startup separately from sustained cadence.
            // Continue drawing while the hardware encoder initializes.
            for _ in 0..<60 { draw(); try await Task.sleep(for: .nanoseconds(16_666_667)) }
            let initial = renderers.map(\.statistics)
            let startupSkips = initial.enumerated().map { $0.element.skippedFrames - beforeRecording[$0.offset].skippedFrames }
            let clock = ContinuousClock(), start = ContinuousClock.now
            let initialSequence = pipeline.previewStream.sequence
            var deadline = start
            while start.duration(to: clock.now) < .seconds(seconds) {
                draw()
                deadline += .nanoseconds(16_666_667)
                try await clock.sleep(until: deadline, tolerance: .microseconds(200))
            }
            let measurement = start.duration(to: clock.now).components
            let elapsed = Double(measurement.attoseconds) / 1e18 + Double(measurement.seconds)
            let produced = pipeline.previewStream.sequence - initialSequence
            let stats = renderers.enumerated().map { index, renderer in
                let final = renderer.statistics, before = initial[index]
                let count = final.completedFrames - before.completedFrames
                return ["fps": Double(count) / elapsed,
                        "gpu_mean_ms": (final.gpuSeconds - before.gpuSeconds) * 1000 / Double(max(1, count)),
                        "skipped": Double(final.skippedFrames - before.skippedFrames)]
            }
            _ = try await pipeline.finishRecording()
            pipeline.shutdown()
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw StudioError.noFrames }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
            output.alwaysCopiesSampleData = false; reader.add(output); reader.startReading()
            var frames = 0
            while output.copyNextSampleBuffer() != nil { frames += 1 }
            guard reader.status == .completed else {
                throw StudioError.writer(reader.error?.localizedDescription ?? "The benchmark movie could not be decoded completely.")
            }
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            let result: [String: Any] = ["output": quality.title, "seconds": elapsed,
                "encoder_warmup_seconds": 1, "startup_surface_skips": startupSkips,
                "pipeline_fps": Double(produced) / elapsed, "surfaces": stats,
                "recorded_frames": frames, "recorded_seconds": duration, "recorded_fps": Double(frames) / duration]
            var report = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            report.append(0x0A)
            FileHandle.standardOutput.write(report)
            try FileManager.default.removeItem(at: url)
            guard Double(frames) / duration >= 59, Double(produced) / elapsed >= 59,
                  stats.allSatisfy({ ($0["fps"] ?? 0) >= 59 && ($0["skipped"] ?? 1) == 0 }) else {
                throw StudioError.unavailable("The 60 Hz performance budget was missed at \(quality.title). See the measurements above.")
            }
        }
    }

    private static func chart(alternate: Bool) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: 1920, height: 1080, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw StudioError.noFrames }
        for y in stride(from: 0, to: 1080, by: 60) {
            for x in stride(from: 0, to: 1920, by: 60) {
                let level = CGFloat((x / 60 + y / 60) % 2) * 0.4 + 0.2
                context.setFillColor(CGColor(red: alternate ? 0.2 : level, green: level, blue: alternate ? level : 0.2, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 60, height: 60))
            }
        }
        guard let image = context.makeImage() else { throw StudioError.noFrames }
        return image
    }
}

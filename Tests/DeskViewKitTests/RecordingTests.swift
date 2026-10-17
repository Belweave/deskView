@preconcurrency import AVFoundation
import CoreImage
import Synchronization
import Testing
@testable import DeskViewKit

struct RecordingTests {
    @Test func movieContainsComposedVideoAndMicrophoneTrack() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("presentation.mov")
        var config = StudioConfiguration(); config.quality = .hd; config.layout = .sideBySide
        let context = CIContext()
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: red.extent)
        let composed = FrameCompositor().compose(camera: red, desk: blue, configuration: config)
        let recorder = try MovieRecorder(url: url, configuration: config, includesAudio: true, context: context)
        for frame in 0..<30 {
            let time = CMTime(value: Int64(600 + frame), timescale: 30)
            try recorder.append(image: composed, at: time)
            // Audio intentionally begins 200 ms after video.
            if frame >= 6 { try recorder.append(audio: try audioSample(at: time)) }
            // Allow the real encoder to drain; this verifies file generation,
            // rather than mocking AVAssetWriter's ready-for-media-data state.
            try await Task.sleep(for: .milliseconds(15))
        }
        let finished = try await withCheckedThrowingContinuation { continuation in
            recorder.finish { continuation.resume(with: $0) }
        }
        #expect(finished == url)
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(videoTracks.count == 1)
        #expect(audioTracks.count == 1)
        let audio = try #require(audioTracks.first)
        let reader = try AVAssetReader(asset: asset)
        let decodedAudio = AVAssetReaderTrackOutput(track: audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32
        ])
        reader.add(decodedAudio)
        #expect(reader.startReading())
        var peak: Float = 0
        var signalStart: Double?
        while let audioBuffer = decodedAudio.copyNextSampleBuffer() {
            let block = try #require(CMSampleBufferGetDataBuffer(audioBuffer))
            var bytes = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
            #expect(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: &bytes) == noErr)
            let values = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            peak = max(peak, values.reduce(Float.zero) { max($0, abs($1)) })
            if signalStart == nil, let index = values.firstIndex(where: { abs($0) > 0.03 }) {
                signalStart = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(audioBuffer)) + Double(index) / 48_000
            }
        }
        #expect(peak > 0.03)
        // The movie may represent the delay as leading silence. Verify the
        // decoded signal's onset, not the audio track's edit-list start time.
        let onset = try #require(signalStart)
        #expect(onset > 0.15 && onset < 0.27)
        reader.cancelReading()
        let video = try #require(videoTracks.first)
        #expect(try await video.load(.naturalSize) == CGSize(width: 1280, height: 720))
        let duration = try await asset.load(.duration)
        #expect(CMTimeGetSeconds(duration) > 0.9)
        #expect(CMTimeGetSeconds(duration) < 1.2)
        let generator = AVAssetImageGenerator(asset: asset)
        let frame = try await generator.image(at: .zero).image
        #expect(frame.width == 1280)
        #expect(frame.height == 720)
        let decoded = CIImage(cgImage: frame)
        var left = [UInt8](repeating: 0, count: 4)
        var right = left
        context.render(decoded, toBitmap: &left, rowBytes: 4, bounds: CGRect(x: 100, y: 300, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        context.render(decoded, toBitmap: &right, rowBytes: 4, bounds: CGRect(x: 1100, y: 300, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        #expect(left[0] > 220 && left[2] < 40)
        #expect(right[2] > 220 && right[0] < 40)
    }

    @Test func emptyRecordingIsRejectedAndRemoved() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        let recorder = try MovieRecorder(url: url, configuration: StudioConfiguration(), includesAudio: false, context: CIContext())
        let result: Result<URL, Error> = await withCheckedContinuation { continuation in
            recorder.finish { continuation.resume(returning: $0) }
        }
        if case .success = result { Issue.record("A movie without video frames must fail.") }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func pipelineRequiresBothSourcesForPresentationRecording() async throws {
        let pipeline = StudioPipeline()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        do {
            try await pipeline.startRecording(to: url, includesAudio: false)
            Issue.record("Missing camera inputs must block recording.")
        } catch {
            #expect(error is StudioError)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        pipeline.shutdown()
    }

    @Test func snapshotUsesSelectedCanvasDimensions() async throws {
        let pipeline = StudioPipeline()
        let context = CIContext()
        let source = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let cg = try #require(context.createCGImage(source, from: source.extent))
        var config = StudioConfiguration(); config.quality = .hd; config.aspect = .portrait
        pipeline.update(config)
        pipeline.setDemo(camera: cg, desk: cg)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url); pipeline.shutdown() }
        try await pipeline.snapshot(to: url)
        let png = try #require(CIImage(contentsOf: url))
        #expect(png.extent.size == CGSize(width: 720, height: 1280))
    }

    @Test func interruptionRetainsRecordingOwnershipAndDuplicateStopsJoin() async throws {
        let pipeline = StudioPipeline()
        let context = CIContext()
        let source = CIImage(color: CIColor(red: 0, green: 0.8, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let cg = try #require(context.createCGImage(source, from: source.extent))
        var config = StudioConfiguration(); config.quality = .hd
        pipeline.update(config)
        pipeline.setDemo(camera: cg, desk: cg)
        pipeline.start()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { pipeline.shutdown(); try? FileManager.default.removeItem(at: folder) }
        let id = UUID()
        let url = folder.appendingPathComponent("interrupted.mov")
        try await pipeline.startRecording(to: url, includesAudio: false, id: id)
        try await Task.sleep(for: .milliseconds(200))
        // A stale Stop from another session cannot end this one.
        do {
            _ = try await pipeline.finishRecording(id: UUID())
            Issue.record("A different recording's Stop must be rejected.")
        } catch { #expect(error is StudioError) }
        await confirmation("Source loss begins finalization once", expectedCount: 1) { interrupted in
            pipeline.onRecordingFinalizing = { observedID, _ in
                #expect(observedID == id)
                interrupted()
            }
            pipeline.setDemo(camera: nil, desk: nil)
            try? await Task.sleep(for: .milliseconds(200))
        }
        async let first = pipeline.finishRecording(id: id)
        async let second = pipeline.finishRecording(id: id)
        let results = try await (first, second)
        #expect(results.0 == url && results.1 == url)
        let asset = AVURLAsset(url: url)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(CMTimeGetSeconds(try await asset.load(.duration)) > 0.1)
        // A subsequent session has its own identity and survives the old Stop.
        let nextID = UUID()
        let next = folder.appendingPathComponent("next.mov")
        pipeline.setDemo(camera: cg, desk: cg)
        try await pipeline.startRecording(to: next, includesAudio: false, id: nextID)
        do {
            _ = try await pipeline.finishRecording(id: id)
            Issue.record("An old Stop must not finalize a new recording.")
        } catch { #expect(error is StudioError) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await pipeline.finishRecording(id: nextID) == next)
    }

    @Test func unusedCameraFailureDoesNotAffectSingleSourceRecording() {
        #expect(!CaptureFailure.video(.desk, "Disconnected").affectsRecording(layout: .camera, includesAudio: true))
        #expect(!CaptureFailure.video(.camera, "Disconnected").affectsRecording(layout: .desk, includesAudio: false))
        #expect(CaptureFailure.video(.desk, "Disconnected").affectsRecording(layout: .pictureInPicture, includesAudio: false))
        #expect(CaptureFailure.video(.camera, "Disconnected").affectsRecording(layout: .sideBySide, includesAudio: false))
        #expect(!CaptureFailure.audio("Disconnected").affectsRecording(layout: .camera, includesAudio: false))
    }

    @Test func liveSampleBuffersExpireAndFinalizeAPlayableRecording() async throws {
        let pipeline = StudioPipeline()
        var config = StudioConfiguration(); config.quality = .hd
        pipeline.update(config)
        let id = UUID()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { pipeline.shutdown(); try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("live-samples.mov")
        let frame = try videoSample()
        pipeline.receive(MediaSample(frame), channel: .camera)
        pipeline.receive(MediaSample(frame), channel: .desk)
        pipeline.start()
        try await pipeline.startRecording(to: url, includesAudio: false, id: id)
        // Frames are delivered through the actual capture ingestion path,
        // rather than setDemo. Their two-second freshness lease then expires.
        try await Task.sleep(for: .milliseconds(2200))
        #expect(try await pipeline.finishRecording(id: id) == url)
        let asset = AVURLAsset(url: url)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        #expect(duration > 1.5 && duration < 2.3)
        do {
            try await pipeline.snapshot(to: folder.appendingPathComponent("stale.png"))
            Issue.record("Expired live frames must not be saved as a fresh snapshot.")
        } catch { #expect(error is StudioError) }
    }

    @Test func clearingLastLiveSourcePublishesUnavailablePreview() async throws {
        let pipeline = StudioPipeline()
        let latest = Mutex<PreviewFrame?>(nil)
        pipeline.onPreview = { frame in latest.withLock { $0 = frame } }
        var config = StudioConfiguration(); config.quality = .hd; config.layout = .camera
        pipeline.update(config)
        pipeline.receive(MediaSample(try videoSample()), channel: .camera)
        pipeline.start()
        defer { pipeline.shutdown() }
        for _ in 0..<100 {
            if latest.withLock({ $0?.cameraAvailable == true }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(latest.withLock { $0?.cameraAvailable == true })
        pipeline.clear(.camera)
        for _ in 0..<100 {
            if latest.withLock({ $0?.cameraAvailable == false }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let cleared = try #require(latest.withLock { $0 })
        #expect(!cleared.cameraAvailable && !cleared.deskAvailable)
        #expect(cleared.cameraThumbnail == nil && cleared.deskThumbnail == nil)
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(CIImage(cgImage: cleared.image), toBitmap: &pixel, rowBytes: 4,
                           bounds: CGRect(x: 100, y: 100, width: 1, height: 1), format: .RGBA8,
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        #expect(pixel[0] < 40 && pixel[1] < 40 && pixel[2] < 40)
    }

    private func videoSample() throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess)
        let pixel = try #require(pixelBuffer)
        let image = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        CIContext().render(image, to: pixel)
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }

    private func audioSample(at time: CMTime) throws -> CMSampleBuffer {
        var format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        #expect(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format, layoutSize: 0, layout: nil,
                                              magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr)
        let sampleCount = 1600
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: sampleCount * 4,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: sampleCount * 4, flags: 0, blockBufferOut: &block) == noErr)
        let start = CMTimeGetSeconds(time) * 48_000
        let data = (0..<sampleCount).map { Float(sin((start + Double($0)) * 2 * .pi * 440 / 48_000) * 0.1) }
        let audioBlock = try #require(block)
        _ = data.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: audioBlock, offsetIntoDestination: 0, dataLength: sampleCount * 4) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var sampleSize = 4
        #expect(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: audioBlock, formatDescription: description,
                                         sampleCount: sampleCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                         sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}

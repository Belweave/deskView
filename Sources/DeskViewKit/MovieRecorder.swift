import AVFoundation
import CoreImage
import Foundation

/// Confined to StudioPipeline's serial media queue. Audio and video use the
/// same host-clock timebase, with the first video frame defining time zero.
final class MovieRecorder: @unchecked Sendable {
    let url: URL
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let context: CIContext
    private var origin: CMTime?
    private var lastVideoTime = CMTime.invalid
    private var frameCount = 0
    private let frameRate: Int

    init(url: URL, configuration: StudioConfiguration, includesAudio: Bool, context: CIContext) throws {
        self.url = url
        self.context = context
        frameRate = configuration.safeFrameRate
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let size = configuration.outputSize
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(size.width * size.height * 7),
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2
            ]
        ])
        video.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(video) else { throw StudioError.writer("Video encoding is unavailable.") }
        writer.add(video)
        if includesAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw StudioError.writer("Audio encoding is unavailable.") }
            writer.add(input)
            audio = input
        } else { audio = nil }
        guard writer.startWriting() else { throw StudioError.writer(writer.error?.localizedDescription ?? "The encoder did not start.") }
    }

    func append(image: CIImage, at time: CMTime) throws {
        guard time.isValid, time.isNumeric else { return }
        if origin == nil {
            origin = time
            writer.startSession(atSourceTime: time)
        }
        guard !lastVideoTime.isValid || CMTimeCompare(time, lastVideoTime) > 0 else { return }
        guard writer.status == .writing else { throw StudioError.writer(writer.error?.localizedDescription ?? "The encoder stopped.") }
        guard video.isReadyForMoreMediaData else { return }
        guard let pool = adaptor.pixelBufferPool else { throw StudioError.writer("The video buffer pool is unavailable.") }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw StudioError.writer("Could not allocate a video frame (\(status)).") }
        context.render(image, to: buffer, bounds: image.extent, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw StudioError.writer(writer.error?.localizedDescription ?? "A video frame could not be written.")
        }
        lastVideoTime = time
        frameCount += 1
    }

    func append(audio sample: CMSampleBuffer) throws {
        guard let audio, let origin, writer.status == .writing,
              CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), origin) >= 0,
              audio.isReadyForMoreMediaData else { return }
        guard audio.append(sample) else {
            throw StudioError.writer(writer.error?.localizedDescription ?? "Microphone audio could not be written.")
        }
    }

    func finish(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        guard frameCount > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            completion(.failure(StudioError.noFrames))
            return
        }
        video.markAsFinished()
        audio?.markAsFinished()
        let end = CMTimeAdd(lastVideoTime, CMTime(value: 1, timescale: Int32(frameRate)))
        writer.endSession(atSourceTime: end)
        let url = url
        // No append calls follow finish; AVAssetWriter owns finalization until
        // this callback, and the recorder stays alive for its read-only result.
        writer.finishWriting { [self] in
            if writer.status == .completed { completion(.success(url)) }
            else { completion(.failure(StudioError.writer(writer.error?.localizedDescription ?? "The file did not finish saving."))) }
        }
    }

    func cancel() {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }
}

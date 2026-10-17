@preconcurrency import AVFoundation
import CoreImage
import Foundation

public struct PreviewFrame: @unchecked Sendable {
    public let image: CGImage
    public let cameraThumbnail: CGImage?
    public let deskThumbnail: CGImage?
    public let cameraAvailable: Bool
    public let deskAvailable: Bool
    public let isDemo: Bool
}

public struct MediaSample: @unchecked Sendable {
    public let buffer: CMSampleBuffer
    public init(_ buffer: CMSampleBuffer) { self.buffer = buffer }
}

private final class RecordingFinalization: @unchecked Sendable {
    let id: UUID
    let reason: String?
    var waiters: [@Sendable (Result<URL, Error>) -> Void] = []
    init(id: UUID, reason: String?) { self.id = id; self.reason = reason }
}

/// All mutable media state lives on one bounded serial queue. Capture delegates
/// only hand off the latest buffers; a timer composes at the output cadence.
public final class StudioPipeline: @unchecked Sendable {
    public var onPreview: (@Sendable (PreviewFrame) -> Void)?
    public var onRecordingFinalizing: (@Sendable (UUID, String) -> Void)?
    public var onRecordingInterrupted: (@Sendable (UUID, String, Result<URL, Error>) -> Void)?
    public var onAudioLevel: (@Sendable (Float) -> Void)?
    private let queue = DispatchQueue(label: "org.belweave.deskView.media", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let compositor = FrameCompositor()
    private var configuration = StudioConfiguration()
    private var timer: DispatchSourceTimer?
    private var camera: CIImage?
    private var desk: CIImage?
    private var cameraTime: TimeInterval = 0
    private var deskTime: TimeInterval = 0
    private var recorder: MovieRecorder?
    private var recordingID: UUID?
    private var finalization: RecordingFinalization?
    private var completedFinalization: (id: UUID, result: Result<URL, Error>)?
    private var demo = false
    private var demoCamera: CIImage?
    private var demoDesk: CIImage?
    private var tickIndex = 0
    private var previewNeedsRefresh = false

    public init() {}

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: 1.0 / 30, leeway: .milliseconds(3))
            source.setEventHandler { [weak self] in self?.renderTick() }
            source.resume()
            timer = source
        }
    }

    public func shutdown() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            recorder?.cancel()
            recorder = nil
            camera = nil
            desk = nil
        }
    }

    public func update(_ configuration: StudioConfiguration) {
        queue.async { [self] in
            guard recorder == nil, finalization == nil else { return }
            self.configuration = configuration
        }
    }

    public func setDemo(camera: CGImage?, desk: CGImage?) {
        queue.async { [self] in
            demo = camera != nil && desk != nil
            demoCamera = camera.map { CIImage(cgImage: $0) }
            demoDesk = desk.map { CIImage(cgImage: $0) }
            self.camera = nil
            self.desk = nil
            cameraTime = 0
            deskTime = 0
            previewNeedsRefresh = true
        }
    }

    public func clear(_ channel: CaptureChannel) {
        queue.async { [self] in
            switch channel {
            case .camera: camera = nil; cameraTime = 0
            case .desk: desk = nil; deskTime = 0
            }
            previewNeedsRefresh = true
        }
    }

    public func receive(_ sample: MediaSample, channel: CaptureChannel) {
        queue.async { [self] in
            guard !demo, let buffer = CMSampleBufferGetImageBuffer(sample.buffer) else { return }
            let image = CIImage(cvPixelBuffer: buffer)
            let now = ProcessInfo.processInfo.systemUptime
            switch channel {
            case .camera: camera = image; cameraTime = now
            case .desk: desk = image; deskTime = now
            }
        }
    }

    public func receiveAudio(_ sample: MediaSample) {
        queue.async { [self] in
            do { try recorder?.append(audio: sample.buffer) }
            catch { interrupt(error.localizedDescription) }
            // Peak level is derived from a Float32, noninterleaved capture buffer.
            guard let block = CMSampleBufferGetDataBuffer(sample.buffer) else { return }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
                  let pointer, length >= MemoryLayout<Float>.size else { return }
            let description = CMSampleBufferGetFormatDescription(sample.buffer)
                .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
            guard let description, description.mFormatID == kAudioFormatLinearPCM,
                  description.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  description.mBitsPerChannel == 32 else { return }
            let values = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
            var peak: Float = 0
            for index in 0..<(length / MemoryLayout<Float>.size) { peak = max(peak, abs(values[index])) }
            onAudioLevel?(min(peak, 1))
        }
    }

    public func startRecording(to url: URL, includesAudio: Bool, id: UUID = UUID()) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard recorder == nil, finalization == nil else { throw StudioError.recordingInProgress }
                    let inputs = freshInputs()
                    guard requiredInputsExist(camera: inputs.0, desk: inputs.1) else { throw StudioError.noFrames }
                    recorder = try MovieRecorder(url: url, configuration: configuration, includesAudio: includesAudio, context: context)
                    recordingID = id
                    completedFinalization = nil
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func finishRecording(id: UUID? = nil) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if recorder == nil, finalization == nil, let id, let completedFinalization, completedFinalization.id == id {
                    continuation.resume(with: completedFinalization.result)
                    return
                }
                if let finalization, id == nil || id == finalization.id {
                    finalization.waiters.append { continuation.resume(with: $0) }
                    return
                }
                guard let current = recorder, let recordingID, id == nil || id == recordingID else {
                    continuation.resume(throwing: StudioError.unavailable("There is no active recording."))
                    return
                }
                beginFinalization(current, id: recordingID, reason: nil, waiter: { continuation.resume(with: $0) })
            }
        }
    }

    public func snapshot(to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    let inputs = freshInputs()
                    guard requiredInputsExist(camera: inputs.0, desk: inputs.1) else { throw StudioError.noFrames }
                    let image = compositor.compose(camera: inputs.0, desk: inputs.1, configuration: configuration)
                    try context.writePNGRepresentation(of: image, to: url, format: .RGBA8,
                                                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func freshInputs() -> (CIImage?, CIImage?) {
        if demo { return (demoCamera, demoDesk) }
        let now = ProcessInfo.processInfo.systemUptime
        return (now - cameraTime < 2 ? camera : nil, now - deskTime < 2 ? desk : nil)
    }

    private func requiredInputsExist(camera: CIImage?, desk: CIImage?) -> Bool {
        (!configuration.layout.needsCamera || camera != nil) && (!configuration.layout.needsDesk || desk != nil)
    }

    private func renderTick() {
        autoreleasepool {
            guard previewNeedsRefresh || demo || camera != nil || desk != nil || recorder != nil else { return }
            tickIndex += 1
            // A 30 Hz preview keeps controls responsive; 24 fps files get a 24 Hz
            // timestamp schedule using the same monotonic host clock as audio.
            let inputs = freshInputs()
            if recorder != nil && !requiredInputsExist(camera: inputs.0, desk: inputs.1) {
                interrupt("A camera stopped delivering frames. The available portion of your recording was saved.")
            }
            let image = compositor.compose(camera: inputs.0, desk: inputs.1, configuration: configuration)
            if let recorder {
                let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
                let seconds = CMTimeGetSeconds(hostTime)
                let frame = Int64((seconds * Double(configuration.safeFrameRate)).rounded(.down))
                let quantized = CMTime(value: frame, timescale: Int32(configuration.safeFrameRate))
                do { try recorder.append(image: image, at: quantized) }
                catch { interrupt(error.localizedDescription) }
            }
            // Render UI previews at 15 Hz; recording remains at the selected cadence.
            guard tickIndex % 2 == 0 else { return }
            let scale = min(1, 1280 / image.extent.width)
            let preview = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cgImage = context.createCGImage(preview, from: preview.extent) else { return }
            func thumbnail(_ source: CIImage?) -> CGImage? {
                guard let source else { return nil }
                let scale = 240 / source.extent.width
                let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                return context.createCGImage(small, from: small.extent)
            }
            onPreview?(PreviewFrame(image: cgImage,
                                    cameraThumbnail: thumbnail(inputs.0), deskThumbnail: thumbnail(inputs.1),
                                    cameraAvailable: inputs.0 != nil, deskAvailable: inputs.1 != nil, isDemo: demo))
            previewNeedsRefresh = false
        }
    }

    private func interrupt(_ message: String) {
        guard let current = recorder, let recordingID else { return }
        beginFinalization(current, id: recordingID, reason: message)
    }

    private func beginFinalization(_ current: MovieRecorder, id: UUID, reason: String?, waiter: (@Sendable (Result<URL, Error>) -> Void)? = nil) {
        let operation = RecordingFinalization(id: id, reason: reason)
        if let waiter { operation.waiters.append(waiter) }
        finalization = operation
        recorder = nil
        recordingID = nil
        if let reason { onRecordingFinalizing?(id, reason) }
        current.finish { [self] result in
            queue.async { [self] in
                guard finalization === operation else { return }
                finalization = nil
                completedFinalization = (operation.id, result)
                if let reason = operation.reason { onRecordingInterrupted?(operation.id, reason, result) }
                for waiter in operation.waiters { waiter(result) }
            }
        }
    }
}

@preconcurrency import AVFoundation
import CoreImage
import Foundation

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
    public let previewStream = PreviewStream()
    private let queue = DispatchQueue(label: "org.belweave.deskView.media", qos: .userInitiated)
    private let snapshotQueue = DispatchQueue(label: "org.belweave.deskView.snapshots", qos: .utility)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let compositor = FrameCompositor()
    private var configuration = StudioConfiguration()
    private var timer: DispatchSourceTimer?
    private let latestVideo = LatestVideoFrames()
    private var recorder: RecordingWorker?
    private var recordingClockOrigin: CMTime?
    private var lastRecordingSlot: Int64 = -1
    private var recordingID: UUID?
    private var finalization: RecordingFinalization?
    private var completedFinalization: (id: UUID, result: Result<URL, Error>)?
    private var demo = false
    private var demoCamera: CIImage?
    private var demoDesk: CIImage?
    private var previewNeedsRefresh = false
    private var previousAvailability: (camera: Bool, desk: Bool, demo: Bool)?
    private var lastAudioLevelTime: TimeInterval = 0
    private var realTimeActivity: NSObjectProtocol?

    public init() {}

    deinit {
        if let realTimeActivity { ProcessInfo.processInfo.endActivity(realTimeActivity) }
    }

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: 1.0 / 60, leeway: .microseconds(500))
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
            latestVideo.clear()
            previewStream.clear()
            updateRealTimeActivity(active: false)
        }
    }

    public func update(_ configuration: StudioConfiguration) {
        queue.async { [self] in
            guard recorder == nil, finalization == nil else { return }
            self.configuration = configuration
        }
    }

    public func setDemo(camera: CGImage?, desk: CGImage?) {
        latestVideo.clear()
        queue.async { [self] in
            demo = camera != nil && desk != nil
            demoCamera = camera.flatMap(makeDemoImage)
            demoDesk = desk.flatMap(makeDemoImage)
            previewNeedsRefresh = true
        }
    }

    private func makeDemoImage(_ image: CGImage) -> CIImage? {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                       kCVPixelBufferMetalCompatibilityKey as String: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height,
                                  kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        // Upload a bitmap test chart once. Rebinding a CGImage on every draw
        // repeatedly compresses/uploads it on the CPU in each Metal context.
        context.render(CIImage(cgImage: image), to: buffer,
                       bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return CIImage(cvPixelBuffer: buffer)
    }

    public func clear(_ channel: CaptureChannel) {
        latestVideo.clear(channel)
        queue.async { [self] in
            previewNeedsRefresh = true
        }
    }

    public func receive(_ sample: MediaSample, channel: CaptureChannel) {
        guard let buffer = CMSampleBufferGetImageBuffer(sample.buffer) else { return }
        latestVideo.receive(CIImage(cvPixelBuffer: buffer), channel: channel,
                            at: ProcessInfo.processInfo.systemUptime)
    }

    public func receiveAudio(_ sample: MediaSample) {
        queue.async { [self] in
            recorder?.append(audio: sample.buffer)
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastAudioLevelTime >= 0.1 else { return }
            lastAudioLevelTime = now
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
                    recorder = try RecordingWorker(url: url, configuration: configuration, includesAudio: includesAudio, context: context) { [weak self] message in
                        self?.queue.async { [weak self] in
                            guard let self, recordingID == id else { return }
                            interrupt(message)
                        }
                    }
                    recordingID = id
                    recordingClockOrigin = nil
                    lastRecordingSlot = -1
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
                    snapshotQueue.async { [context] in
                        do {
                            try context.writePNGRepresentation(of: image, to: url, format: .RGBA8,
                                                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                            continuation.resume()
                        } catch { continuation.resume(throwing: error) }
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func freshInputs() -> (CIImage?, CIImage?) {
        if demo { return (demoCamera, demoDesk) }
        return latestVideo.fresh(at: ProcessInfo.processInfo.systemUptime)
    }

    private func requiredInputsExist(camera: CIImage?, desk: CIImage?) -> Bool {
        (!configuration.layout.needsCamera || camera != nil) && (!configuration.layout.needsDesk || desk != nil)
    }

    private func renderTick() {
        autoreleasepool {
            let inputs = freshInputs()
            updateRealTimeActivity(active: demo || inputs.0 != nil || inputs.1 != nil || recorder != nil || finalization != nil)
            let availabilityChanged = previousAvailability?.camera != (inputs.0 != nil) ||
                previousAvailability?.desk != (inputs.1 != nil) || previousAvailability?.demo != demo
            guard previewNeedsRefresh || availabilityChanged || demo || inputs.0 != nil || inputs.1 != nil || recorder != nil else { return }
            if recorder != nil && !requiredInputsExist(camera: inputs.0, desk: inputs.1) {
                interrupt("A camera stopped delivering frames. The available portion of your recording was saved.")
            }
            let image = compositor.compose(camera: inputs.0, desk: inputs.1, configuration: configuration)
            if let recorder {
                let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
                if recordingClockOrigin == nil { recordingClockOrigin = hostTime }
                let origin = recordingClockOrigin!
                let elapsed = CMTimeGetSeconds(CMTimeSubtract(hostTime, origin))
                let slot = Int64((elapsed * Double(configuration.safeFrameRate)).rounded())
                if slot > lastRecordingSlot {
                    let time = CMTimeAdd(origin, CMTime(value: slot, timescale: Int32(configuration.safeFrameRate)))
                    recorder.append(image: image, at: time)
                    lastRecordingSlot = slot
                }
            }
            let frame = PreviewFrame(image: image, camera: inputs.0, desk: inputs.1, isDemo: demo)
            previewStream.publish(frame)
            // SwiftUI only observes availability changes, never video frames.
            if availabilityChanged { onPreview?(frame) }
            previousAvailability = (inputs.0 != nil, inputs.1 != nil, demo)
            previewNeedsRefresh = false
        }
    }

    private func updateRealTimeActivity(active: Bool) {
        if active && realTimeActivity == nil {
            realTimeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Live camera studio preview and recording")
        } else if !active, let activity = realTimeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            realTimeActivity = nil
        }
    }

    private func interrupt(_ message: String) {
        guard let current = recorder, let recordingID else { return }
        beginFinalization(current, id: recordingID, reason: message)
    }

    private func beginFinalization(_ current: RecordingWorker, id: UUID, reason: String?, waiter: (@Sendable (Result<URL, Error>) -> Void)? = nil) {
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

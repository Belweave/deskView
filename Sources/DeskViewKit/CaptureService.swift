@preconcurrency import AVFoundation
import Foundation

public struct AudioDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
}

public struct VideoEffectsState: Equatable, Sendable {
    public var supportsCenterStage = false
    public var centerStage = false
    public var portrait = false
    public var studioLight = false
    public var backgroundReplacement = false
    public var reactions = false
    public init() {}
}

private final class SampleDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                                    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let handler: @Sendable (MediaSample) -> Void
    init(handler: @escaping @Sendable (MediaSample) -> Void) { self.handler = handler }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        handler(MediaSample(sampleBuffer))
    }
}

/// Session mutations and device configuration are isolated on `queue`, never
/// the UI thread. Two video sessions allow the paired camera and Desk View
/// streams to run independently; audio has a third, optional session.
public final class CaptureService: @unchecked Sendable {
    public var onDevicesChanged: (@Sendable ([CameraDescriptor], [AudioDescriptor]) -> Void)?
    public var onError: (@Sendable (CaptureFailure) -> Void)?
    private let queue = DispatchQueue(label: "org.belweave.deskView.capture", qos: .userInitiated)
    private let sampleQueue = DispatchQueue(label: "org.belweave.deskView.samples", qos: .userInitiated)
    private let videoDiscovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
        mediaType: .video, position: .unspecified)
    private let audioDiscovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
    private let pipeline: StudioPipeline
    private var cameraSession: AVCaptureSession?
    private var deskSession: AVCaptureSession?
    private var audioSession: AVCaptureSession?
    private var cameraDevice: AVCaptureDevice?
    private var delegates: [String: SampleDelegate] = [:]
    private var observations: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []

    public init(pipeline: StudioPipeline) {
        self.pipeline = pipeline
        observations = [
            videoDiscovery.observe(\.devices, options: [.new]) { [weak self] _, _ in self?.refreshDevices() },
            audioDiscovery.observe(\.devices, options: [.new]) { [weak self] _, _ in self?.refreshDevices() }
        ]
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                guard let self, let session = notification.object as? AVCaptureSession else { return }
                let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                self.queue.async {
                    guard session === self.cameraSession || session === self.deskSession || session === self.audioSession else { return }
                    let detail = message ?? "Capture was interrupted. Reconnect the source and start the preview again."
                    session.stopRunning()
                    let failure: CaptureFailure
                    if session === self.cameraSession {
                        self.cameraSession = nil; self.cameraDevice = nil; self.delegates[CaptureChannel.camera.rawValue] = nil
                        self.pipeline.clear(.camera)
                        failure = .video(.camera, detail)
                    } else if session === self.deskSession {
                        self.deskSession = nil; self.delegates[CaptureChannel.desk.rawValue] = nil
                        self.pipeline.clear(.desk)
                        failure = .video(.desk, detail)
                    } else {
                        self.audioSession = nil; self.delegates["audio"] = nil
                        failure = .audio(detail)
                    }
                    self.onError?(failure)
                }
            })
        }
    }

    deinit { notifications.forEach(NotificationCenter.default.removeObserver) }

    public func refreshDevices() {
        queue.async { [self] in
            let video = videoDiscovery.devices.map {
                CameraDescriptor(id: $0.uniqueID, name: $0.localizedName, isContinuityCamera: $0.isContinuityCamera,
                                 isDeskView: $0.deviceType == .deskViewCamera,
                                 companionDeskID: $0.companionDeskViewCamera?.uniqueID)
            }.sorted { lhs, rhs in
                if lhs.isContinuityCamera != rhs.isContinuityCamera { return lhs.isContinuityCamera }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            let audio = audioDiscovery.devices.map { AudioDescriptor(id: $0.uniqueID, name: $0.localizedName) }
            onDevicesChanged?(video, audio)
        }
    }

    public func selectVideo(id: String?, channel: CaptureChannel) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                let previous = channel == .camera ? cameraSession : deskSession
                previous?.stopRunning()
                pipeline.clear(channel)
                guard let id else {
                    if channel == .camera { cameraSession = nil; cameraDevice = nil }
                    else { deskSession = nil }
                    delegates[channel.rawValue] = nil
                    continuation.resume()
                    return
                }
                do {
                    guard let device = videoDiscovery.devices.first(where: { $0.uniqueID == id }), device.isConnected else {
                        throw StudioError.unavailable("This camera is no longer connected. Choose another source or reconnect your iPhone.")
                    }
                    let session = AVCaptureSession()
                    session.beginConfiguration()
                    // 1080p is a source request, not the composed output resolution.
                    // Desk View may expose 1920×1440 and is allowed its native format.
                    if channel == .camera, session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
                    else if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { throw StudioError.unavailable("macOS could not open this camera. Close any app that is holding it and try again.") }
                    session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                    let delegate = SampleDelegate { [pipeline] sample in pipeline.receive(sample, channel: channel) }
                    output.setSampleBufferDelegate(delegate, queue: sampleQueue)
                    guard session.canAddOutput(output) else { throw StudioError.unavailable("This camera cannot supply a video stream in the current configuration.") }
                    session.addOutput(output)
                    if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    session.commitConfiguration()
                    if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                        do {
                            try device.lockForConfiguration()
                            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                            device.unlockForConfiguration()
                        } catch { /* A shared camera may retain the system's frame rate. */ }
                    }
                    delegates[channel.rawValue] = delegate
                    if channel == .camera {
                        cameraSession = session
                        cameraDevice = device
                        AVCaptureDevice.userPreferredCamera = device
                    } else { deskSession = session }
                    session.startRunning()
                    guard session.isRunning else { throw StudioError.unavailable("The camera did not start. Check the iPhone connection and try again.") }
                    continuation.resume()
                } catch {
                    if channel == .camera { cameraSession = nil; cameraDevice = nil }
                    else { deskSession = nil }
                    delegates[channel.rawValue] = nil
                    pipeline.clear(channel)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func selectAudio(id: String?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                audioSession?.stopRunning()
                audioSession = nil
                delegates["audio"] = nil
                guard let id else { continuation.resume(); return }
                do {
                    guard let device = audioDiscovery.devices.first(where: { $0.uniqueID == id }) else {
                        throw StudioError.unavailable("The selected microphone is disconnected. Select another microphone or record without audio.")
                    }
                    let session = AVCaptureSession()
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioDataOutput()
                    output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM,
                                            AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32]
                    guard session.canAddInput(input) else { throw StudioError.unavailable("The microphone is unavailable.") }
                    session.addInput(input)
                    guard session.canAddOutput(output) else { throw StudioError.unavailable("Microphone capture is unavailable.") }
                    let delegate = SampleDelegate { [pipeline] in pipeline.receiveAudio($0) }
                    output.setSampleBufferDelegate(delegate, queue: sampleQueue)
                    session.addOutput(output)
                    delegates["audio"] = delegate
                    audioSession = session
                    session.startRunning()
                    guard session.isRunning else { throw StudioError.unavailable("The microphone did not start.") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func stopAll() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                cameraSession?.stopRunning(); deskSession?.stopRunning(); audioSession?.stopRunning()
                cameraSession = nil; deskSession = nil; audioSession = nil; cameraDevice = nil
                delegates.removeAll()
                pipeline.clear(.camera); pipeline.clear(.desk)
                continuation.resume()
            }
        }
    }

    public func effects() async -> VideoEffectsState {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var state = VideoEffectsState()
                state.supportsCenterStage = cameraDevice?.activeFormat.isCenterStageSupported ?? false
                state.centerStage = cameraDevice?.isCenterStageActive ?? false
                state.portrait = cameraDevice?.isPortraitEffectActive ?? false
                state.studioLight = cameraDevice?.isStudioLightActive ?? false
                state.backgroundReplacement = cameraDevice?.isBackgroundReplacementActive ?? false
                state.reactions = cameraDevice?.canPerformReactionEffects ?? false
                continuation.resume(returning: state)
            }
        }
    }

    public func setCenterStage(_ enabled: Bool) async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if cameraDevice?.activeFormat.isCenterStageSupported == true {
                    AVCaptureDevice.centerStageControlMode = .cooperative
                    AVCaptureDevice.isCenterStageEnabled = enabled
                }
                continuation.resume()
            }
        }
    }

    public func performReaction(_ type: AVCaptureReactionType) {
        queue.async { [self] in
            guard let device = cameraDevice, device.canPerformReactionEffects,
                  device.availableReactionTypes.contains(type) else { return }
            device.performEffect(for: type)
        }
    }
}

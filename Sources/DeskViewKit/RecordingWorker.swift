import AVFoundation
import CoreImage

/// GPU-to-encoder synchronization belongs here, away from preview composition.
/// One encoding frame and one pending frame bound both latency and memory.
final class RecordingWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.belweave.deskView.encoder", qos: .userInitiated)
    private let videoSlots = DispatchSemaphore(value: 2)
    private let audioSlots = DispatchSemaphore(value: 16)
    private let recorder: MovieRecorder
    private let onError: @Sendable (String) -> Void

    init(url: URL, configuration: StudioConfiguration, includesAudio: Bool, context: CIContext,
         onError: @escaping @Sendable (String) -> Void) throws {
        recorder = try MovieRecorder(url: url, configuration: configuration, includesAudio: includesAudio, context: context)
        self.onError = onError
    }

    func append(image: CIImage, at time: CMTime) {
        guard videoSlots.wait(timeout: .now()) == .success else { return }
        queue.async { [self] in
            defer { videoSlots.signal() }
            autoreleasepool {
                do { try recorder.append(image: image, at: time) }
                catch { onError(error.localizedDescription) }
            }
        }
    }

    func append(audio sample: CMSampleBuffer) {
        guard audioSlots.wait(timeout: .now()) == .success else { return }
        let media = MediaSample(sample)
        queue.async { [self] in
            defer { audioSlots.signal() }
            do { try recorder.append(audio: media.buffer) }
            catch { onError(error.localizedDescription) }
        }
    }

    func finish(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        queue.async { [self] in recorder.finish(completion: completion) }
    }

    func cancel() { queue.async { [self] in recorder.cancel() } }
}

import CoreImage
import Foundation
import Synchronization

/// Immutable Core Image graphs retain their capture buffers until Metal is done.
/// No video pixels cross the CPU or SwiftUI observation on the preview path.
public struct PreviewFrame: @unchecked Sendable {
    public let image: CIImage
    public let camera: CIImage?
    public let desk: CIImage?
    public let isDemo: Bool
    public var cameraAvailable: Bool { camera != nil }
    public var deskAvailable: Bool { desk != nil }
}

public enum PreviewContent: Sendable { case composed, camera, desk }

public final class PreviewStream: Sendable {
    private struct State: Sendable {
        var frame: PreviewFrame?
        var sequence: UInt64 = 0
    }
    private let state = Mutex(State())
    public init() {}
    public var sequence: UInt64 { state.withLock { $0.sequence } }
    public func snapshot() -> PreviewFrame? { state.withLock { $0.frame } }
    func publish(_ frame: PreviewFrame) {
        state.withLock { $0.frame = frame; $0.sequence &+= 1 }
    }
    func clear() { state.withLock { $0.frame = nil; $0.sequence &+= 1 } }
}

/// A single slot per source. A slow renderer replaces old frames instead of
/// accumulating capture callbacks and presenting increasingly stale video.
final class LatestVideoFrames: Sendable {
    struct TimedImage: @unchecked Sendable {
        let image: CIImage
        let receivedAt: TimeInterval
    }
    private struct State: Sendable {
        var camera: TimedImage?
        var desk: TimedImage?
    }
    private let state = Mutex(State())
    func receive(_ image: CIImage, channel: CaptureChannel, at time: TimeInterval) {
        state.withLock {
            let frame = TimedImage(image: image, receivedAt: time)
            switch channel {
            case .camera: $0.camera = frame
            case .desk: $0.desk = frame
            }
        }
    }
    func clear(_ channel: CaptureChannel) {
        state.withLock {
            switch channel {
            case .camera: $0.camera = nil
            case .desk: $0.desk = nil
            }
        }
    }
    func clear() { state.withLock { $0 = State() } }
    func fresh(at time: TimeInterval) -> (CIImage?, CIImage?) {
        state.withLock {
            ( $0.camera.flatMap { time - $0.receivedAt < 2 ? $0.image : nil },
              $0.desk.flatMap { time - $0.receivedAt < 2 ? $0.image : nil } )
        }
    }
}

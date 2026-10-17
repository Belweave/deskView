import Foundation
import CoreGraphics

public enum StudioLayout: String, CaseIterable, Codable, Sendable, Identifiable {
    case pictureInPicture, sideBySide, camera, desk
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pictureInPicture: "Camera + desk"
        case .sideBySide: "Side by side"
        case .camera: "Camera"
        case .desk: "Desk"
        }
    }
    public var symbol: String {
        switch self {
        case .pictureInPicture: "pip"
        case .sideBySide: "rectangle.split.2x1"
        case .camera: "person.crop.rectangle"
        case .desk: "square.and.pencil"
        }
    }
    public var needsCamera: Bool { self != .desk }
    public var needsDesk: Bool { self != .camera }
}

public enum OutputAspect: String, CaseIterable, Codable, Sendable, Identifiable {
    case wide, portrait, square
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .wide: "16:9"
        case .portrait: "9:16"
        case .square: "1:1"
        }
    }
}

public enum OutputQuality: Int, CaseIterable, Codable, Sendable, Identifiable {
    case hd = 720, fullHD = 1080, ultraHD = 2160
    public var id: Int { rawValue }
    public var title: String { self == .ultraHD ? "4K" : "\(rawValue)p" }
    public func size(for aspect: OutputAspect) -> CGSize {
        let short = CGFloat(rawValue)
        // All encoder dimensions are even, including portrait and square.
        let long = (short * 16 / 9 / 2).rounded() * 2
        switch aspect {
        case .wide: return CGSize(width: long, height: short)
        case .portrait: return CGSize(width: short, height: long)
        case .square: return CGSize(width: short, height: short)
        }
    }
}

public enum InsetCorner: String, CaseIterable, Codable, Sendable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .topLeading: "Top left"
        case .topTrailing: "Top right"
        case .bottomLeading: "Bottom left"
        case .bottomTrailing: "Bottom right"
        }
    }
}

public struct SourceFraming: Codable, Equatable, Sendable {
    public var zoom: Double = 1
    public var panX: Double = 0
    public var panY: Double = 0
    public var mirrored = false
    public var quarterTurns = 0
    public init() {}

    public var normalized: Self {
        var result = self
        result.zoom = zoom.isFinite ? min(max(zoom, 1), 4) : 1
        result.panX = panX.isFinite ? min(max(panX, -1), 1) : 0
        result.panY = panY.isFinite ? min(max(panY, -1), 1) : 0
        result.quarterTurns = ((quarterTurns % 4) + 4) % 4
        return result
    }
}

public struct StudioConfiguration: Codable, Equatable, Sendable {
    public var layout: StudioLayout = .pictureInPicture
    public var aspect: OutputAspect = .wide
    public var quality: OutputQuality = .fullHD
    public var framesPerSecond: Int = 30
    public var cameraFraming = SourceFraming()
    public var deskFraming = SourceFraming()
    public var insetCorner: InsetCorner = .bottomTrailing
    public var insetScale: Double = 0.28
    public var deskIsBackground = true
    public init() {}
    public var outputSize: CGSize { quality.size(for: aspect) }
    public var safeFrameRate: Int { framesPerSecond == 24 ? 24 : 30 }
}

public enum CaptureChannel: String, Sendable { case camera, desk }

public enum CaptureFailure: Sendable {
    case video(CaptureChannel, String)
    case audio(String)
    public var message: String {
        switch self {
        case .video(_, let message), .audio(let message): message
        }
    }
    public func affectsRecording(layout: StudioLayout, includesAudio: Bool) -> Bool {
        switch self {
        case .video(.camera, _): layout.needsCamera
        case .video(.desk, _): layout.needsDesk
        case .audio: includesAudio
        }
    }
}

public struct CameraDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isContinuityCamera: Bool
    public let isDeskView: Bool
    public let companionDeskID: String?
    public init(id: String, name: String, isContinuityCamera: Bool, isDeskView: Bool, companionDeskID: String? = nil) {
        self.id = id
        self.name = name
        self.isContinuityCamera = isContinuityCamera
        self.isDeskView = isDeskView
        self.companionDeskID = companionDeskID
    }
}

public enum StudioError: LocalizedError, Sendable {
    case unavailable(String)
    case noFrames
    case recordingInProgress
    case writer(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail): detail
        case .noFrames: "No camera frames have arrived yet. Connect a camera and start the preview."
        case .recordingInProgress: "Finish the current recording before changing output settings."
        case .writer(let detail): "The recording could not be saved. \(detail)"
        }
    }
}

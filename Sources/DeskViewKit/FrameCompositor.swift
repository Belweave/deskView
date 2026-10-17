import CoreImage
import Foundation

/// One renderer defines the preview, PNG snapshot and recorded video.
/// Coordinates are Core Image coordinates (origin at bottom left).
public struct FrameCompositor: Sendable {
    public init() {}

    public func compose(camera: CIImage?, desk: CIImage?, configuration: StudioConfiguration) -> CIImage {
        let size = configuration.outputSize
        let canvas = CGRect(origin: .zero, size: size)
        var result = CIImage(color: CIColor(red: 0.025, green: 0.04, blue: 0.06)).cropped(to: canvas)
        func place(_ image: CIImage?, framing: SourceFraming, in rect: CGRect) {
            guard let image else { return }
            result = fitted(image, framing: framing, in: rect).composited(over: result)
        }
        switch configuration.layout {
        case .camera:
            place(camera, framing: configuration.cameraFraming, in: canvas)
        case .desk:
            place(desk, framing: configuration.deskFraming, in: canvas)
        case .sideBySide:
            let gap = size.width * 0.006
            if configuration.aspect == .portrait {
                let height = (size.height - gap) / 2
                place(camera, framing: configuration.cameraFraming, in: CGRect(x: 0, y: height + gap, width: size.width, height: height))
                place(desk, framing: configuration.deskFraming, in: CGRect(x: 0, y: 0, width: size.width, height: height))
            } else {
                let width = (size.width - gap) / 2
                place(camera, framing: configuration.cameraFraming, in: CGRect(x: 0, y: 0, width: width, height: size.height))
                place(desk, framing: configuration.deskFraming, in: CGRect(x: width + gap, y: 0, width: width, height: size.height))
            }
        case .pictureInPicture:
            let background = configuration.deskIsBackground ? desk : camera
            let inset = configuration.deskIsBackground ? camera : desk
            let backFraming = configuration.deskIsBackground ? configuration.deskFraming : configuration.cameraFraming
            let insetFraming = configuration.deskIsBackground ? configuration.cameraFraming : configuration.deskFraming
            place(background, framing: backFraming, in: canvas)
            let margin = min(size.width, size.height) * 0.035
            let scale = configuration.insetScale.isFinite ? min(max(configuration.insetScale, 0.18), 0.45) : 0.28
            let width = size.width * scale
            let height = width * 0.75
            let leading = configuration.insetCorner == .topLeading || configuration.insetCorner == .bottomLeading
            let top = configuration.insetCorner == .topLeading || configuration.insetCorner == .topTrailing
            let rect = CGRect(x: leading ? margin : size.width - width - margin,
                              y: top ? size.height - height - margin : margin,
                              width: width, height: height)
            if inset != nil {
                let border = CIImage(color: CIColor(red: 0.83, green: 0.9, blue: 0.94))
                    .cropped(to: rect.insetBy(dx: -2, dy: -2))
                result = border.composited(over: result)
                place(inset, framing: insetFraming, in: rect)
            }
        }
        return result.cropped(to: canvas)
    }

    public func fitted(_ original: CIImage, framing rawFraming: SourceFraming, in target: CGRect) -> CIImage {
        let framing = rawFraming.normalized
        var image = original
        // EXIF rotation also relocates the extent, so normalize after transforming.
        switch framing.quarterTurns {
        case 1: image = image.oriented(.right)
        case 2: image = image.oriented(.down)
        case 3: image = image.oriented(.left)
        default: break
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if framing.mirrored {
            image = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: image.extent.width, ty: 0))
        }
        guard image.extent.width > 0, image.extent.height > 0, target.width > 0, target.height > 0 else {
            return CIImage.empty()
        }
        let scale = max(target.width / image.extent.width, target.height / image.extent.height) * framing.zoom
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let excessX = max(0, image.extent.width - target.width)
        let excessY = max(0, image.extent.height - target.height)
        let x = target.minX - excessX * (framing.panX + 1) / 2
        let y = target.minY - excessY * (framing.panY + 1) / 2
        return image.transformed(by: CGAffineTransform(translationX: x, y: y)).cropped(to: target)
    }
}

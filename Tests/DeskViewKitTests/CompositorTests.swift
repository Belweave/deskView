import Testing
import CoreImage
@testable import DeskViewKit

struct CompositorTests {
    private let context = CIContext(options: [.useSoftwareRenderer: true])
    private let compositor = FrameCompositor()
    private var red: CIImage { CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240)) }
    private var blue: CIImage { CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240)) }

    private func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &data, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return data
    }

    @Test func sideBySidePlacesBothSources() {
        var config = StudioConfiguration()
        config.quality = .hd; config.layout = .sideBySide
        let image = compositor.compose(camera: red, desk: blue, configuration: config)
        #expect(image.extent.size == CGSize(width: 1280, height: 720))
        #expect(pixel(image, x: 100, y: 360)[0] > 240)
        #expect(pixel(image, x: 1100, y: 360)[2] > 240)
        #expect(pixel(image, x: 640, y: 360)[0] < 30)
    }

    @Test func insetRespectsCornerAndBackgroundSwap() {
        var config = StudioConfiguration()
        config.quality = .hd; config.insetCorner = .topLeading
        let image = compositor.compose(camera: red, desk: blue, configuration: config)
        #expect(pixel(image, x: 80, y: 650)[0] > 240)
        #expect(pixel(image, x: 1100, y: 100)[2] > 240)
        config.deskIsBackground = false
        let swapped = compositor.compose(camera: red, desk: blue, configuration: config)
        #expect(pixel(swapped, x: 80, y: 650)[2] > 240)
        #expect(pixel(swapped, x: 1100, y: 100)[0] > 240)
    }

    @Test func portraitStacksSourcesAndUsesEvenEncoderDimensions() {
        var config = StudioConfiguration()
        config.aspect = .portrait; config.quality = .hd; config.layout = .sideBySide
        let image = compositor.compose(camera: red, desk: blue, configuration: config)
        #expect(image.extent.size == CGSize(width: 720, height: 1280))
        #expect(pixel(image, x: 360, y: 1000)[0] > 240)
        #expect(pixel(image, x: 360, y: 200)[2] > 240)
        for quality in OutputQuality.allCases {
            for aspect in OutputAspect.allCases {
                let size = quality.size(for: aspect)
                #expect(Int(size.width) % 2 == 0)
                #expect(Int(size.height) % 2 == 0)
            }
        }
    }

    @Test func mirroringAndRotationTransformTheActualPixels() {
        let left = red.cropped(to: CGRect(x: 0, y: 0, width: 160, height: 240))
        let source = left.composited(over: blue)
        var framing = SourceFraming(); framing.mirrored = true
        let mirrored = compositor.fitted(source, framing: framing, in: source.extent)
        #expect(pixel(mirrored, x: 30, y: 120)[2] > 240)
        #expect(pixel(mirrored, x: 290, y: 120)[0] > 240)
        framing.mirrored = false; framing.quarterTurns = 1
        let rotated = compositor.fitted(source, framing: framing, in: CGRect(x: 0, y: 0, width: 240, height: 320))
        let top = pixel(rotated, x: 120, y: 290)
        let bottom = pixel(rotated, x: 120, y: 30)
        #expect(top[0] != bottom[0])
    }

    @Test func missingInputsProduceAValidCanvasAndFramingClampsCorruptValues() {
        let image = compositor.compose(camera: nil, desk: nil, configuration: StudioConfiguration())
        #expect(image.extent.size == CGSize(width: 1920, height: 1080))
        var framing = SourceFraming()
        framing.zoom = .nan; framing.panX = 20; framing.panY = -.infinity; framing.quarterTurns = -5
        #expect(framing.normalized.zoom == 1)
        #expect(framing.normalized.panX == 1)
        #expect(framing.normalized.panY == 0)
        #expect(framing.normalized.quarterTurns == 3)
    }
}

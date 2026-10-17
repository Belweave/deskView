import AppKit
import DeskViewKit
import SwiftUI

enum StudioTheme {
    static let canvas = Color(red: 0.04, green: 0.065, blue: 0.09)
    static let shell = Color(red: 0.075, green: 0.115, blue: 0.16)
    static let accent = Color(red: 0.59, green: 0.85, blue: 0.93)
    static let secondary = Color(red: 0.68, green: 0.75, blue: 0.82)
    static let record = Color(red: 1, green: 0.34, blue: 0.31)
    static let recordFill = Color(red: 0.78, green: 0.12, blue: 0.10)
}

struct StudioView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.openWindow) private var openWindow
    @State private var showsGrid = false
    @State private var framingChannel: CaptureChannel = .desk

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                SourceSidebar(model: model).frame(width: 224)
                Divider()
                workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                FramingInspector(model: model, channel: $framingChannel).frame(width: 232)
            }
            Divider()
            footer
        }
        .background(StudioTheme.shell)
        .ignoresSafeArea(.container, edges: .top)
        .tint(StudioTheme.accent)
        .sheet(isPresented: $model.showsLibrary) { RecordingsView(model: model) }
        .sheet(isPresented: $model.showsGuide) { SetupGuide(model: model) }
        .alert("Studio needs your attention", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.aperture").font(.title2).foregroundStyle(StudioTheme.accent)
            Text("deskView()").font(.system(size: 19, weight: .semibold))
            Spacer()
            if model.isDemo { StatusPill(title: "Demo test chart", symbol: "testtube.2", color: .orange) }
            else if model.isRecording { StatusPill(title: "Recording", symbol: "record.circle.fill", color: StudioTheme.record) }
            else if model.isPreviewRunning { StatusPill(title: "Preview on", symbol: "video.fill", color: .green) }
            Button { model.showsLibrary = true; Task { await model.refreshLibrary() } } label: {
                Label("Recordings", systemImage: "photo.stack")
            }.help("Browse saved recordings and snapshots (⇧⌘L)")
            Button { openWindow(id: "output") } label: { Label("Output window", systemImage: "rectangle.on.rectangle") }
                .help("Open a clean window to share in a video call (⌘2)")
        }
        .buttonStyle(.bordered)
        .padding(.leading, 82).padding(.trailing, 20).frame(height: 62)
        .background(.ultraThinMaterial)
    }

    private var workspace: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Studio").font(.system(size: 24, weight: .semibold))
                Spacer()
                Button { showsGrid.toggle() } label: { Image(systemName: "grid") }
                    .buttonStyle(.borderless).foregroundStyle(showsGrid ? StudioTheme.accent : StudioTheme.secondary)
                    .help("Toggle framing grid (preview only)").accessibilityLabel("Framing grid")
                    .accessibilityValue(showsGrid ? "On" : "Off")
                Menu {
                    Picker("Resolution", selection: $model.configuration.quality) {
                        ForEach(OutputQuality.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Aspect ratio", selection: $model.configuration.aspect) {
                        ForEach(OutputAspect.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Frame rate", selection: $model.configuration.framesPerSecond) {
                        Text("24 fps").tag(24); Text("30 fps").tag(30); Text("60 fps").tag(60)
                    }
                } label: {
                    Text("\(model.configuration.quality.title) · \(model.configuration.aspect.title) · \(model.configuration.safeFrameRate) fps")
                        .font(.system(size: 12, weight: .medium))
                }.menuStyle(.borderedButton).disabled(model.isBusy).help("Composed recording dimensions and frame rate. Source resolution may differ.")
            }
            GeometryReader { geometry in
                ZStack {
                    if model.isPreviewRunning {
                        MetalPreview(stream: model.pipeline.previewStream)
                            .overlay { if showsGrid { ThirdsGrid() } }
                    } else { emptyCanvas }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if let message = model.missingSourceMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            transport
        }
        .padding(20)
        .background(StudioTheme.canvas)
    }

    private var emptyCanvas: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.inset.bottomtrailing.filled")
                .font(.system(size: 56, weight: .ultraLight)).foregroundStyle(StudioTheme.accent)
            VStack(spacing: 7) {
                Text("Your desk has a point of view.").font(.system(size: 23, weight: .medium))
                Text("Bring your camera and your ideas into the frame.")
                    .font(.system(size: 14)).foregroundStyle(StudioTheme.secondary)
            }
            if model.cameraPermission == .denied || model.cameraPermission == .restricted {
                Button("Open Camera Settings") { model.openCameraPrivacy() }.buttonStyle(.borderedProminent)
            } else {
                Button { Task { await model.startPreview() } } label: {
                    Label(model.isConnecting ? "Connecting…" : "Start preview", systemImage: "video")
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isConnecting)
            }
            HStack(spacing: 20) {
                Button("Connection help") { model.showsGuide = true }
                Button("Try a demo") { Task { await model.enableDemo() } }
            }.buttonStyle(.link).font(.system(size: 12))
        }
        .padding(24)
        .multilineTextAlignment(.center)
    }

    private var transport: some View {
        HStack(spacing: 18) {
            HStack(spacing: 4) {
                ForEach(StudioLayout.allCases) { layout in
                    Button { model.configuration.layout = layout } label: {
                        VStack(spacing: 6) {
                            Image(systemName: layout.symbol).font(.system(size: 20))
                            Text(layout.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).frame(height: 58)
                        .background(model.configuration.layout == layout ? StudioTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(model.configuration.layout == layout ? StudioTheme.canvas : .white)
                    }
                    .buttonStyle(.plain).help(layout.title)
                    .accessibilityAddTraits(model.configuration.layout == layout ? [.isSelected] : [])
                }
            }.disabled(model.isBusy)
            Divider().frame(height: 48)
            Button { Task { await model.takeSnapshot() } } label: {
                Image(systemName: "camera").font(.system(size: 23)).frame(width: 44, height: 44)
            }
            .buttonStyle(.glass).disabled(!model.canCapture).help("Save the canvas as a PNG snapshot (⇧⌘S)")
            .accessibilityLabel("Take snapshot")
            Button { Task { await model.toggleRecording() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.isRecording ? "stop.fill" : "record.circle.fill").font(.system(size: 23))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.isSaving ? "Saving…" : (model.isRecording ? "Stop" : "Record")).font(.system(size: 15, weight: .semibold))
                        RecordingTimecode(clock: model.recordingClock).font(.system(size: 11, design: .monospaced))
                    }
                }.frame(width: 116, height: 58)
            }
            .buttonStyle(.plain)
            .background(StudioTheme.recordFill.opacity((model.canCapture || model.isRecording) ? 1 : 0.3), in: Capsule())
            .foregroundStyle(.white)
            .disabled((!model.canCapture && !model.isRecording) || model.isSaving)
            .help("Start or stop recording (⌘R)")
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .frame(height: 92)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isDemo ? "testtube.2" : "info.circle").foregroundStyle(StudioTheme.secondary)
            Text(model.statusMessage).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            Button { model.revealDestination() } label: {
                Label("\(model.destination.deletingLastPathComponent().lastPathComponent) / \(model.destination.lastPathComponent)", systemImage: "folder")
            }.buttonStyle(.plain).help(model.destination.path)
        }
        .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
        .padding(.horizontal, 20).frame(height: 36)
    }
}

private struct RecordingTimecode: View {
    @ObservedObject var clock: RecordingClockState
    var body: some View { Text(clock.timecode) }
}

struct StatusPill: View {
    var title: String
    var symbol: String
    var color: Color
    var body: some View {
        Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct ThirdsGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for value in [1.0 / 3, 2.0 / 3] {
                    path.move(to: CGPoint(x: geometry.size.width * value, y: 0))
                    path.addLine(to: CGPoint(x: geometry.size.width * value, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * value))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * value))
                }
            }.stroke(.white.opacity(0.5), lineWidth: 0.6)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct OutputView: View {
    @ObservedObject var model: StudioModel
    var body: some View {
        ZStack {
            Color.black
            if model.isPreviewRunning {
                MetalPreview(stream: model.pipeline.previewStream,
                             label: model.isDemo ? "Demo test chart output" : "Clean composed camera output")
            } else {
                ContentUnavailableView("Preview is stopped", systemImage: "video.slash", description: Text("Start the preview in the studio to share this window."))
            }
            if model.isDemo {
                VStack { Spacer(); Text("DEMO TEST CHART").font(.caption.monospaced()).padding(8).background(.black.opacity(0.7)); }.padding(12)
            }
        }
    }
}

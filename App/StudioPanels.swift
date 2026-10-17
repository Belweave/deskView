import AppKit
import AVFoundation
import DeskViewKit
import SwiftUI

struct SourceSidebar: View {
    @ObservedObject var model: StudioModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Sources").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button { model.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Refresh connected cameras").accessibilityLabel("Refresh sources")
                }
                source(title: "Camera", symbol: "video", content: .camera, available: model.cameraAvailable) {
                    if model.isDemo { demoSource("Demo camera") }
                    else {
                    Picker("Camera", selection: Binding(get: { model.selectedCameraID }, set: model.chooseCamera)) {
                        Text("No camera").tag("")
                        if !model.selectedCameraID.isEmpty && !model.mainCameras.contains(where: { $0.id == model.selectedCameraID }) {
                            Text("Disconnected camera").tag(model.selectedCameraID)
                        }
                        ForEach(model.mainCameras) { Text($0.name).tag($0.id) }
                    }
                    }
                }
                source(title: "Desk View", symbol: "square.and.pencil", content: .desk, available: model.deskAvailable) {
                    if model.isDemo { demoSource("Demo Desk View") }
                    else {
                    Picker("Desk View", selection: Binding(get: { model.selectedDeskID }, set: model.chooseDesk)) {
                        Text("No Desk View").tag("")
                        if !model.selectedDeskID.isEmpty && !model.deskCameras.contains(where: { $0.id == model.selectedDeskID }) {
                            Text("Disconnected Desk View").tag(model.selectedDeskID)
                        }
                        ForEach(model.deskCameras) { Text($0.name).tag($0.id) }
                    }
                    }
                }
                if !model.isDemo && !model.selectedDeskID.isEmpty {
                    Button(model.isAligningDeskView ? "Aligning Desk View…" : "Align Desk View…") {
                        Task { await model.alignDeskView() }
                    }
                    .buttonStyle(.bordered).disabled(model.isBusy || model.isAligningDeskView)
                    .help("Open Apple's overhead setup. If Desk View is already open, choose View → Return to Setup in its menu.")
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label("Microphone", systemImage: "mic").font(.system(size: 12, weight: .medium))
                    if model.isDemo { demoSource("No microphone · demo") }
                    else { Picker("Microphone", selection: Binding(get: { model.selectedMicrophoneID }, set: model.chooseMicrophone)) {
                        Text("No microphone · silent").tag("")
                        ForEach(model.microphones) { Text($0.name).tag($0.id) }
                    }.labelsHidden().disabled(model.isBusy) }
                    HStack(spacing: 6) {
                        AudioLevelMeter(meter: model.audioMeter).frame(height: 4).accessibilityHidden(true)
                        Text(model.microphoneActive ? "On" : "Off").font(.system(size: 10)).foregroundStyle(StudioTheme.secondary)
                    }.accessibilityElement(children: .ignore).accessibilityLabel(model.microphoneActive ? "Microphone active" : "Microphone off")
                    if model.microphoneActive {
                        Button("Microphone modes…") { model.showMicrophoneModes() }.buttonStyle(.link).font(.system(size: 11))
                    }
                }
                VStack(spacing: 10) {
                    Button {
                        Task { if model.isPreviewRunning { await model.stopPreview() } else { await model.startPreview() } }
                    } label: {
                        Label(model.isConnecting ? "Connecting…" : (model.isPreviewRunning ? "Stop preview" : "Start preview"),
                              systemImage: model.isPreviewRunning ? "video.slash" : "video")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).disabled(model.isBusy)
                    Button("Camera setup guide") { model.showsGuide = true }.buttonStyle(.link).font(.system(size: 11))
                }
                if model.isDemo {
                    Text("Demo mode uses test charts. No camera or microphone is active.")
                        .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Use real cameras") { Task { await model.startPreview() } }.disabled(model.isBusy)
                }
            }.padding(18)
        }
        .background(.ultraThinMaterial)
    }

    private func demoSource(_ title: String) -> some View {
        Text(title).font(.system(size: 12)).foregroundStyle(StudioTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 9).padding(.vertical, 6)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func source<Content: View>(title: String, symbol: String, content: PreviewContent, available: Bool, @ViewBuilder picker: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: symbol).foregroundStyle(StudioTheme.accent)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: available ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.system(size: 10)).foregroundStyle(available ? .green : StudioTheme.secondary)
                    .accessibilityLabel(available ? "Receiving frames" : "No video frames")
            }
            picker().labelsHidden().disabled(model.isBusy || model.isDemo).frame(maxWidth: .infinity)
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.3))
                if available {
                    MetalPreview(stream: model.pipeline.previewStream, content: content, label: "\(title) source preview")
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: symbol).font(.system(size: 22, weight: .light))
                        Text(title == "Desk View" ? "Overhead, when available" : "Ready when you are").font(.system(size: 10))
                    }.foregroundStyle(StudioTheme.secondary)
                }
            }.frame(height: 112).clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel("\(title) source preview")
        }
    }
}

private struct AudioLevelMeter: View {
    @ObservedObject var meter: AudioMeterState
    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(.white.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule().fill(StudioTheme.accent).frame(width: proxy.size.width * CGFloat(min(meter.level * 3, 1)))
                }
        }
    }
}

struct FramingInspector: View {
    @ObservedObject var model: StudioModel
    @Binding var channel: CaptureChannel
    private var framing: Binding<SourceFraming> {
        channel == .camera ? $model.configuration.cameraFraming : $model.configuration.deskFraming
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Framing").font(.system(size: 14, weight: .semibold))
                Picker("Adjust source", selection: $channel) {
                    Text("Camera").tag(CaptureChannel.camera)
                    Text("Desk").tag(CaptureChannel.desk)
                }.pickerStyle(.segmented).labelsHidden()
                FramingControls(framing: framing).disabled(model.isBusy)
                if model.configuration.layout == .pictureInPicture {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Picture in picture").font(.system(size: 12, weight: .semibold))
                        Picker("Position", selection: $model.configuration.insetCorner) {
                            ForEach(InsetCorner.allCases) { Text($0.title).tag($0) }
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Inset size").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                            Slider(value: $model.configuration.insetScale, in: 0.18...0.45).accessibilityLabel("Inset size")
                        }
                        Button { model.configuration.deskIsBackground.toggle() } label: {
                            Label("Swap views", systemImage: "arrow.triangle.2.circlepath")
                        }.frame(maxWidth: .infinity)
                    }.disabled(model.isBusy)
                }
                Divider()
                effects
            }.padding(18)
        }.background(.ultraThinMaterial)
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Video effects").font(.system(size: 13, weight: .semibold))
            Toggle("Center Stage", isOn: Binding(get: { model.effects.centerStage }, set: model.setCenterStage))
                .toggleStyle(.switch).controlSize(.small)
                .disabled(!model.effects.supportsCenterStage || model.isDemo || !model.isPreviewRunning)
            effectRow("Portrait", active: model.effects.portrait)
            effectRow("Studio Light", active: model.effects.studioLight)
            effectRow("Background", active: model.effects.backgroundReplacement)
            Button { model.showEffects() } label: {
                HStack { Text("Open video effects"); Spacer(); Image(systemName: "arrow.up.right") }
            }.buttonStyle(.bordered).disabled(!model.isPreviewRunning || model.isDemo)
            if model.effects.reactions && !model.isDemo {
                Menu("Send a reaction") {
                    Button("Hearts") { model.reaction(.heart) }
                    Button("Thumbs up") { model.reaction(.thumbsUp) }
                    Button("Balloons") { model.reaction(.balloons) }
                    Button("Confetti") { model.reaction(.confetti) }
                    Button("Fireworks") { model.reaction(.fireworks) }
                }
            }
            Text("Availability depends on your camera. macOS controls Portrait, Studio Light, backgrounds and gestures.")
                .font(.system(size: 10)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func effectRow(_ title: String, active: Bool) -> some View {
        Button { model.showEffects() } label: {
            HStack {
                Text(title)
                Spacer()
                Text(active ? "On" : "Off").foregroundStyle(active ? StudioTheme.accent : StudioTheme.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9))
            }.font(.system(size: 12))
        }.buttonStyle(.plain).disabled(!model.isPreviewRunning || model.isDemo)
    }
}

private struct FramingControls: View {
    @Binding var framing: SourceFraming
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(spacing: 8) {
                HStack { Text("Zoom"); Spacer(); Text("\(framing.zoom, format: .number.precision(.fractionLength(1)))×") }
                    .font(.system(size: 12))
                Slider(value: $framing.zoom, in: 1...4).accessibilityLabel("Digital crop zoom")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Pan horizontally").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                Slider(value: $framing.panX, in: -1...1).accessibilityLabel("Horizontal pan")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Pan vertically").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
                Slider(value: $framing.panY, in: -1...1).accessibilityLabel("Vertical pan")
            }
            Toggle("Mirror", isOn: $framing.mirrored).toggleStyle(.switch).controlSize(.small)
            HStack {
                Text("Rotate").font(.system(size: 12))
                Spacer()
                Button { framing.quarterTurns = (framing.quarterTurns + 3) % 4 } label: { Image(systemName: "rotate.left") }
                    .help("Rotate counterclockwise 90°").accessibilityLabel("Rotate counterclockwise")
                Button { framing.quarterTurns = (framing.quarterTurns + 1) % 4 } label: { Image(systemName: "rotate.right") }
                    .help("Rotate clockwise 90°").accessibilityLabel("Rotate clockwise")
            }
            Button("Reset framing") { framing = SourceFraming() }.buttonStyle(.link).font(.system(size: 11))
            Text("Digital crop applies to the canvas, snapshots and recording.")
                .font(.system(size: 10)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct RecordingsView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recordings & snapshots").font(.title2.bold())
                Spacer()
                Button("Show folder") { model.revealDestination() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(24)
            Divider()
            if model.library.isEmpty {
                ContentUnavailableView("Your next idea goes here.", systemImage: "photo.stack", description: Text("Record a presentation or take a snapshot. Your files stay in the save folder on your Mac."))
                    .frame(maxHeight: .infinity)
            } else {
                List(model.library) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.isVideo ? "film" : "photo").font(.title2).foregroundStyle(StudioTheme.accent).frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") { NSWorkspace.shared.open(item.url) }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "folder") }
                            .help("Reveal in Finder").accessibilityLabel("Reveal \(item.url.lastPathComponent) in Finder")
                    }.padding(.vertical, 8)
                }
            }
            Divider()
            HStack {
                Text(model.destination.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Change save folder…") { model.chooseDestination() }.disabled(model.isBusy)
            }.padding(20)
        }
        .frame(width: 760, height: 500).tint(StudioTheme.accent)
    }
}

struct SetupGuide: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("Bring your iPhone into the studio.").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            guide("Connect Continuity Camera", "Use the same Apple Account on your Mac and iPhone, with two-factor authentication. Turn on Wi-Fi and Bluetooth, enable Continuity Camera in iPhone Settings → General → AirPlay & Continuity, then place your locked iPhone nearby in landscape orientation. A trusted USB connection also works.", symbol: "iphone.and.arrow.forward")
            guide("Choose both views", "Refresh Sources, select your iPhone camera, and choose its paired Desk View. Some recent Macs and displays provide Desk View through their built-in cameras. If no Desk View device appears, check Apple's hardware requirements.", symbol: "rectangle.on.rectangle")
            guide("Align the overhead view", "Keep your iPhone mounted above the display with its rear cameras facing you. Choose Align Desk View, adjust Apple's selection border around your keyboard, then click Start Desk View. If its window is already open, choose View → Return to Setup. This sets the overhead region before any digital crop.", symbol: "viewfinder")
            guide("Frame, then record", "Choose Camera + desk or Side by side. Select Camera or Desk in Framing to adjust its crop, pan, mirror and rotation. The preview runs at 60 Hz; recording offers 24, 30 or 60 fps. Source motion depends on the camera's supported rate. Choose a microphone or No microphone for silence.", symbol: "record.circle")
            guide("Share a clean window", "Open Output window, then choose that window in your call app's screen sharing controls. deskView() does not install a virtual camera.", symbol: "rectangle.on.rectangle")
            HStack(spacing: 18) {
                Link("Apple Desk View requirements ↗", destination: URL(string: "https://support.apple.com/en-us/121541")!)
                Link("Continuity Camera setup ↗", destination: URL(string: "https://support.apple.com/en-us/102546")!)
            }.font(.system(size: 12))
            HStack {
                Button("Refresh sources") { model.refreshDevices() }
                Button("Camera privacy settings") { model.openCameraPrivacy() }
                Spacer()
                Button("Try demo charts") { dismiss(); Task { await model.enableDemo() } }.disabled(model.isBusy)
            }
        }.padding(28).frame(width: 700).tint(StudioTheme.accent)
    }
    private func guide(_ title: String, _ message: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(StudioTheme.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct StudioSettings: View {
    @ObservedObject var model: StudioModel
    var body: some View {
        Form {
            Section("Save location") {
                Text(model.destination.path).textSelection(.enabled).font(.callout)
                HStack { Button("Choose folder…") { model.chooseDestination() }.disabled(model.isBusy); Button("Open in Finder") { model.revealDestination() } }
            }
            Section("Output") {
                Picker("Resolution", selection: $model.configuration.quality) { ForEach(OutputQuality.allCases) { Text($0.title).tag($0) } }
                Picker("Aspect ratio", selection: $model.configuration.aspect) { ForEach(OutputAspect.allCases) { Text($0.title).tag($0) } }
                Text("Recordings are H.264 movies with optional AAC microphone audio. 4K describes the output canvas; camera detail depends on the source.").font(.caption).foregroundStyle(.secondary)
            }.disabled(model.isBusy)
            Section("Getting started") {
                Button("Replay welcome") { model.showsIntro = true }
                Button("Camera setup guide") { model.showsGuide = true }
                Button("Try demo charts") { Task { await model.enableDemo() } }.disabled(model.isBusy)
            }
        }.formStyle(.grouped).padding(12).tint(StudioTheme.accent)
    }
}

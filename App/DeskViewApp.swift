import AppKit
import DeskViewKit
import FoyerKit
import SwiftUI

@main
struct DeskViewApp: App {
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate
    @StateObject private var model = StudioModel()

    var body: some Scene {
        Window("deskView()", id: "studio") {
            StudioRoot(model: model)
                .task { appDelegate.model = model; model.start() }
                .frame(minWidth: 1120, minHeight: 740)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { StudioCommands(model: model) }

        Window("deskView() Output", id: "output") {
            OutputView(model: model)
                .frame(minWidth: 480, minHeight: 270)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 960, height: 540)

        Settings {
            StudioSettings(model: model).frame(width: 520).preferredColorScheme(.dark)
        }
    }
}

private struct StudioRoot: View {
    @ObservedObject var model: StudioModel
    private var skipsIntro: Bool { ProcessInfo.processInfo.arguments.contains("--skip-intro") }
    var body: some View {
        Group {
            if skipsIntro { StudioView(model: model) }
            else { StudioView(model: model).foyer(Self.intro) }
        }
        .foyer(Self.intro, isPresented: $model.showsIntro)
    }

    private static let intro = Foyer(
        appName: "deskView()",
        mark: .symbol("camera.aperture", color: .cyan),
        pages: [
            .greeting("Make room for your ideas.", message: "Your camera. Your desk. One place to bring them together."),
            .symbols("Two views. One story.", message: "Pair your iPhone camera with an overhead Desk View. Frame a sketch, a lesson, or your next great demo.",
                     symbols: ["camera", "square.and.pencil", "mic", "record.circle", "rectangle.on.rectangle"], center: "camera.aperture"),
            .icon("Your own little studio.", message: "Record the canvas, save a snapshot, or share a clean output window. Everything stays on your Mac.", symbol: "camera.aperture", badge: "checkmark")
        ],
        finale: ["Set the scene.", "Press record."],
        startTitle: Text("Let's set the scene."),
        startButton: Text("Open studio"),
        tint: .cyan,
        playsLaunchAnimation: false,
        storage: FoyerStorage(key: "org.belweave.deskView.welcome.v1"),
        allowsSkipping: true
    )
}

@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: StudioModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.isSaving || model.isConnecting { return .terminateCancel }
        Task {
            let saved = await model.stopRecording()
            if saved {
                await model.shutdown()
                sender.reply(toApplicationShouldTerminate: true)
            } else {
                let alert = NSAlert()
                alert.messageText = "The recording could not finish saving."
                alert.informativeText = model.alertMessage ?? "Review the recording before quitting."
                alert.addButton(withTitle: "Keep studio open")
                alert.runModal()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}

private struct StudioCommands: Commands {
    @ObservedObject var model: StudioModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Studio") { openWindow(id: "studio") }.keyboardShortcut("1", modifiers: [.command])
            Button("Open Output Window") { openWindow(id: "output") }.keyboardShortcut("2", modifiers: [.command])
        }
        CommandMenu("Capture") {
            Button(model.isRecording ? "Stop Recording" : "Record") { Task { await model.toggleRecording() } }
                .keyboardShortcut("r", modifiers: [.command]).disabled(!model.canCapture && !model.isRecording)
            Button("Take Snapshot") { Task { await model.takeSnapshot() } }
                .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(!model.canCapture)
            Divider()
            Button(model.isPreviewRunning ? "Stop Preview" : "Start Preview") {
                Task { if model.isPreviewRunning { await model.stopPreview() } else { await model.startPreview() } }
            }.disabled(model.isBusy)
            Button("Video Effects…") { model.showEffects() }.disabled(!model.isPreviewRunning || model.isDemo)
            Divider()
            Button("Show Recordings") { model.showsLibrary = true; Task { await model.refreshLibrary() } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Show Save Folder") { model.revealDestination() }
        }
        CommandGroup(replacing: .help) {
            Button("Camera Setup Guide") { model.showsGuide = true }
            Button("Replay Welcome") { model.showsIntro = true }
            Link("Apple Desk View Guide", destination: URL(string: "https://support.apple.com/en-us/121541")!)
        }
    }
}

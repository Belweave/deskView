import AppKit
import AVFoundation
import Combine
import DeskViewKit
import Foundation

struct MediaItem: Identifiable, Sendable {
    let url: URL
    let date: Date
    let bytes: Int64
    var id: URL { url }
    var isVideo: Bool { url.pathExtension.lowercased() == "mov" }
}

@MainActor
final class StudioModel: ObservableObject {
    @Published var configuration: StudioConfiguration {
        didSet {
            pipeline.update(configuration)
            if let data = try? JSONEncoder().encode(configuration) { UserDefaults.standard.set(data, forKey: "studio.configuration.v1") }
        }
    }
    @Published private(set) var cameras: [CameraDescriptor] = []
    @Published private(set) var microphones: [AudioDescriptor] = []
    @Published var selectedCameraID = ""
    @Published var selectedDeskID = ""
    @Published var selectedMicrophoneID = ""
    @Published private(set) var cameraAvailable = false
    @Published private(set) var deskAvailable = false
    @Published private(set) var isPreviewRunning = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isAligningDeskView = false
    @Published private(set) var isRecording = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDemo = false
    @Published private(set) var microphoneActive = false
    let audioMeter = AudioMeterState()
    let recordingClock = RecordingClockState()
    private var audioLevel: Float {
        get { audioMeter.level }
        set { audioMeter.level = newValue }
    }
    @Published private(set) var effects = VideoEffectsState()
    private var elapsed: TimeInterval {
        get { recordingClock.elapsed }
        set { recordingClock.elapsed = newValue }
    }
    @Published private(set) var cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var library: [MediaItem] = []
    @Published var destination: URL
    @Published var alertMessage: String?
    @Published var statusMessage = "Connect your iPhone. Make room for your ideas."
    @Published var showsLibrary = false
    @Published var showsGuide = false
    @Published var showsIntro = false

    let pipeline = StudioPipeline()
    private lazy var capture = CaptureService(pipeline: pipeline)
    private var startedAt: Date?
    private var statusTask: Task<Void, Never>?
    private var didStart = false
    private var snapshotBusy = false
    private var recordingID: UUID?
    private var finalizingRecordingID: UUID?
    private var microphonePreferenceWasSet: Bool
    private let deskViewApplication = AVCaptureDeskViewApplication()

    init() {
        microphonePreferenceWasSet = UserDefaults.standard.object(forKey: "studio.microphone") != nil
        if let data = UserDefaults.standard.data(forKey: "studio.configuration.v1"),
           let stored = try? JSONDecoder().decode(StudioConfiguration.self, from: data) {
            configuration = stored
        } else { configuration = StudioConfiguration() }
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        destination = UserDefaults.standard.url(forKey: "studio.destination") ?? movies.appendingPathComponent("deskView", isDirectory: true)
        selectedCameraID = UserDefaults.standard.string(forKey: "studio.camera") ?? ""
        selectedMicrophoneID = UserDefaults.standard.string(forKey: "studio.microphone") ?? ""
    }

    var mainCameras: [CameraDescriptor] { cameras.filter { !$0.isDeskView } }
    var deskCameras: [CameraDescriptor] { cameras.filter(\.isDeskView) }
    var isBusy: Bool { isRecording || isSaving || isConnecting }
    var canCapture: Bool {
        isPreviewRunning && (!configuration.layout.needsCamera || cameraAvailable) &&
        (!configuration.layout.needsDesk || deskAvailable) && !isConnecting && !isSaving && !isAligningDeskView
    }
    var missingSourceMessage: String? {
        if !isPreviewRunning { return nil }
        if configuration.layout.needsCamera && !cameraAvailable { return "Waiting for the camera. Reconnect it or choose Desk layout." }
        if configuration.layout.needsDesk && !deskAvailable { return "Desk View is unavailable. Connect a compatible device or choose Camera layout." }
        return nil
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        pipeline.onPreview = { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if cameraAvailable != frame.cameraAvailable { cameraAvailable = frame.cameraAvailable }
                if deskAvailable != frame.deskAvailable { deskAvailable = frame.deskAvailable }
            }
        }
        pipeline.onAudioLevel = { [weak self] value in
            Task { @MainActor [weak self] in self?.audioLevel = value }
        }
        pipeline.onRecordingFinalizing = { [weak self] id, _ in
            Task { @MainActor [weak self] in
                guard let self, recordingID == id else { return }
                finalizingRecordingID = id
                isRecording = false; isSaving = true; startedAt = nil
                statusMessage = "Saving interrupted recording…"
            }
        }
        pipeline.onRecordingInterrupted = { [weak self] id, reason, result in
            Task { @MainActor [weak self] in
                guard let self, recordingID == id else { return }
                recordingID = nil; finalizingRecordingID = nil
                isRecording = false; isSaving = false; startedAt = nil
                switch result {
                case .success(let url): statusMessage = "Saved \(url.lastPathComponent)"; alertMessage = reason
                case .failure(let error): alertMessage = "\(reason)\n\(error.localizedDescription)"
                }
                await refreshLibrary()
            }
        }
        capture.onDevicesChanged = { [weak self] cameras, microphones in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cameras = cameras; self.microphones = microphones
                if !isPreviewRunning && !isBusy {
                    if !mainCameras.contains(where: { $0.id == selectedCameraID }) {
                        let preferred = AVCaptureDevice.systemPreferredCamera?.uniqueID
                        selectedCameraID = mainCameras.first(where: { $0.id == preferred })?.id ?? mainCameras.first?.id ?? ""
                    }
                    selectCompanionDesk()
                    if !(selectedMicrophoneID.isEmpty && microphonePreferenceWasSet) && !microphones.contains(where: { $0.id == selectedMicrophoneID }) {
                        selectedMicrophoneID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? microphones.first?.id ?? ""
                    }
                }
            }
        }
        capture.onError = { [weak self] failure in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let includedAudio = microphoneActive
                if case .audio = failure { microphoneActive = false; audioLevel = 0 }
                statusMessage = failure.message
                if isRecording && failure.affectsRecording(layout: configuration.layout, includesAudio: includedAudio) {
                    _ = await stopRecording()
                }
                alertMessage = failure.message
            }
        }
        pipeline.update(configuration)
        pipeline.start()
        capture.refreshDevices()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                if let startedAt { elapsed = Date().timeIntervalSince(startedAt) }
                if isPreviewRunning && !isDemo {
                    let current = await capture.effects()
                    if effects != current { effects = current }
                }
                let permission = AVCaptureDevice.authorizationStatus(for: .video)
                if cameraPermission != permission { cameraPermission = permission }
            }
        }
        Task { await refreshLibrary() }
        if ProcessInfo.processInfo.arguments.contains("--demo") { Task { await enableDemo() } }
    }

    func refreshDevices() { capture.refreshDevices() }

    func chooseCamera(_ id: String) {
        guard !isBusy else { return }
        selectedCameraID = id
        UserDefaults.standard.set(id, forKey: "studio.camera")
        selectCompanionDesk()
        if isPreviewRunning && !isDemo { scheduleSourceReconnect() }
    }

    func chooseDesk(_ id: String) {
        guard !isBusy else { return }
        selectedDeskID = id
        if isPreviewRunning && !isDemo { scheduleSourceReconnect() }
    }

    func chooseMicrophone(_ id: String) {
        guard !isBusy else { return }
        selectedMicrophoneID = id
        microphonePreferenceWasSet = true
        UserDefaults.standard.set(id, forKey: "studio.microphone")
        if isPreviewRunning && !isDemo {
            isConnecting = true
            Task {
                await connectAudio()
                isConnecting = false
            }
        }
    }

    private func selectCompanionDesk() {
        let companion = mainCameras.first(where: { $0.id == selectedCameraID })?.companionDeskID
        selectedDeskID = deskCameras.first(where: { $0.id == companion })?.id ?? deskCameras.first?.id ?? ""
    }

    func startPreview() async {
        guard !isBusy else { return }
        isConnecting = true
        defer { isConnecting = false }
        if isDemo {
            await capture.stopAll()
            pipeline.setDemo(camera: nil, desk: nil)
            isDemo = false; isPreviewRunning = false
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
            guard granted else { statusMessage = "Camera access is off. Enable it in System Settings."; return }
        } else if status != .authorized {
            cameraPermission = status
            statusMessage = "Camera access is off. Enable it in System Settings, then reopen deskView()."
            return
        }
        guard !selectedCameraID.isEmpty || !selectedDeskID.isEmpty else {
            statusMessage = "Choose a camera or Desk View in Sources, then start the preview. Refresh sources if your device is missing."
            showsGuide = true
            return
        }
        await configureSelectedSources()
    }

    private func scheduleSourceReconnect() {
        isConnecting = true
        Task {
            await configureSelectedSources()
            isConnecting = false
        }
    }

    private func configureSelectedSources() async {
        isDemo = false
        pipeline.setDemo(camera: nil, desk: nil)
        var connected = false
        do {
            try await capture.selectVideo(id: selectedCameraID.isEmpty ? nil : selectedCameraID, channel: .camera)
            connected = !selectedCameraID.isEmpty
        } catch { alertMessage = error.localizedDescription }
        do {
            try await capture.selectVideo(id: selectedDeskID.isEmpty ? nil : selectedDeskID, channel: .desk)
            connected = connected || !selectedDeskID.isEmpty
        } catch { alertMessage = error.localizedDescription }
        isPreviewRunning = connected
        statusMessage = connected ? "Preview is on. Your recording will match this canvas." : "The cameras could not start. Check the connection and try again."
        if connected { await connectAudio() }
    }

    private func connectAudio() async {
        microphoneActive = false
        audioLevel = 0
        try? await capture.selectAudio(id: nil)
        // Request microphone permission only when an actual microphone is chosen.
        guard !selectedMicrophoneID.isEmpty else { try? await capture.selectAudio(id: nil); return }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                statusMessage = "Microphone access is off. You can record a silent video or enable access in System Settings."
                return
            }
        } else if status != .authorized {
            statusMessage = "Microphone access is off. Recording will be silent."
            return
        }
        do { try await capture.selectAudio(id: selectedMicrophoneID); microphoneActive = true }
        catch { alertMessage = error.localizedDescription }
    }

    func stopPreview() async {
        guard !isBusy else { return }
        isConnecting = true
        await capture.stopAll()
        pipeline.setDemo(camera: nil, desk: nil)
        isDemo = false; isPreviewRunning = false; microphoneActive = false; audioLevel = 0
        cameraAvailable = false; deskAvailable = false
        statusMessage = "Preview stopped. Cameras and microphone are off."
        isConnecting = false
    }

    func enableDemo() async {
        guard !isBusy else { return }
        isConnecting = true
        defer { isConnecting = false }
        await capture.stopAll()
        let camera = DemoFrames.makeCamera()
        let desk = DemoFrames.makeDesk()
        pipeline.setDemo(camera: camera, desk: desk)
        isDemo = true; isPreviewRunning = true; microphoneActive = false; audioLevel = 0
        statusMessage = "Demo test chart. No camera or microphone is in use."
    }

    func toggleRecording() async {
        if isRecording { _ = await stopRecording(); return }
        guard canCapture, !isBusy else { return }
        let id = UUID()
        recordingID = id
        isSaving = true
        defer { if recordingID == id && finalizingRecordingID != id { isSaving = false } }
        do {
            let url = try newMediaURL(extension: "mov")
            try await pipeline.startRecording(to: url, includesAudio: microphoneActive && !isDemo, id: id)
            guard recordingID == id, finalizingRecordingID != id else { return }
            startedAt = Date(); elapsed = 0; isRecording = true
            statusMessage = isDemo ? "Recording demo test chart · silent" : (microphoneActive ? "Recording camera + audio" : "Recording · no microphone audio")
        } catch {
            if recordingID == id { recordingID = nil; isSaving = false; alertMessage = error.localizedDescription }
        }
    }

    @discardableResult
    func stopRecording() async -> Bool {
        guard let id = recordingID, isRecording || finalizingRecordingID == id else { return !isSaving }
        isRecording = false; isSaving = true; startedAt = nil
        finalizingRecordingID = id
        do {
            let url = try await pipeline.finishRecording(id: id)
            guard recordingID == id else { return true }
            recordingID = nil; finalizingRecordingID = nil; isSaving = false
            statusMessage = "Saved \(url.lastPathComponent)"
            await refreshLibrary()
            return true
        } catch {
            if recordingID == id {
                recordingID = nil; finalizingRecordingID = nil; isSaving = false
                alertMessage = error.localizedDescription
            }
            return false
        }
    }

    func takeSnapshot() async {
        guard canCapture, !snapshotBusy else { return }
        snapshotBusy = true
        defer { snapshotBusy = false }
        do {
            let url = try newMediaURL(extension: "png")
            try await pipeline.snapshot(to: url)
            statusMessage = "Snapshot saved · \(url.lastPathComponent)"
            await refreshLibrary()
        } catch { alertMessage = error.localizedDescription }
    }

    private func newMediaURL(extension ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let prefix = isDemo ? "deskView-demo" : "deskView"
        return destination.appendingPathComponent("\(prefix)_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6)).\(ext)")
    }

    func chooseDestination() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose where deskView() saves recordings"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = destination
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url; UserDefaults.standard.set(url, forKey: "studio.destination")
        Task { await refreshLibrary() }
    }

    func revealDestination() {
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            NSWorkspace.shared.open(destination)
        } catch { alertMessage = error.localizedDescription }
    }

    func refreshLibrary() async {
        let directory = destination
        let items = await Task.detached(priority: .utility) {
            let keys: Set<URLResourceKey> = [.creationDateKey, .fileSizeKey, .isRegularFileKey]
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            return urls.filter { ["mov", "png"].contains($0.pathExtension.lowercased()) }.compactMap { url -> MediaItem? in
                guard let info = try? url.resourceValues(forKeys: keys), info.isRegularFile == true else { return nil }
                return MediaItem(url: url, date: info.creationDate ?? .distantPast, bytes: Int64(info.fileSize ?? 0))
            }.sorted { $0.date > $1.date }
        }.value
        library = items
    }

    func showEffects() { AVCaptureDevice.showSystemUserInterface(.videoEffects) }
    func alignDeskView() async {
        guard !isBusy, !isAligningDeskView, !isDemo, !selectedDeskID.isEmpty else { return }
        if !isPreviewRunning { await startPreview() }
        guard isPreviewRunning else { return }
        isAligningDeskView = true
        statusMessage = "In Apple's Desk View window, place the keyboard inside the border and click Start Desk View."
        defer { isAligningDeskView = false }
        let launch = AVCaptureDeskViewApplication.LaunchConfiguration()
        launch.requiresSetUpModeCompletion = true
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                deskViewApplication.present(launchConfiguration: launch) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            // Native alignment defines the overhead region. Remove any extra
            // digital crop so the canvas shows the newly aligned desk region.
            configuration.deskFraming = SourceFraming()
            statusMessage = "Desk View alignment is ready. The canvas uses the paired overhead camera."
        } catch {
            alertMessage = "Desk View setup could not finish. \(error.localizedDescription)"
            statusMessage = "Choose Align Desk View to try the overhead setup again."
        }
    }
    func showMicrophoneModes() { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }
    func setCenterStage(_ enabled: Bool) { Task { await capture.setCenterStage(enabled); effects = await capture.effects() } }
    func reaction(_ type: AVCaptureReactionType) { capture.performReaction(type) }

    func openCameraPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    func shutdown() async {
        statusTask?.cancel()
        await capture.stopAll()
        pipeline.shutdown()
    }
}

// Frequent meter/clock ticks must not invalidate the full studio, inspector,
// source panels and output window through StudioModel.objectWillChange.
@MainActor final class AudioMeterState: ObservableObject {
    @Published var level: Float = 0
}

@MainActor final class RecordingClockState: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    var timecode: String {
        let seconds = max(0, Int(elapsed))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}

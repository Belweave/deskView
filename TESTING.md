# Testing

Run `./scripts/test.sh`. It verifies the selected Xcode, then runs Swift Testing through SwiftPM with two jobs and disk-backed `.build/package` storage. Run `./scripts/build.sh Debug` or `Release` to compile the full app, FoyerKit and Metal resources.

## Automated coverage

`CompositorTests` checks actual pixels for both sources, inset placement and swapping, portrait arrangement, mirroring and rotation. It also checks even encoder dimensions and malformed framing values.

`RecordingTests` writes a real movie containing composed H.264 video and a synthetic AAC tone. It decodes video pixels and audio samples, verifies a deliberate 200 ms audio delay, and reads track dimensions and duration. It also feeds live `CMSampleBuffer` frames through the capture ingestion path, verifies cleared-source preview pixels and availability, two-second expiry and playable interruption finalization, duplicate Stop calls, recording UUID isolation, unused-source failure policy, empty-movie cleanup, required-source rejection and full-resolution PNG dimensions. Tests use temporary directories and clean up only their own files.

The 60 fps regression test decodes sixty movie frames and checks their distinct presentation times. `PreviewTests` verifies bounded latest-frame replacement, arrival-time expiry, 60 Hz composition, and actual GPU-rendered pixels and letterboxing. The Metal pixel check is skipped on CI hosts without a Metal device.

## Performance measurement

Run `./scripts/performance.sh 5` with the app stopped. The Release harness uses synthetic 1080p charts, three Metal preview surfaces and simultaneous 60 fps recording at 720p, 1080p and 4K. It warms the hardware encoder for one second before measuring sustained preview cadence and reports startup surface skips separately. JSON includes composition cadence, completed preview fps, mean GPU duration, skipped preview work and full-movie decoded cadence including startup. It opens no capture devices and cleans up its generated movies. This measures the current Mac; it cannot establish performance on every device or create 60 unique frames from a 30 fps source.

For the visible app, stream the `org.belweave.deskView` subsystem with macOS `log stream --level info`. Preview and capture counters are emitted every five seconds. Measure with the Release app, visible windows, and no concurrent build. Source fps and rendered fps are separate measurements.

## Native smoke check

`./scripts/run.sh --demo --skip-intro` starts labeled test charts with no camera/microphone access. Verify all four layouts, framing controls, aspect ratio, recording start/stop, PNG snapshots, file browsing and Output window. Repeat at the default and minimum window sizes. Test charts must remain labeled as demo content. Also verify the stopped/empty state and replay the FoyerKit welcome.

## Hardware checklist

These checks need a real camera, a compatible Desk View source and permission granted in macOS:

- Select an iPhone through Continuity Camera and confirm its paired Desk View becomes available.
- Choose Align Desk View, frame the keyboard in Apple's setup window, then verify the studio's desk canvas shows the same overhead region.
- Start both feeds, record a spoken presentation, and verify picture, sound and synchronization in QuickTime Player.
- Disconnect a required source during recording; confirm the app reports the interruption and saves the playable portion.
- Deny/revoke camera or microphone permission; confirm the app explains recovery and does not imply that silent recording contains audio.
- Switch between built-in, external and Continuity Camera sources; confirm source names and thumbnails match.
- Exercise supported Center Stage, Portrait, Studio Light, background replacement, reactions and microphone modes through macOS.
- Share the clean Output window in a call and verify recipients see only the canvas.

Passing automated media tests does not establish these hardware behaviors. The initial build was developed and tested locally on Apple Silicon with Xcode 27.1 (27A9275); current results are recorded in the [initial release verification report](Documentation/Verification.md).

## CI and packaging

GitHub Actions uses the `xcode-27` arm64 image and selects its Xcode 27.1 RC installation explicitly. CI runs the same tests and app build. The manual Package app workflow creates an ad-hoc-signed development ZIP and retains the build log. It does not upload to App Store Connect or publish a GitHub release.

# Architecture

`deskView()` is a macOS 26+ SwiftUI app targeting arm64. It uses public Apple frameworks and FoyerKit for onboarding. There is no server or network capture layer.

## Capture and concurrency

`StudioModel` is the main-actor UI state owner. Permission requests, device choices, recording state and save-folder preferences live here. Opening the app discovers devices; starting the preview is an explicit action. Demo charts avoid physical capture entirely.

`CaptureService` confines session changes and device configuration to a serial capture queue. Main-camera, paired Desk View and optional microphone sessions run independently. Discovery uses `continuityCamera` and `deskViewCamera`, along with built-in and external devices. `companionDeskViewCamera` determines the preferred Desk View pairing. Discovery changes refresh source choices; runtime errors are scoped to this app's sessions. A separate delegate queue delivers late-frame-discarding video outputs and Float32 microphone audio.

`StudioPipeline` owns mutable media state on one serial media queue. Capture callbacks hand off sample buffers; a 30 Hz timer reads the latest frames. A source becomes unavailable after two seconds without a new frame. UI previews render at 15 Hz with a maximum width of 1280 pixels. Recordings render at the selected 24/30 fps cadence. Preview delivery crosses to the main actor; expensive session start/stop and media encoding never run there.

## One composed output

`FrameCompositor` crops and transforms each source, then renders camera, desk, side-by-side or picture-in-picture into a fixed canvas. Portrait side-by-side uses a vertical arrangement. Pan and zoom are digital transformations of delivered frames. The same composition is used for previews, full-resolution PNG snapshots and the movie writer; the preview-only grid and UI chrome are excluded.

`MovieRecorder` writes H.264 video and optional mono AAC audio into a `.mov`. Both use the host-clock timebase. The first video frame starts the asset session; earlier audio is discarded. Duplicate/non-increasing video timestamps are discarded, and backpressure drops video frames rather than blocking capture. The final frame's duration is included when ending the session.

Changing capture sources, framing or output settings is disabled while recording or saving. The media pipeline rejects configuration updates and new recordings until finalization completes. Recording callbacks carry a UUID; duplicate Stop requests for that UUID join the pending finalization or receive its retained result. Failure of a required video source, an included microphone or the movie writer finalizes the available recording and reports the result; failure of an unused source is reported without stopping a healthy recording. Quitting an active recording waits for finalization; a failure leaves the studio open with an explanation.

## Storage and dependencies

Recordings and snapshots use unique timestamp + random-suffix names in the user-selected directory (default `~/Movies/deskView`). Preferences are local `UserDefaults` values. The app is not sandboxed; it has camera/audio hardened-runtime entitlements and explicit usage descriptions. No capture happens before the user starts a real preview.

The Xcode project links the root `DeskViewKit` package and pins FoyerKit to commit `9b4ed7e5d3fd1b208b59c1675fdbf48e66c54509`. A standard-library Python generator produces the committed project. Xcode compiles FoyerKit's Metal shader into its resource bundle.

## Output and system effects

The clean Output window shows the shared composed preview. A call app can screen-share this window. Virtual-camera system extensions are outside the current implementation.

Center Stage uses cooperative AVFoundation control when the active camera format supports it. Portrait, Studio Light, background replacement and microphone modes remain controlled through macOS system UI. State is refreshed while a real preview runs. Reaction calls validate the active device's advertised reaction set before invoking the effect.

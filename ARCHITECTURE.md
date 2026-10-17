# Architecture

`deskView()` is a macOS 26+ SwiftUI app targeting arm64. It uses public Apple frameworks and FoyerKit for onboarding. There is no server or network capture layer.

## Capture and concurrency

`StudioModel` is the main-actor UI state owner. Permission requests, device choices, recording state and save-folder preferences live here. Opening the app discovers devices; starting the preview is an explicit action. Demo charts avoid physical capture entirely.

`CaptureService` confines session changes and device configuration to a serial capture queue. Main-camera, paired Desk View and optional microphone sessions run independently. Discovery uses `continuityCamera` and `deskViewCamera`, along with built-in and external devices. `companionDeskViewCamera` determines the preferred Desk View pairing. Discovery changes refresh source choices; runtime errors are scoped to this app's sessions. A separate delegate queue delivers late-frame-discarding video outputs and Float32 microphone audio.

`CaptureService` selects a 60 fps format near 1080p when available, and otherwise uses the source's fastest supported rate. Desk View may expose only a 30 fps format. Format selection does not invent additional source motion.

`StudioPipeline` owns configuration and recording state on a serial media queue. Video callbacks replace one frame slot per source under a short lock; they never enqueue a growing list of buffers. A 60 Hz timer composes the latest fresh frames into immutable Core Image graphs. Freshness is measured from capture arrival, with a two-second expiry. `PreviewStream` retains only the newest composition and source images. SwiftUI observes availability changes, not video frames. Clock and 10 Hz audio-meter updates have separate observable objects so they refresh only their small views.

`MetalPreview` uses display-paced `MTKView` surfaces at a 60 Hz target. `MetalPreviewRenderer` encodes Core Image directly into drawable textures on a background queue, with at most two GPU commands in flight and no CPU image readback. Main canvas, source views and clean output use this same path. Demo bitmaps are uploaded once into IOSurface-backed pixel buffers to avoid repeated CPU texture compression. Local OSLog counters report preview and capture cadence without image or audio content.

`RecordingWorker` isolates GPU-to-encoder synchronization from preview composition. It permits two pending video operations and sixteen audio operations; backpressure drops work rather than building latency. PNG encoding also has a separate queue. Recordings offer 24, 30 and 60 fps. Their timestamp slots are relative to the first video tick on the shared host clock, avoiding duplicate slots caused by absolute-clock timer phase.

Fresh frames, demo playback or recording/finalization hold a user-initiated, latency-critical process activity. It keeps background media work from being throttled by App Nap and timer coalescing. The activity ends when inputs expire and recording has finished, or on shutdown. It permits idle system sleep.

## One composed output

`FrameCompositor` crops and transforms each source, then renders camera, desk, side-by-side or picture-in-picture into a fixed canvas. Portrait side-by-side uses a vertical arrangement. Pan and zoom are digital transformations of delivered frames. The same composition is used for previews, full-resolution PNG snapshots and the movie writer; the preview-only grid and UI chrome are excluded.

`MovieRecorder` writes H.264 video and optional mono AAC audio into a `.mov`. Both use the host-clock timebase. The first video frame starts the asset session; earlier audio is discarded. Duplicate/non-increasing video timestamps are discarded, and backpressure drops video frames rather than blocking capture. The final frame's duration is included when ending the session.

Changing capture sources, framing or output settings is disabled while recording or saving. The media pipeline rejects configuration updates and new recordings until finalization completes. Recording callbacks carry a UUID; duplicate Stop requests for that UUID join the pending finalization or receive its retained result. Failure of a required video source, an included microphone or the movie writer finalizes the available recording and reports the result; failure of an unused source is reported without stopping a healthy recording. Quitting an active recording waits for finalization; a failure leaves the studio open with an explanation.

## Storage and dependencies

Recordings and snapshots use unique timestamp + random-suffix names in the user-selected directory (default `~/Movies/deskView`). Preferences are local `UserDefaults` values. The app is not sandboxed; it has camera/audio hardened-runtime entitlements and explicit usage descriptions. No capture happens before the user starts a real preview.

The Xcode project links the root `DeskViewKit` package and pins FoyerKit to commit `9b4ed7e5d3fd1b208b59c1675fdbf48e66c54509`. A standard-library Python generator produces the committed project. Xcode compiles FoyerKit's Metal shader into its resource bundle.

## Output and system effects

The clean Output window shows the shared composed preview. A call app can screen-share this window. Virtual-camera system extensions are outside the current implementation.

The Align Desk View action presents `AVCaptureDeskViewApplication` with setup-completion tracking. Apple owns the physical overhead region and its perspective correction; the app's digital crop is applied afterward. Alignment opens the selected camera preview if necessary and resets the extra desk crop after setup completes.

Center Stage uses cooperative AVFoundation control when the active camera format supports it. Portrait, Studio Light, background replacement and microphone modes remain controlled through macOS system UI. State is refreshed while a real preview runs. Reaction calls validate the active device's advertised reaction set before invoking the effect.

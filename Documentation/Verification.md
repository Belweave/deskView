# Initial release verification

Verified locally on Apple Silicon, 2026-10-17, with Xcode 27.1 RC (27A9275).

## Passed

- Debug and Release app builds, including FoyerKit and its Metal resources.
- Thirteen Swift Testing tests in two suites. These include actual H.264 encoding/video decoding, AAC tone decoding and a deliberate 200 ms audio offset, live sample-buffer ingestion, cleared-source preview pixels and availability, two-second source expiry, playable interruption finalization, duplicate Stop requests, recording UUID isolation, compositor pixels, framing transforms and PNG output dimensions.
- Native demo: all four layout controls; recording start/stop and locked setup controls; PNG snapshot; media library listing; clean Output window; stopped preview state.
- Native FoyerKit welcome replay, accessible page headings, Continue and Skip returning to the studio.
- Default and minimum-width native captures. The final review found no clipping or obscured primary actions. The Record action was darkened to bring white label contrast above 4.5:1; both revised captures were accepted.
- Bundled FoyerKit license/attribution notices and pinned package resolution.

## Scope of review

The native code review found and verified fixes for recording-finalization ownership, preservation of an explicit silent-microphone choice, failure of an unused source stopping a healthy recording, and stale preview availability after clearing the last source. The last-source regression test failed before its fix and passed afterward. A separate test-coverage audit informed the live-ingestion and decoded-audio checks.

An optional external Claude Code review timed out and supplied no completed review coverage. Native review and the checks above completed independently.

## Requires physical validation

Physical camera/microphone permission, live iPhone + paired Desk View capture, real spoken synchronization, hardware disconnect behavior, hardware video effects and recipients' screen-sharing output were not exercised in this verification. Synthetic media and discovery of available devices do not establish those behaviors. Use the hardware checklist in [TESTING.md](../TESTING.md).

Local development builds use ad-hoc signing. Developer ID signing, notarization and App Store distribution are outside this source release.

## Desk View and performance follow-up

The initial app omitted a direct entry point to Apple's Desk View alignment. Opening Apple's setup and selecting the keyboard region resolved the reported overhead-framing problem, confirmed by the tester. The studio now includes Align Desk View and corresponding setup guidance.

The original pipeline forced capture to 30 fps and copied previews to CPU images at 15 Hz. The replacement uses 60 Hz Metal surfaces, latest-frame slots, a separate bounded recording worker and 24/30/60 fps output. Demo bitmaps are uploaded once, command encoding runs off the UI thread, and clock/audio-meter observation is isolated from the studio. Active media work holds a process activity to prevent background throttling, released when frames stop or the pipeline shuts down. Eighteen automated tests and Debug/Release builds pass, including GPU pixels, frame replacement/expiry, and a decoded sixty-frame movie with distinct 1/60-second presentation times.

A Release synthetic benchmark on an Apple M3 Mac with 24 GB RAM ran three preview surfaces while recording for five measured seconds at each resolution, after encoder warmup. Preview cadence was 59.95–59.98 fps with zero skipped GPU submissions across 720p, 1080p and 4K. Main-preview GPU work averaged 1.29–1.98 ms. Full-movie decoded cadence, including startup, was 59.68 fps at 720p and 60 fps at 1080p/4K. These measurements cover this Mac and workload, not every supported device. Run `scripts/performance.sh` to repeat them.

Native onscreen profiling used the studio canvas, both source previews and clean Output window while recording. The final steady-state sample sustained approximately 60 fps on all four surfaces with zero skipped GPU submissions. A 95.17-second native 1080p demo recording contains exactly 5,710 frames at 60 fps. The Record/Stop controls, timecode and recording-time setup lockout were exercised. These charts contain no personal camera content.

The connected iPhone advertises a 60 fps main-camera format, while its paired Desk View and this Mac's built-in camera advertise at most 30 fps. A 60 Hz preview or 60 fps file repeats frames from those slower sources. An earlier local hardware test produced a 134.8-second 1080p H.264 movie with a 48 kHz mono AAC track; audio decoding confirmed a non-silent signal. No personal media is included in the repository. The iPhone was unavailable during the final build's checks; final dual-feed alignment, live source cadence and spoken synchronization require reconnection.

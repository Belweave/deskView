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

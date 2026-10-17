# Changelog

## Unreleased

- Add direct access to Apple's Desk View alignment and keyboard-framing guidance.
- Replace the 15 Hz CPU-image preview with 60 Hz Metal surfaces and GPU-compatible frame storage.
- Offer 60 fps recording and select faster capture formats where hardware supports them.
- Bound video handoff and encoder queues; move recording, snapshots and GPU command encoding off the UI path.
- Upload demo charts once, preventing repeated texture compression on the UI thread.
- Add GPU, cadence and decoded 60 fps movie regression checks plus a reproducible performance harness.

## 0.1.0 — 2026-10-17

First camera studio for Apple Silicon Macs, with a native SwiftUI / Liquid Glass workspace and FoyerKit welcome.

- Bring Continuity Camera and a paired Desk View into one composed presentation.
- Record H.264 movies with optional microphone audio, or save PNG snapshots.
- Choose picture in picture, side by side, camera or desk; crop, pan, mirror and rotate each source.
- Use macOS video effects and share a clean Output window.
- Browse local media, choose a save folder, and try labeled demo charts without a camera.
- Include focused compositor and real movie-encoding tests, local build scripts and GitHub Actions.

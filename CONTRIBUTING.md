# Contributing

Use an Apple Silicon Mac with macOS 26+, Xcode 27.1 RC (27A9275) or a newer stable Xcode, and Apple's Metal toolchain.

1. Create a feature branch.
2. Keep AVFoundation session mutations off the main actor and media mutations on the pipeline queue.
3. Add focused tests for changes to composition, timestamps, storage or recording failure behavior.
4. Run `./scripts/test.sh` and `./scripts/build.sh Debug`.
5. For interface changes, compare the native app with `DESIGN.md` and the approved Canvas-first layout. Preserve accessibility labels, keyboard shortcuts and usable missing-device states.

After changing the app's source-file list, regenerate with `python3 scripts/generate-project.py`. Do not commit `.build`, recordings, local permissions, signing credentials or user-specific Xcode data. Include observed validation and any hardware checks you could not perform in your pull request.

# Working on deskView()

## Apple toolchain preference

- On this Mac, use Xcode 27.1 Release Candidate (build 27A9275) globally for Apple-platform projects until a newer stable Xcode release is available. Verify the installed version before building; do not fall back to an older beta silently.
- Prefer local builds, bounded concurrency, and disk-backed build storage. Coordinate large builds with other active projects to avoid memory pressure.

## Build and testing

- App: `./scripts/build.sh Debug` (or `Release`).
- Tests: `./scripts/test.sh`; meaningful media tests live in `Tests/DeskViewKitTests`.
- Launch: `./scripts/run.sh`. Demo: `./scripts/run.sh --demo --skip-intro`.
- Regenerate the committed Xcode project after changing app files: `python3 scripts/generate-project.py`.
- Keep build storage in `.build/` and use two jobs by default (maximum four).
- See `TESTING.md` for hardware checks. Never claim physical Continuity Camera/Desk View validation from synthetic media tests.

## Product and architecture

- The product name is `deskView()`. The repository slug is `deskView`.
- Use FoyerKit for onboarding. Pin dependency changes deliberately.
- Native SwiftUI and Liquid Glass; approved layout is Canvas first, documented in `DESIGN.md`.
- `StudioModel` owns main-actor UI state. `CaptureService` and `StudioPipeline` each confine mutable state to their own serial queues.
- Preview, snapshots and movies must use the same compositor. Mark demo content explicitly.
- Public Apple APIs only. macOS owns availability and hardware video effects.
- Keep all user recordings local. Never commit personal camera content or credentials.

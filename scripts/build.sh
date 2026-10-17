#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-toolchain.sh
deskview_configuration="${1:-Debug}"
if [[ "$deskview_configuration" != "Debug" && "$deskview_configuration" != "Release" ]]; then
    echo 'Usage: scripts/build.sh [Debug|Release]' >&2
    exit 1
fi
deskview_jobs="${DESKVIEW_JOBS:-2}"
if ! [[ "$deskview_jobs" =~ ^[1-4]$ ]]; then
    echo 'DESKVIEW_JOBS must be 1–4 (default 2).' >&2
    exit 1
fi
mkdir -p .build/logs
deskview_log=".build/logs/build-${deskview_configuration}.log"
if ! xcodebuild -project DeskView.xcodeproj -scheme deskView \
    -configuration "$deskview_configuration" -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$PWD/.build/xcode" -clonedSourcePackagesDirPath "$PWD/.build/SourcePackages" \
    -jobs "$deskview_jobs" build > "$deskview_log" 2>&1; then
    tail -n 100 "$deskview_log"
    exit 1
fi
tail -n 5 "$deskview_log"
echo "App: $PWD/.build/xcode/Build/Products/$deskview_configuration/deskView().app"

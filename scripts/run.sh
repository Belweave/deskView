#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh Debug
open '.build/xcode/Build/Products/Debug/deskView().app' --args "$@"

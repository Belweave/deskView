#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-toolchain.sh
swift test --jobs 2 --scratch-path .build/package

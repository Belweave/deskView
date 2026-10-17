#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-toolchain.sh
swift run --configuration release --jobs 2 --scratch-path .build/package DeskViewBench "${1:-5}"

#!/bin/bash
set -euo pipefail
deskview_xcode_info="$(xcodebuild -version)"
python3 - "$deskview_xcode_info" <<'PY'
import re, sys
info = sys.argv[1]
version = re.search(r'Xcode (\d+)\.(\d+)', info)
build = re.search(r'Build version (\S+)', info)
if not version or not build:
    sys.exit('Could not verify Xcode. Select Xcode 27.1 RC (27A9275) or a newer stable release.')
v = tuple(map(int, version.groups()))
b = build.group(1)
if b != '27A9275' and (v < (27, 1) or b[-1].islower()):
    sys.exit(f'Unsupported toolchain: {info}. Use Xcode 27.1 RC (27A9275) or a newer stable release.')
print(info)
PY
if [ "$(uname -m)" != "arm64" ]; then
    echo 'deskView() targets Apple Silicon. Run the build natively on an arm64 Mac.' >&2
    exit 1
fi

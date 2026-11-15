#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The standalone Command Line Tools may omit the Testing plug-in from SwiftPM's search paths.
flags=(--disable-xctest)
developer="$(xcode-select -p)"
plugin="$developer/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$plugin" ]; then
    flags+=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
fi
swift test "${flags[@]}" "$@"

#!/bin/bash
# Runs the unit tests (HotSyncCore). With only the Command Line Tools
# installed, swift-testing lives outside the default search paths.
set -euo pipefail
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$CLT/Frameworks/Testing.framework" ]; then
  exec swift test -Xswiftc -F"$CLT/Frameworks" -Xlinker -F"$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
fi
exec swift test "$@"

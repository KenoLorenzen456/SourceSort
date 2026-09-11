#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed (no Xcode), swift-testing
# lives outside the default search paths, so point the compiler and linker at it.
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer
if [[ -d $F/Frameworks/Testing.framework ]]; then
  exec swift test -Xswiftc -F -Xswiftc $F/Frameworks -Xlinker -F -Xlinker $F/Frameworks \
    -Xlinker -rpath -Xlinker $F/Frameworks -Xlinker -rpath -Xlinker $F/usr/lib "$@"
fi
exec swift test "$@"

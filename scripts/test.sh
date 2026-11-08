#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/full-mac-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang -fobjc-arc -fmodules -Wall -Wextra \
    -framework AppKit -framework CoreGraphics -framework ServiceManagement \
    "$ROOT/Tests/BrightnessControls.m" -o "$TEST_DIR/brightness-tests"
"$TEST_DIR/brightness-tests"

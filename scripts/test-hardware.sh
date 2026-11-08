#!/bin/bash
# Explicit opt-in: exercises both connected physical screens and leaves boost on.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/full-mac-hardware.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang -fobjc-arc -Wall -Wextra \
    -framework AppKit -framework CoreGraphics -framework ServiceManagement \
    "$ROOT/Tests/HardwareBrightness.m" -o "$TEST_DIR/hardware-tests"
"$TEST_DIR/hardware-tests"

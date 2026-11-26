#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build/tests}"
mkdir -p "$BUILD_DIR"

xcrun swiftc \
  -swift-version 5 \
  -framework CoreGraphics \
  -framework Foundation \
  -o "$BUILD_DIR/notch-tests" \
  "$ROOT/tests/NotchTests.swift" \
  "$ROOT/DisplayMode.swift" \
  "$ROOT/NotchGeometry.swift"

"$BUILD_DIR/notch-tests"

#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build/tests}"
MODULE_CACHE="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-module-cache-tests}"
mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  -swift-version 5 \
  -framework Cocoa \
  -framework CoreGraphics \
  -framework Foundation \
  -o "$BUILD_DIR/notch-tests" \
  "$ROOT/tests/NotchTests.swift" \
  "$ROOT/ThemeModels.swift" \
  "$ROOT/DisplayMode.swift" \
  "$ROOT/NotchGeometry.swift"

"$BUILD_DIR/notch-tests"

xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  -swift-version 5 \
  -framework Cocoa \
  -framework QuartzCore \
  -framework CoreAudio \
  -framework Accelerate \
  -framework AudioToolbox \
  -o "$BUILD_DIR/core-tests" \
  "$ROOT/tests/CoreEngineTests.swift" \
  "$ROOT/ThemeModels.swift" \
  "$ROOT/TextRomanizerAndArtwork.swift" \
  "$ROOT/LyricsParserAndFetcher.swift" \
  "$ROOT/VocalAutoSyncEngine.swift" \
  "$ROOT/TouchBarLyricsView.swift" \
  "$ROOT/NotchGeometry.swift" \
  "$ROOT/NotchLyricsWindowController.swift"

"$BUILD_DIR/core-tests"

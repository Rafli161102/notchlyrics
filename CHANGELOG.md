# Changelog

Format mengikuti [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versi mengikuti [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `README.md`, `CHANGELOG.md`, `.gitignore`.
- **Notch output:** `NotchLyricsWindowController`, top-center transparent `NSPanel`, `DisplayMode` Touch Bar / Notch / Both / Hidden, physical-notch-aware top inset, secondary display support, same lyrics/theme/artwork pipeline, reduced-motion handling.
- `tests/run.sh` + `tests/NotchTests.swift` standalone tests for display-mode routing and top-center geometry.
- `build.sh` reproducible local build, source `Info.plist`, `VERSION`, `BUILD_NUMBER`, signing hook.
- `notarize.sh` untuk Developer ID + notarytool + stapler.

### Changed
- Source dapat di-`git init`; build tidak lagi bergantung pada app bundle yang sudah ada.

### Notes
- Lisensi belum dipilih; jangan publish source sebelum memilih lisensi.
- Notarization memerlukan kredensial Apple; tidak disimpan di repo.
- Mode Notch belum di-screenshot/di-verifikasi pada Touch Bar fisik + physical-notch hardware.

## [2.1] - 2026-11-26

### Added
- **Lyrics:** karaoke per huruf/per kata, per-word timing, synthesized timing, main + backing vocal independent progress.
- **Lyrics sources:** LRCLIB + NetEase paralel, ranking durasi/granularity, Lyrics.ovh fallback, LRC/YRC/enhanced LRC, estimated plain lyrics.
- **Romanization:** Jepang (`CFStringTokenizer`, romaji), Korea, China, Cyrillic, Thai, Arabic; romanized word timing.
- **Auto-sync vokal:** CoreAudio Process Tap + private aggregate, 300–3400 Hz biquad, mid/side, adaptive floor/peak, lead + backing offsets, clarity, consensus, reset; fallback timestamp.
- **Color:** artwork palette extraction ImageIO, WCAG contrast guard, adaptiveArtwork/vividArtwork/themeOnly, live tint, EQ/progress motion.
- **Themes:** 4 built-in + custom editor; layout, slots, alignment, fonts, sizes, padding, EQ, backing placement, transitions, word animations, animation speeds, karaoke offset, color sync; JSON persistence.
- **Animation:** `karaokeLift`, `smoothWipe`, `typewriter`, `glowPulse`, `solid`; `pushUp`, `pushDown`, `slideLeft`, `crossfade`, `zoomSoft`, `none`; `reduceMotion`.
- **Media:** Safari-only default, Now Playing streaming, play/pause, single instance, graceful shutdown, adapter cleanup.
- **App:** version 2.1 build 3, macOS 14.2+, ad-hoc signing local, source modular 8 Swift files.

### Fixed
- Kompilasi `FetchedLyricsResult` setelah penambahan `romanizedLines`.
- Restart CoreAudio tap setelah pause/resume; retry cooldown reset on stop.
- Engine reset saat track change; manual offset reset lead + backing.
- Scoring alignment optimized; optional reduce-motion/animation disable.

### Known limitations
- Belum ada XCTest/CI; verifikasi ad-hoc manual + build/runtime.
- Touch Bar visual belum di-screenshot otomatis.
- Accuracy sync bergantung izin audio, timing sumber, center-panned vokal; fallback timestamp.
- Lirik membutuhkan network sumber eksternal; estimated fallback bisa kurang akurat.
- Dependency Atoll MediaRemoteAdapter hard-coded.
- Source belum git init sebelum perubahan rilis ini; signing ad-hoc bukan Developer ID; belum notarized.

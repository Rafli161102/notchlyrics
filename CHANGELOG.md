# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/).

## [2.3] - 2026-11-27

### Added
- **Multi-Language Settings UI (`English` Default + 5 Languages):** Added `Localization.swift` and `windows/i18n.js` supporting live switching across **English** (default), **Bahasa Indonesia**, **日本語**, **한국어**, **简体中文**, and **Español** directly from both the macOS Studio / Menu Bar and Windows System Tray.
- **Crowded Vocal & Backing Vocal Choreography:** Added selectable `VocalSyncMode` presets (`Auto Balanced`, `Stable (Crowded Vocals / Chorus)`, `Aggressive`, `Manual`), dense-chorus consensus protection, backing-vocal clarity noise floor, `< 0.14s` duet merge guard so fast rap/chorus lines never collapse into backing vocals, unison `0.0s` backing lock, and compact dual-layer bounce dampening.
- **Sub-Second Cadence Calibration & Fine Sync Controls:** Added track-wide median singing cadence (`trackSecPerUnit`) so short lines before long breaks keep natural timing, independent **Backing Vocal Offset** (`-1.50s..+1.50s`), wider **Word Sweep Speed** (`0.40x–2.20x`) and **Shift Timing** (`-2.50s..+2.50s`) sliders, quick `±0.05s / ±0.25s` nudge buttons, speed presets (`0.75x / 1.00x / 1.25x`), and one-click **Recalibrate Auto-Sync**.
- **More Lyric & Metadata Sources:** Added **Kuwo Music** (`search.kuwo.cn` + `m.kuwo.cn`) synced LRC racing and concurrent **iTunes + Deezer Search** metadata normalization for Romanized Japanese/Korean tracks on both macOS and Windows.

## [2.2] - 2026-11-26

### Added
- **MIT License:** Added `LICENSE` (MIT) and full English GitHub documentation (`README.md`, `windows/README.md`, `web/README.md`).
- **Multi-User macOS Portability:** `AppDelegate` resolves bundled/local `MediaRemoteAdapter` cleanly and adds zero-dependency Apple Events fallback (`Music`, `Spotify`, `Safari`) when external adapters are absent; auto-selects Notch mode on Macs with physical camera notches; `build.sh` supports `--universal`, `--package`, and automatic resource bundling.
- **Windows Desktop Companion (`windows/`) & Extension (`windows/browser-extension/`):** Always-on-top Electron Golden Ratio OLED Notch app backed by WinRT SMTC (`win_smtc.ps1`), shared multi-source JS lyrics & Hangul/CJK engine (`lyrics-engine.js`), automated Node unit tests (`windows/tests/lyrics-engine.test.js`), plus Manifest V3 extension for Chrome/Edge/Brave.
- **Cross-Platform GitHub Actions CI:** Added `.github/workflows/ci-build.yml` to build & test both macOS Universal `.app` and Windows `.exe`.
- **Intonation & Real-Time Vocal DSP:** Added CoreAudio zero-crossing vocal pitch/brightness (`vocalIntonation`) and syllable onset pulse (`vocalOnset`), dynamic singing tempo pacing (`realtimeDeliveryTempoScale`), linguistic phrasing weights, progress cursor glow bead, and 3-zone chromatic karaoke sweep.
- **Multilingual Romaji & Complex Script Accuracy:** Particle corrections (`は/へ/を` -> `wa/e/o`), cross-token Japanese sokuon & chōonpu handling (`待っていた` -> `matte ita`, `コーヒー` -> `koohii`), YRC isolated `っ` gemination, algorithmic Korean Hangul Revised Romanization (`사랑해요 괜찮아 빨리`), clean Cyrillic, and intact word-cluster sweeps for RTL Arabic/Hebrew, Hindi, and Thai.
- **Notch Polish:** Zero-truncation multi-line auto-fit wrapping, pure `#000000` OLED black preservation with album-tinted lyrics text, hover-expanded `MM:SS / MM:SS` playback timer, and Golden Ratio geometry (`phi = 1.618`) across Attached Bezel, Floating Island, and Edge Dock Strip styles.

## [2.1] - 2026-11-26

### Added
- **Lyrics:** Karaoke per-letter/per-word sweep, synthesized timings, independent main + backing vocal progress.
- **Lyrics sources:** LRCLIB + NetEase parallel search, Lyrics.ovh fallback, LRC/YRC/enhanced LRC parsing.
- **Auto-sync vocal:** CoreAudio Process Tap + private aggregate device, 300–3400 Hz biquad, mid/side separation, lead + backing offsets.
- **Themes & Colors:** 4 built-in themes + live Studio editor, artwork color extraction with WCAG AA contrast guard.

# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/).

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

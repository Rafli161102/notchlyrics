# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/).

## [2.4.0] - 2026-11-27

### Added
- **Native Linux Desktop Support (`windows/mpris_bridge.js`, `windows/package.json`):** Zero-dependency Node.js MPRIS2 bridge using `playerctl --follow` streaming (with `gdbus` and `dbus-send` D-Bus polling fallback) for Spotify, Chrome, Firefox, VLC, and native MPRIS2 players, X11/Wayland transparent always-on-top `BrowserWindow` configuration, `userData` persistence, system tray integration, and `dist:linux` packaging for `.AppImage` and `.deb` (`x64`).
- **Official Landing & Download Website (`site/`):** Vercel-ready static site for [`https://notchlyrics.mrr.my.id`](https://notchlyrics.mrr.my.id) featuring automatic OS detection (`macOS`, `Windows`, `Linux`), an interactive live OLED Notch simulator, platform-specific install tabs, Open Graph/SEO metadata, and `site/vercel.json` headers.
- **Per-Track Refetch Cache & Manual Lyrics Offset:** Added **Refetch Lyrics (Clear Cache)** (`clearTrackCache` removing only the active track cache) and **Manual Lyrics Offset** (`+0.5s`, `+0.1s`, `-0.1s`, `-0.5s`, `0.0s` reset) persisted in `settings.json` across macOS, Windows, and Linux.
- **Touch Bar & Studio Customization Polish:** Fixed background vocal clipping on Touch Bar, added per-pixel spacing, custom font selection, karaoke animation refinements, and deterministic Reduce Motion lift tests.

### Changed
- **Lock-Free `vDSP` CoreAudio Pipeline (`VocalAutoSyncEngine.swift`):** Upgraded real-time vocal energy and intonation tracking to a lock-free ring buffer and Accelerate `vDSP` processing.
- **Event-Driven Desktop IPC & `rAF` Karaoke Loop (`windows/main.js`, `windows/renderer/lyrics-timing.js`):** Replaced redundant idle/paused polling broadcasts with event-driven snapshots and a client-side `requestAnimationFrame` sweep loop that halts automatically when paused or hidden.
- **Node.js 24 CI/CD & Linux Release Automation (`.github/workflows/`):** Updated workflows to Node.js 24 (`actions/checkout@v6`, `actions/setup-node@v6`, `actions/upload-artifact@v6`) and added the `linux-package` job (`ubuntu-latest`) to build, verify (`app.asar` + outputs), and attach `.AppImage` and `.deb` assets alongside macOS and Windows builds.

### Fixed
- **LRC, Enhanced LRC & Kuwo Parser Reliability (`windows/lyrics-engine.js`, `LyricsParserAndFetcher.swift`):** Added Enhanced LRC `<mm:ss.xx>` word tag parsing, instrumental break `endTime` handling on empty timestamp lines, band/artist preservation (`Earth, Wind & Fire`, `Tyler, The Creator`, `Sammy Davis, Jr.`), `cleanTitle` pipe/quote guards, and resilient `parseKuwoSearchResponse` / `mapKuwoLrcList` mapping.

## [2.3.0] - 2026-11-27

### Added
- **Multi-Language Settings UI (`English` Default + 5 Languages):** Added `Localization.swift` and `windows/i18n.js` supporting live switching across **English** (default), **Bahasa Indonesia**, **日本語**, **한국어**, **简体中文**, and **Español** directly from both the macOS Studio / Menu Bar and Windows System Tray (`settings.json` persistence).
- **Crowded Vocal & Backing Vocal Choreography:** Added selectable `VocalSyncMode` presets (`Auto Balanced`, `Stable (Crowded Vocals / Chorus)`, `Aggressive`, `Manual`), dense-chorus consensus protection, backing-vocal clarity noise floor, `< 0.14s` duet merge guard so fast rap/chorus lines never collapse into backing vocals, unison `0.0s` backing lock, and compact dual-layer bounce dampening.
- **Sub-Second Cadence Calibration & Fine Sync Controls:** Added track-wide median singing cadence (`trackSecPerUnit`) so short lines before long breaks keep natural timing, independent **Backing Vocal Offset** (`-1.50s..+1.50s`), wider **Word Sweep Speed** (`0.40x–2.20x`) and **Shift Timing** (`-2.50s..+2.50s`) sliders, quick `±0.05s / ±0.25s` nudge buttons, speed presets (`0.75x / 1.00x / 1.25x`), and one-click **Recalibrate Auto-Sync**.
- **More Lyric & Metadata Sources:** Added **Kuwo Music** (`search.kuwo.cn` + `m.kuwo.cn`) synced LRC racing and concurrent **iTunes + Deezer Search** metadata normalization for Romanized Japanese/Korean tracks on both macOS and Windows.
- **Automated Release Packaging (`.github/workflows/release.yml`):** Added tagged release automation (`v*` + manual dispatch) publishing Windows `x64`/`ARM64` `.exe` installers/portables alongside the Universal macOS `.zip`.

### Fixed
- **Windows Electron Packaging (`windows/package.json`):** Added missing `i18n.js` to `build.files` (preventing `Cannot find module './i18n'` at runtime), aligned all version metadata to `2.3.0` (`package.json`, `manifest.json`, `VERSION`, `Info.plist`), configured `portable` builds for both `x64` and `arm64` with `${arch}` `artifactName` templates to prevent overwrites, and committed `windows/package-lock.json`.
- **GitHub Actions CI (`.github/workflows/ci-build.yml`):** Upgraded retired `macos-14` runner to `macos-15`, switched `windows-package` to `npm run dist:win` (`x64` + `arm64`), added structural `app.asar` header verification (`i18n.js` present, `tests/` excluded) across both architectures, and verified all expected `.exe` outputs before upload.

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

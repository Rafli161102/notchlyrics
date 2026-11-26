# NotchLyrics

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS 14.2+ | Windows 10/11](https://img.shields.io/badge/Platform-macOS%2014.2%2B%20%7C%20Windows%2010%2F11-black)

Real-time synchronized karaoke lyrics for the **macOS Touch Bar**, **macOS Top-Center Notch Overlay**, **Windows 10/11 Desktop Notch Overlay**, and **Chromium/Edge/Brave Browser Extension**.

Designed around **Golden Ratio ($\varphi \approx 1.618$) proportions**, **pure OLED `#000000` black surfaces**, **album-matched adaptive text colors**, **multi-line zero-truncation Notch rendering**, and **real-time vocal intonation & BPM audio auto-sync**.

---

## Key Features

### Cross-Platform Outputs
- **macOS Touch Bar (`macOS 14.2+`)**: Native `NSTouchBar` system tray item & live interactive karaoke strip (`DFRFoundation`), zero Xcode project required.
- **macOS Top-Center Notch (`macOS 14.2+`)**: Transparent always-on-top `NSPanel` visible across all Spaces and full-screen apps with zero focus stealing. Automatically adapts to **Attached Bezel**, **Floating Dynamic Island**, or **Wide Edge Dock Strip**, and automatically selects Notch mode on Apple Silicon / notched MacBooks without a Touch Bar.
- **Windows 10 / 11 Desktop App (`windows/`)**: Frameless, transparent always-on-top Electron overlay powered by built-in Windows WinRT `GlobalSystemMediaTransportControls` (`win_smtc.ps1`), reading Spotify, YouTube Music, Chrome, Edge, Brave, Firefox, Apple Music, and VLC system-wide without extra native drivers.
- **Zero-Build Browser Extension (`windows/browser-extension/`)**: Manifest V3 extension for Chrome, Edge, and Brave adding an OLED Golden Ratio lyrics notch on YouTube, YouTube Music, Spotify Web, SoundCloud, and Apple Music.

### Real-Time Lyrics & Vocal Synchronization
- **Fast Progressive Multi-Source Search**: Queries **LRCLIB** (`/api/get`, `/api/search`, full-text `?q=`), **NetEase Cloud Music** (`YRC` word-level & `LRC`), **Kugou Music** (`LRC`), and **Kuwo Music** (`LRC`) concurrently with immediate early display, stale request cancellation, **iTunes + Deezer Search API** metadata normalization for Romanized tracks, and **Lyrics.ovh** plain-text fallback.
- **Strict Track Accuracy, Script Consistency & Offline Cache**: Scores duration match, cross-script romanized token similarity, line coverage, and lyric-language consistency (preventing English translations or `(inst)`/cover versions from overriding native Japanese/Korean/Indonesian tracks). Persists fetched lyrics, detected BPM, and lead/backing calibration offsets in local cache (`~/Library/Application Support/TouchBarLyrics/LyricsCache` on macOS, `%APPDATA%\NotchLyrics\LyricsCache` on Windows).
- **Real-Time CoreAudio DSP Auto-Sync (macOS)**: Taps system audio (`300–3400 Hz` mid/side vocal separation) to align lead & backing vocal timing within milliseconds, detect track BPM continuously, track live vocal pitch brightness (`vocalIntonation`) and syllable attack bursts (`vocalOnset`), and fall back seamlessly to timestamp playback if system audio permission is declined.
- **Intonation-Reactive Karaoke Choreography**: Smooth 60 FPS word-by-word & syllable sweep with anticipatory pre-glow, pitch/onset-scaled vertical syllable lift, dual-layer outgoing cross-dissolve line transitions, independent call-and-response backing vocals, and a real-time glowing progress bead.

### Multi-Language Script & Romaji Support
- **Japanese**: Context-aware `CFStringTokenizer` phrase transcription handling grammar particles (`は` -> `wa`, `へ` -> `e`, `を` -> `o`), cross-token sokuon gemination (`待っていた` -> `matte ita`, `知った` -> `shitta`), long vowel macrons/chōonpu (`コーヒー` -> `koohii`), and YRC word fragment alignment.
- **Korean**: Algorithmic Unicode Hangul Revised Romanization supporting consonant liaison and lateral assimilation (`사랑해요 괜찮아 빨리` -> `saranghaeyo gwaenchana ppalli`).
- **Mandarin Chinese, Cyrillic (Russian), Arabic/Hebrew RTL & Indic/Thai**: Clean Cyrillic transliteration (`Привет мир любовь` -> `Privet mir lyubov`), automatic `.rightToLeft` direction for Arabic/Hebrew, and word-cluster grouping preserving cursive ligatures and stacked vowel marks in Arabic, Hindi, and Thai.

### Visual Polish & Customization
- **Pure OLED Black + Album Text Colors**: Dark themes keep `#000000` pure black backgrounds untouched while tinting lyric text, active highlights, backing vocals, and progress accents from album artwork with enforced WCAG AA (`>= 4.5:1`) contrast.
- **Zero-Truncation Multiline Notch**: Automatically wraps lyrics cleanly across lines and steps font sizing smoothly inside Notch bounds without `...` ellipsis clipping.
- **Hover-Expanded Notch Card**: Smoothly expands (`336x48` -> `544x110`) on hover/focus with artwork thumbnail, track title, artist/album metadata, live **`MM:SS / MM:SS`** playback timer, and native Previous / Play-Pause / Next controls.
- **Studio Theme Editor & Multi-Language Settings (macOS + Windows)**: 4 built-in themes + unlimited custom JSON themes with live UI switching across **English** (default), **Bahasa Indonesia**, **日本語**, **한국어**, **简体中文**, and **Español**, plus controls for layout, alignment, fonts, word speed scale (`0.40x–2.20x`), main timing offset (`-2.50s..+2.50s`), independent backing vocal offset (`-1.50s..+1.50s`), vocal auto-sync mode (`Balanced / Stable Crowded / Aggressive / Manual`), fine `±0.05s` nudges, line transitions, animation curves, color sync mode, and `prefers-reduced-motion` support.

---

## Repository Structure

```text
.
├── AppDelegate.swift                # macOS menu bar app, Now Playing bridge & render loop
├── DisplayMode.swift                # Touch Bar / Notch / Both / Hidden routing
├── Localization.swift               # Multi-language UI (English default + 5 languages)
├── LyricsParserAndFetcher.swift     # LRCLIB + NetEase + Kugou + Kuwo + iTunes/Deezer + cache
├── NotchGeometry.swift              # Golden Ratio (phi) bezel/floating/strip notch geometry
├── NotchLyricsWindowController.swift# Hover-expanding NSPanel notch overlay + timer UI
├── TextRomanizerAndArtwork.swift    # Multi-script romanizer & album color palette extractor
├── ThemeEditorWindow.swift          # Live 3-tab Studio Theme Customizer window
├── ThemeModels.swift                # Codable theme definitions & WCAG contrast helpers
├── TouchBarLyricsView.swift         # Dual-layer transitions, multiline wrap & 60fps renderer
├── VocalAutoSyncEngine.swift        # CoreAudio Process Tap, BPM & intonation DSP engine
├── build.sh                         # macOS reproducible compiler (--install, --universal, --package)
├── notarize.sh                      # Apple Developer ID notarization & stapling helper
├── Info.plist                       # App metadata & privacy usage descriptions
├── .github/workflows/               # Cross-platform CI build & tagged release automation
├── tests/                           # Standalone macOS Swift test suites
├── windows/                         # Windows 10/11 Electron app, WinRT SMTC & MV3 extension
└── web/                             # Reusable standalone browser notch UI
```

---

## Prebuilt Releases (macOS & Windows)

Ready-to-use binaries are published on the [**GitHub Releases**](https://github.com/Rafli161102/notchlyrics/releases) page (built automatically by [.github/workflows/release.yml](.github/workflows/release.yml) on every `v*` tag):

- **macOS (`14.2+` Universal `arm64` + `x86_64`):** `TouchBarLyrics-2.3.0-macOS.zip`
- **Windows (`10 / 11` Installer `x64` + `ARM64`):** `NotchLyrics Setup 2.3.0.exe`
- **Windows Portable:** `NotchLyrics-2.3.0-x64-portable.exe` (`x64`), `NotchLyrics-2.3.0-arm64-portable.exe` (`ARM64`), and `NotchLyrics-2.3.0-portable.exe` (dual-arch)

---

## Installation & Usage

### macOS (`14.2+`, Apple Silicon & Intel)

#### Zero-Dependency Portability
`TouchBarLyrics.app` runs out of the box for any macOS user:
1. If `MediaRemoteAdapter.framework` + `mediaremote-adapter.pl` is bundled inside `Contents/Resources/` (automatic when built with `./build.sh` on a machine that has it, or installed under `~/Library/Application Support/TouchBarLyrics/MediaRemoteAdapter/` / `/Applications/Atoll.app`), TouchBarLyrics streams system-wide Now Playing at ~10 ms debounce.
2. If no external adapter is installed on the target Mac, TouchBarLyrics **automatically falls back to built-in macOS Apple Events**, reading playback directly from **Apple Music**, **Spotify**, and **Safari** active tabs with zero external apps required.

#### Build & Install from Source
```sh
git clone https://github.com/Rafli161102/notchlyrics.git
cd notchlyrics

# Run unit tests (Notch Geometry + Core Engine / Romanizer / OLED Contrast)
./tests/run.sh

# Build & install to ~/Applications/TouchBarLyrics.app
./build.sh --install
```

Build flags:
- `./build.sh` — builds `.build/TouchBarLyrics.app` for host architecture.
- `./build.sh --install` — installs & re-signs into `~/Applications/TouchBarLyrics.app`.
- `./build.sh --universal` — builds a fat Universal Mach-O binary (`arm64` + `x86_64`).
- `./build.sh --package` — packages `.build/TouchBarLyrics-<version>-macOS.zip` for distribution.

Open `TouchBarLyrics.app`, grant **System Audio Recording** when prompted (optional, enables live CoreAudio vocal/intonation sync; declines gracefully fallback to timestamp sync), and play music in Safari, Music, or Spotify.

---

### Windows (`10 / 11`)

#### Option 1: Always-On-Top Windows Desktop App (Spotify, Chrome, Edge, Apple Music, etc.)
Requires [Node.js](https://nodejs.org/) 18+ (built-in Windows PowerShell WinRT handles SMTC media reading with no C++ compiler needed):

```powershell
cd windows
npm install
npm test
npm start
```

Package Windows installers & portable executables (`x64` and `ARM64`) inside `windows/dist/`:
```powershell
npm run dist:win
```
This outputs:
- `NotchLyrics Setup 2.3.0.exe` (dual-arch NSIS installer for `x64` + `ARM64`)
- `NotchLyrics-2.3.0-x64-portable.exe` (`x64` portable)
- `NotchLyrics-2.3.0-arm64-portable.exe` (`ARM64` portable)
- `NotchLyrics-2.3.0-portable.exe` (dual-arch portable)

#### Option 2: Zero-Build Chrome / Edge / Brave Extension (`windows/browser-extension/`)
1. Open `chrome://extensions` (or `edge://extensions` / `brave://extensions`).
2. Enable **Developer mode**.
3. Click **Load unpacked** and select the `windows/browser-extension` folder.
4. Open YouTube, YouTube Music, Spotify Web, SoundCloud, or Apple Music to see the top-center OLED Notch overlay immediately.

See [windows/README.md](windows/README.md) and [web/README.md](web/README.md) for architecture and JS widget contract details.

---

## Signing & Notarization (macOS Public Releases)

Default local builds use ad-hoc signing (`CODESIGN_IDENTITY=-`). For public macOS Gatekeeper distribution:

```sh
xcrun notarytool store-credentials TouchBarLyricsNotary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"

CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh --universal --package
NOTARY_PROFILE=TouchBarLyricsNotary ./notarize.sh
```

---

## Testing & Verification

- **macOS Tests**: `./tests/run.sh` runs standalone Swift suites in [tests/NotchTests.swift](tests/NotchTests.swift) (`NotchGeometry`, `DisplayMode`) and [tests/CoreEngineTests.swift](tests/CoreEngineTests.swift) (scoring, caching, YRC/LRC sync, Japanese/Korean/Chinese/Cyrillic/Arabic script handling, OLED background lock, WCAG contrast, multiline auto-fit, intonation lift).
- **Windows Engine Tests**: `cd windows && npm test` runs [windows/tests/lyrics-engine.test.js](windows/tests/lyrics-engine.test.js).

---

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for full details.

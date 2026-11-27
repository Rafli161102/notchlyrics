# NotchLyrics for Windows (`10 / 11`) & Linux (`X11 / Wayland`)

Cross-platform Windows & Linux desktop companion and Chromium browser extension bringing TouchBarLyrics' Golden Ratio OLED Notch synchronized karaoke experience to PC desktops.

## Desktop App (`Always-On-Top` System-Wide Overlay)

Uses **Electron** for a transparent always-on-top top-center overlay paired with built-in **PowerShell WinRT `GlobalSystemMediaTransportControlsSessionManager`** (`win_smtc.ps1`) on Windows and zero-dependency **MPRIS2 (`playerctl --follow` + `gdbus`/`dbus-send` fallback)** (`mpris_bridge.js`) on Linux.

Supports Spotify, Chrome, Edge, Brave, Firefox, YouTube Music PWA, Apple Music Windows, Tidal, Rhythmbox, and VLC.

### Run Locally
```powershell
cd windows
npm install
npm test
npm start
```

### Build Windows Installer & Portable `.exe` (`x64` + `ARM64`)
```powershell
cd windows
npm install
npm run dist:win
```
Produces dual-arch NSIS installer (`NotchLyrics Setup 2.4.0.exe`), architecture-specific portables (`NotchLyrics-2.4.0-x64-portable.exe`, `NotchLyrics-2.4.0-arm64-portable.exe`), and dual-arch portable inside `windows/dist/`.

### Build Linux `.AppImage` & `.deb` (`x64`)
```sh
cd windows
npm install
npm run dist:linux
```
For optimal event-driven Linux playback tracking, install `playerctl` (`sudo apt install playerctl` / `sudo pacman -S playerctl` / `sudo dnf install playerctl`).

Also supports live System Tray language switching (`English` default, `Bahasa Indonesia`, `日本語`, `한국어`, `简体中文`, and `Español`), Refetch Lyrics (Clear Cache), and Manual Lyrics Offset (`±0.1s` / `±0.5s`).

---

## Browser Extension (`Chrome / Edge / Brave`)

For a lightweight zero-Node setup directly inside your browser:

1. Navigate to `chrome://extensions` or `edge://extensions`.
2. Toggle **Developer mode** ON.
3. Click **Load unpacked** and choose `windows/browser-extension`.
4. Play tracks on YouTube, YouTube Music, Spotify Web, SoundCloud, or Apple Music Web.

# NotchLyrics for Windows (`10 / 11`)

Cross-platform Windows desktop companion and Chromium browser extension bringing TouchBarLyrics' Golden Ratio OLED Notch synchronized karaoke experience to Windows PCs.

## Desktop App (`Always-On-Top` System-Wide Overlay)

Uses **Electron** for a transparent always-on-top top-center overlay paired with built-in **PowerShell WinRT `GlobalSystemMediaTransportControlsSessionManager`** (`win_smtc.ps1`) — no Visual Studio or C++ native build tools required.

Supports Spotify, Chrome, Edge, Brave, Firefox, YouTube Music PWA, Apple Music Windows, Tidal, and VLC.

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
Produces dual-arch NSIS installer (`NotchLyrics Setup 2.3.0.exe`), architecture-specific portables (`NotchLyrics-2.3.0-x64-portable.exe`, `NotchLyrics-2.3.0-arm64-portable.exe`), and dual-arch portable inside `windows/dist/`.

Also supports live System Tray language switching (`English` default, `Bahasa Indonesia`, `日本語`, `한국어`, `简体中文`, and `Español`).

---

## Browser Extension (`Chrome / Edge / Brave`)

For a lightweight zero-Node setup directly inside your browser:

1. Navigate to `chrome://extensions` or `edge://extensions`.
2. Toggle **Developer mode** ON.
3. Click **Load unpacked** and choose `windows/browser-extension`.
4. Play tracks on YouTube, YouTube Music, Spotify Web, SoundCloud, or Apple Music Web.

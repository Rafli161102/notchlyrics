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

### Build Windows Installer (`.exe`)
```powershell
cd windows
npm run dist:win
```
Produces NSIS installer and portable executable inside `windows/dist/`.

---

## Browser Extension (`Chrome / Edge / Brave`)

For a lightweight zero-Node setup directly inside your browser:

1. Navigate to `chrome://extensions` or `edge://extensions`.
2. Toggle **Developer mode** ON.
3. Click **Load unpacked** and choose `windows/browser-extension`.
4. Play tracks on YouTube, YouTube Music, Spotify Web, SoundCloud, or Apple Music Web.

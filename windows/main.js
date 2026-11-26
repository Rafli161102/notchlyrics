'use strict';

const { app, BrowserWindow, Tray, Menu, ipcMain, screen, nativeImage } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const {
  cleanTitle,
  cleanArtist,
  romanizeText,
  fetchLyrics,
  computeLineProgress
} = require('./lyrics-engine');
const { LANGUAGES, t } = require('./i18n');

const PHI = 1.6180339887;
const STYLE_DIMENSIONS = {
  attachedBezel: {
    collapsed: { width: 336, height: 48, top: 0 },
    expanded: { width: Math.round(336 * PHI), height: 110, top: 0 }
  },
  floatingIsland: {
    collapsed: { width: 318, height: 48, top: 8 },
    expanded: { width: Math.round(318 * PHI), height: 108, top: 8 }
  },
  edgeDockStrip: {
    collapsed: { width: 488, height: 46, top: 0 },
    expanded: { width: 610, height: 104, top: 0 }
  }
};

let mainWindow = null;
let tray = null;
let smtcProc = null;
let currentStyle = 'attachedBezel';
let isExpanded = false;
let romanizeEnabled = true;
let appLanguage = 'en';

function settingsPath() {
  return path.join(app.getPath('userData'), 'settings.json');
}

function loadSettings() {
  try {
    const raw = JSON.parse(fs.readFileSync(settingsPath(), 'utf8'));
    if (raw.style && STYLE_DIMENSIONS[raw.style]) currentStyle = raw.style;
    if (typeof raw.romanize === 'boolean') romanizeEnabled = raw.romanize;
    if (raw.language && LANGUAGES.some((l) => l.code === raw.language)) appLanguage = raw.language;
  } catch (_) {}
}

function saveSettings() {
  try {
    fs.writeFileSync(settingsPath(), JSON.stringify({
      style: currentStyle,
      romanize: romanizeEnabled,
      language: appLanguage
    }, null, 2), 'utf8');
  } catch (_) {}
}

let playback = {
  title: '',
  artist: '',
  album: '',
  duration: 0,
  baseElapsed: 0,
  updatedAtMs: Date.now(),
  playing: false,
  artworkUrl: ''
};
let currentTrackKey = '';
let activeLyrics = [];
let lyricsStatus = t(appLanguage, 'idleStatus');

function computeBounds(expanded) {
  const disp = screen.getPrimaryDisplay();
  const work = disp.bounds;
  const spec = (STYLE_DIMENSIONS[currentStyle] || STYLE_DIMENSIONS.attachedBezel)[expanded ? 'expanded' : 'collapsed'];
  const w = Math.min(work.width - 24, spec.width);
  return {
    x: Math.round(work.x + (work.width - w) / 2),
    y: Math.round(work.y + spec.top),
    width: w,
    height: spec.height
  };
}

function createWindow() {
  const bounds = computeBounds(false);
  mainWindow = new BrowserWindow({
    ...bounds,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    resizable: false,
    hasShadow: false,
    focusable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.setAlwaysOnTop(true, 'screen-saver');
  mainWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

function updateWindowFrame(expanded) {
  isExpanded = Boolean(expanded);
  if (!mainWindow || mainWindow.isDestroyed()) return;
  mainWindow.setBounds(computeBounds(isExpanded), false);
}

function startWindowsSMTC() {
  if (process.platform !== 'win32') return;
  const psScript = path.join(__dirname, 'win_smtc.ps1');
  if (!fs.existsSync(psScript)) return;

  smtcProc = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', psScript], {
    windowsHide: true
  });

  let buffer = '';
  smtcProc.stdout.on('data', (chunk) => {
    buffer += chunk.toString('utf8');
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || '';
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        handleMediaState(JSON.parse(line));
      } catch (_) {}
    }
  });
}

function sendMediaCommand(command) {
  if (process.platform !== 'win32') return;
  const map = { togglePlayPause: 'toggle', next: 'next', previous: 'previous' };
  const arg = map[command];
  if (!arg) return;
  const psScript = path.join(__dirname, 'win_smtc.ps1');
  spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', psScript, arg], {
    windowsHide: true,
    stdio: 'ignore'
  });
}

async function handleMediaState(next) {
  const title = String(next.title || '');
  const artist = String(next.artist || '');
  const duration = Number(next.duration || 0);
  const trackKey = `${title.toLowerCase()}|${artist.toLowerCase()}|${Math.round(duration)}`;

  playback = {
    title,
    artist,
    album: String(next.album || ''),
    duration,
    baseElapsed: Number(next.elapsed || 0),
    updatedAtMs: Date.now(),
    playing: Boolean(next.playing),
    artworkUrl: String(next.artworkUrl || '')
  };

  if (title && trackKey !== currentTrackKey) {
    currentTrackKey = trackKey;
    activeLyrics = [];
    lyricsStatus = `${t(appLanguage, 'searchingLyrics')} ${cleanTitle(title)}...`;
    const cacheDir = path.join(app.getPath('userData'), 'LyricsCache');
    const res = await fetchLyrics({ title, artist, album: playback.album, duration, cacheDir });
    if (currentTrackKey === trackKey) {
      activeLyrics = res.lines || [];
      if (!activeLyrics.length) {
        const ct = cleanTitle(title);
        const ca = cleanArtist(artist);
        lyricsStatus = ca ? `${ct} - ${ca}` : ct;
      }
    }
  } else if (!title) {
    currentTrackKey = '';
    activeLyrics = [];
    lyricsStatus = t(appLanguage, 'idleStatus');
  }
}

function currentElapsed() {
  if (!playback.playing) return Math.max(0, playback.baseElapsed);
  const dt = Math.max(0, (Date.now() - playback.updatedAtMs) / 1000);
  const raw = playback.baseElapsed + dt;
  return playback.duration > 0 ? Math.min(playback.duration, raw) : raw;
}

function tickFrame() {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  const rawElapsed = currentElapsed();
  const elapsed = rawElapsed + (playback.playing ? 0.11 : 0);

  let mainText = lyricsStatus;
  let backingText = '';
  let lineProgress = 1;

  if (activeLyrics.length) {
    let idx = -1;
    for (let i = 0; i < activeLyrics.length; i++) {
      if (activeLyrics[i].time <= elapsed) idx = i;
      else break;
    }
    if (idx >= 0) {
      const cur = activeLyrics[idx];
      const nextTime = idx + 1 < activeLyrics.length
        ? activeLyrics[idx + 1].time
        : (playback.duration > cur.time ? playback.duration : cur.time + 5);
      mainText = romanizeEnabled ? romanizeText(cur.mainText) : cur.mainText;
      backingText = cur.backingText ? (romanizeEnabled ? romanizeText(cur.backingText) : cur.backingText) : '';
      lineProgress = computeLineProgress(cur, elapsed, nextTime);
    } else {
      mainText = cleanTitle(playback.title);
      lineProgress = 0;
    }
  }

  const songProgress = playback.duration > 0 ? Math.min(1, Math.max(0, rawElapsed / playback.duration)) : 0;
  mainWindow.webContents.send('notch-state', {
    style: currentStyle,
    mainText,
    backingText,
    trackTitle: cleanTitle(playback.title),
    artist: cleanArtist(playback.artist),
    album: playback.album,
    artworkUrl: playback.artworkUrl,
    isPlaying: playback.playing,
    songProgress,
    lineProgress,
    elapsedTime: rawElapsed,
    duration: playback.duration
  });
}

function buildTray() {
  tray = new Tray(nativeImage.createEmpty());
  tray.setToolTip('NotchLyrics');
  const rebuildMenu = () => {
    const langItems = LANGUAGES.map((l) => ({
      label: l.name,
      type: 'radio',
      checked: appLanguage === l.code,
      click: () => {
        appLanguage = l.code;
        if (!playback.title) lyricsStatus = t(appLanguage, 'idleStatus');
        saveSettings();
        rebuildMenu();
      }
    }));

    const menu = Menu.buildFromTemplate([
      { label: t(appLanguage, 'appHeader'), enabled: false },
      { type: 'separator' },
      {
        label: t(appLanguage, 'styleAttached'),
        type: 'radio',
        checked: currentStyle === 'attachedBezel',
        click: () => { currentStyle = 'attachedBezel'; saveSettings(); updateWindowFrame(isExpanded); rebuildMenu(); }
      },
      {
        label: t(appLanguage, 'styleFloating'),
        type: 'radio',
        checked: currentStyle === 'floatingIsland',
        click: () => { currentStyle = 'floatingIsland'; saveSettings(); updateWindowFrame(isExpanded); rebuildMenu(); }
      },
      {
        label: t(appLanguage, 'styleStrip'),
        type: 'radio',
        checked: currentStyle === 'edgeDockStrip',
        click: () => { currentStyle = 'edgeDockStrip'; saveSettings(); updateWindowFrame(isExpanded); rebuildMenu(); }
      },
      { type: 'separator' },
      {
        label: t(appLanguage, 'romanizeLyrics'),
        type: 'checkbox',
        checked: romanizeEnabled,
        click: (item) => { romanizeEnabled = item.checked; saveSettings(); rebuildMenu(); }
      },
      {
        label: `${t(appLanguage, 'languageMenu')}: ${LANGUAGES.find((l) => l.code === appLanguage)?.name || 'English'}`,
        submenu: langItems
      },
      { type: 'separator' },
      { label: t(appLanguage, 'quitApp'), click: () => app.quit() }
    ]);
    tray.setContextMenu(menu);
  };
  rebuildMenu();
}

ipcMain.on('notch-command', (_event, cmd) => sendMediaCommand(cmd));
ipcMain.on('notch-hover', (_event, expanded) => updateWindowFrame(expanded));

app.whenReady().then(() => {
  loadSettings();
  if (!playback.title) lyricsStatus = t(appLanguage, 'idleStatus');
  createWindow();
  buildTray();
  startWindowsSMTC();
  setInterval(tickFrame, 16);
});

app.on('before-quit', () => {
  if (smtcProc && !smtcProc.killed) smtcProc.kill();
});

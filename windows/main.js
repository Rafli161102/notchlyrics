'use strict';

const { app, BrowserWindow, Tray, Menu, ipcMain, screen, nativeImage, dialog, shell } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const {
  cleanTitle,
  cleanArtist,
  romanizeText,
  clearTrackCache,
  fetchLyrics,
  computeFrameState
} = require('./lyrics-engine');
const { startMprisWatcher, sendMprisCommand } = require('./mpris_bridge');
const { LANGUAGES, t } = require('./i18n');

if (process.platform === 'linux') {
  app.commandLine.appendSwitch('enable-transparent-visuals');
}

const isLinux = process.platform === 'linux';

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
let rebuildTrayMenu = () => {};
let smtcProc = null;
let mprisWatcher = null;
let currentStyle = 'attachedBezel';
let isExpanded = false;
let romanizeEnabled = true;
let appLanguage = 'en';
let manualOffsetSeconds = 0;

function idleLabel() {
  return t(appLanguage, isLinux ? 'idleStatusLinux' : 'idleStatus');
}

function headerLabel() {
  return t(appLanguage, isLinux ? 'appHeaderLinux' : 'appHeader');
}

function clampManualOffset(val) {
  const num = Number(val) || 0;
  return Math.max(-5.0, Math.min(5.0, Math.round(num * 10) / 10));
}

function formatOffsetTag(sec) {
  const rounded = clampManualOffset(sec);
  const sign = rounded > 0 ? '+' : '';
  return `${sign}${rounded.toFixed(1)}s`;
}

function settingsPath() {
  return path.join(app.getPath('userData'), 'settings.json');
}

function loadSettings() {
  try {
    const raw = JSON.parse(fs.readFileSync(settingsPath(), 'utf8'));
    if (raw.style && STYLE_DIMENSIONS[raw.style]) currentStyle = raw.style;
    if (typeof raw.romanize === 'boolean') romanizeEnabled = raw.romanize;
    if (raw.language && LANGUAGES.some((l) => l.code === raw.language)) appLanguage = raw.language;
    if (typeof raw.manualOffsetSeconds === 'number') {
      manualOffsetSeconds = clampManualOffset(raw.manualOffsetSeconds);
    }
  } catch (_) {}
}

function saveSettings() {
  try {
    const file = settingsPath();
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify({
      style: currentStyle,
      romanize: romanizeEnabled,
      language: appLanguage,
      manualOffsetSeconds
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
let preparedLines = [];
let lyricsStatus = idleLabel();

function rebuildPreparedLines() {
  preparedLines = (activeLyrics || []).map((line) => ({
    time: line.time,
    endTime: line.endTime,
    mainText: romanizeEnabled ? romanizeText(line.mainText) : line.mainText,
    backingText: line.backingText ? (romanizeEnabled ? romanizeText(line.backingText) : line.backingText) : '',
    words: Array.isArray(line.words) ? line.words : []
  }));
}

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
    icon: path.join(__dirname, 'assets', 'icon.png'),
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
  try {
    mainWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  } catch (_) {}
  mainWindow.webContents.on('did-finish-load', () => emitPlaybackSnapshot());
  mainWindow.on('show', () => emitPlaybackSnapshot());
  mainWindow.on('hide', () => emitPlaybackSnapshot());
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

function startMediaWatcher() {
  stopMediaWatcher();
  if (process.platform === 'win32') {
    startWindowsSMTC();
  } else if (process.platform === 'linux') {
    mprisWatcher = startMprisWatcher({
      onState: (state) => {
        handleMediaState(state).catch(() => {});
      }
    });
  }
}

function stopMediaWatcher() {
  if (smtcProc && !smtcProc.killed) {
    smtcProc.kill();
  }
  smtcProc = null;
  if (mprisWatcher && typeof mprisWatcher.stop === 'function') {
    mprisWatcher.stop();
  }
  mprisWatcher = null;
}

function sendMediaCommand(command) {
  if (process.platform === 'linux') {
    sendMprisCommand(command).catch(() => {});
    return;
  }
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

function currentElapsed() {
  if (!playback.playing) return Math.max(0, playback.baseElapsed);
  const dt = Math.max(0, (Date.now() - playback.updatedAtMs) / 1000);
  const raw = playback.baseElapsed + dt;
  return playback.duration > 0 ? Math.min(playback.duration, raw) : raw;
}

function emitPlaybackSnapshot() {
  if (!mainWindow || mainWindow.isDestroyed() || mainWindow.webContents.isLoading()) return;
  const rawElapsed = currentElapsed();
  const baseSnapshot = {
    style: currentStyle,
    trackTitle: cleanTitle(playback.title),
    artist: cleanArtist(playback.artist),
    album: playback.album,
    artworkUrl: playback.artworkUrl,
    isPlaying: playback.playing,
    baseElapsed: rawElapsed,
    duration: playback.duration,
    manualOffsetSeconds,
    wordSpeedScale: 1.0,
    idleText: lyricsStatus,
    lines: preparedLines,
    windowVisible: mainWindow.isVisible()
  };
  const frame = computeFrameState(baseSnapshot, rawElapsed, -1);
  mainWindow.webContents.send('notch-state', {
    ...baseSnapshot,
    mainText: frame.mainText,
    backingText: frame.backingText,
    songProgress: frame.songProgress,
    lineProgress: frame.lineProgress,
    elapsedTime: frame.elapsedTime
  });
}

async function loadTrackLyrics({ title, artist, album, duration, trackKey, forceRefresh = false }) {
  const cacheDir = path.join(app.getPath('userData'), 'LyricsCache');
  lyricsStatus = `${t(appLanguage, 'searchingLyrics')} ${cleanTitle(title)}...`;
  emitPlaybackSnapshot();

  const res = await fetchLyrics({ title, artist, album, duration, cacheDir, forceRefresh });
  if (currentTrackKey !== trackKey) return;

  activeLyrics = res.lines || [];
  rebuildPreparedLines();
  if (!activeLyrics.length) {
    const ct = cleanTitle(title);
    const ca = cleanArtist(artist);
    lyricsStatus = ca ? `${ct} - ${ca}` : ct;
  }
  emitPlaybackSnapshot();
}

function refetchCurrentLyrics() {
  if (!playback.title) return;
  const cacheDir = path.join(app.getPath('userData'), 'LyricsCache');
  clearTrackCache({
    title: playback.title,
    artist: playback.artist,
    duration: playback.duration,
    cacheDir
  });
  activeLyrics = [];
  preparedLines = [];
  loadTrackLyrics({
    title: playback.title,
    artist: playback.artist,
    album: playback.album,
    duration: playback.duration,
    trackKey: currentTrackKey,
    forceRefresh: true
  });
}

async function handleMediaState(next) {
  const title = String(next.title || '');
  const artist = String(next.artist || '');
  const album = String(next.album || '');
  const duration = Number(next.duration || 0);
  const nextElapsed = Number(next.elapsed || 0);
  const nextPlaying = Boolean(next.playing);
  const artworkUrl = String(next.artworkUrl || '');
  const trackKey = `${title.toLowerCase()}|${artist.toLowerCase()}|${Math.round(duration)}`;

  const predicted = currentElapsed();
  const trackChanged = Boolean(title) && trackKey !== currentTrackKey;
  const clearedTrack = !title && currentTrackKey !== '';
  const playStateChanged = nextPlaying !== playback.playing;
  const metaChanged = album !== playback.album || artworkUrl !== playback.artworkUrl || Math.abs(duration - playback.duration) > 0.5;
  const seeked = Math.abs(nextElapsed - predicted) > 0.45;

  // Avoid spurious 250ms SMTC polling IPC when paused/idle or nothing meaningful changed
  if (!trackChanged && !clearedTrack && !playStateChanged && !metaChanged && !seeked) {
    return;
  }

  playback = {
    title,
    artist,
    album,
    duration,
    baseElapsed: nextElapsed,
    updatedAtMs: Date.now(),
    playing: nextPlaying,
    artworkUrl
  };

  if (trackChanged) {
    currentTrackKey = trackKey;
    activeLyrics = [];
    preparedLines = [];
    rebuildTrayMenu();
    await loadTrackLyrics({ title, artist, album, duration, trackKey, forceRefresh: false });
    return;
  }

  if (!title) {
    currentTrackKey = '';
    activeLyrics = [];
    preparedLines = [];
    lyricsStatus = idleLabel();
    rebuildTrayMenu();
  }

  emitPlaybackSnapshot();
}

function adjustManualOffset(delta) {
  manualOffsetSeconds = clampManualOffset(manualOffsetSeconds + delta);
  saveSettings();
  rebuildTrayMenu();
  emitPlaybackSnapshot();
}

function resetManualOffset() {
  manualOffsetSeconds = 0;
  saveSettings();
  rebuildTrayMenu();
  emitPlaybackSnapshot();
}

function buildTray() {
  const trayPath = path.join(__dirname, 'assets', 'tray.png');
  const trayIcon = fs.existsSync(trayPath) ? nativeImage.createFromPath(trayPath) : nativeImage.createEmpty();
  tray = new Tray(trayIcon);
  tray.setToolTip('NotchLyrics');
  rebuildTrayMenu = () => {
    const langItems = LANGUAGES.map((l) => ({
      label: l.name,
      type: 'radio',
      checked: appLanguage === l.code,
      click: () => {
        appLanguage = l.code;
        if (!playback.title) lyricsStatus = idleLabel();
        saveSettings();
        rebuildTrayMenu();
        emitPlaybackSnapshot();
      }
    }));

    const offsetItems = [
      { label: t(appLanguage, 'offsetAhead50'), click: () => adjustManualOffset(0.5) },
      { label: t(appLanguage, 'offsetAhead10'), click: () => adjustManualOffset(0.1) },
      { label: t(appLanguage, 'offsetBack10'), click: () => adjustManualOffset(-0.1) },
      { label: t(appLanguage, 'offsetBack50'), click: () => adjustManualOffset(-0.5) },
      { type: 'separator' },
      { label: t(appLanguage, 'offsetReset'), click: () => resetManualOffset() }
    ];

    const menu = Menu.buildFromTemplate([
      { label: headerLabel(), enabled: false },
      { type: 'separator' },
      {
        label: t(appLanguage, 'styleAttached'),
        type: 'radio',
        checked: currentStyle === 'attachedBezel',
        click: () => { currentStyle = 'attachedBezel'; saveSettings(); updateWindowFrame(isExpanded); rebuildTrayMenu(); emitPlaybackSnapshot(); }
      },
      {
        label: t(appLanguage, 'styleFloating'),
        type: 'radio',
        checked: currentStyle === 'floatingIsland',
        click: () => { currentStyle = 'floatingIsland'; saveSettings(); updateWindowFrame(isExpanded); rebuildTrayMenu(); emitPlaybackSnapshot(); }
      },
      {
        label: t(appLanguage, 'styleStrip'),
        type: 'radio',
        checked: currentStyle === 'edgeDockStrip',
        click: () => { currentStyle = 'edgeDockStrip'; saveSettings(); updateWindowFrame(isExpanded); rebuildTrayMenu(); emitPlaybackSnapshot(); }
      },
      { type: 'separator' },
      {
        label: t(appLanguage, 'refetchLyrics'),
        enabled: Boolean(playback.title),
        click: () => refetchCurrentLyrics()
      },
      {
        label: `${t(appLanguage, 'manualOffsetMenu')}: ${formatOffsetTag(manualOffsetSeconds)}`,
        submenu: offsetItems
      },
      {
        label: t(appLanguage, 'romanizeLyrics'),
        type: 'checkbox',
        checked: romanizeEnabled,
        click: (item) => {
          romanizeEnabled = item.checked;
          rebuildPreparedLines();
          saveSettings();
          rebuildTrayMenu();
          emitPlaybackSnapshot();
        }
      },
      {
        label: `${t(appLanguage, 'languageMenu')}: ${LANGUAGES.find((l) => l.code === appLanguage)?.name || 'English'}`,
        submenu: langItems
      },
      { type: 'separator' },
      { label: `${t(appLanguage, 'aboutMenu')} (v${app.getVersion()})`, click: () => showAboutDialog() },
      { label: t(appLanguage, 'quitApp'), click: () => app.quit() }
    ]);
    tray.setContextMenu(menu);
  };
  rebuildTrayMenu();
}

async function showAboutDialog() {
  const iconPath = path.join(__dirname, 'assets', 'icon.png');
  const platformName = isLinux ? 'Linux' : 'Windows';
  const detailKey = isLinux ? 'aboutDetailLinux' : 'aboutDetail';
  const res = await dialog.showMessageBox({
    type: 'info',
    icon: fs.existsSync(iconPath) ? nativeImage.createFromPath(iconPath) : undefined,
    title: 'NotchLyrics',
    message: `NotchLyrics for ${platformName} v${app.getVersion()}`,
    detail: t(appLanguage, detailKey),
    buttons: [t(appLanguage, 'aboutClose'), t(appLanguage, 'aboutOpenReleases')],
    defaultId: 0,
    cancelId: 0
  });
  if (res.response === 1) {
    shell.openExternal('https://github.com/Rafli161102/notchlyrics/releases');
  }
}

ipcMain.on('notch-command', (_event, cmd) => sendMediaCommand(cmd));
ipcMain.on('notch-hover', (_event, expanded) => updateWindowFrame(expanded));

app.whenReady().then(() => {
  loadSettings();
  if (!playback.title) lyricsStatus = idleLabel();
  createWindow();
  buildTray();
  startMediaWatcher();
});

app.on('before-quit', () => {
  stopMediaWatcher();
});

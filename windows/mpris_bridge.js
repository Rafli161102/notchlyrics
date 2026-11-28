'use strict';

const { spawn, execFile } = require('child_process');

const MPRIS_FIELD_SEP = '\x1f';
const PLAYERCTL_FORMAT = [
  '{{status}}',
  '{{xesam:title}}',
  '{{xesam:artist}}',
  '{{xesam:album}}',
  '{{mpris:length}}',
  '{{mpris:artUrl}}',
  '{{position}}',
  '{{playerName}}'
].join(MPRIS_FIELD_SEP);

const EMPTY_PLAYBACK_STATE = Object.freeze({
  playing: false,
  title: '',
  artist: '',
  album: '',
  duration: 0,
  elapsed: 0,
  appId: '',
  artworkUrl: ''
});

const PREFERRED_PLAYER_ORDER = [
  'spotify',
  'chromium',
  'chrome',
  'brave',
  'edge',
  'firefox',
  'vlc',
  'rhythmbox',
  'elisa',
  'amberol',
  'mpv'
];

function createEmptyPlaybackState() {
  return { ...EMPTY_PLAYBACK_STATE };
}

function microsecondsToSeconds(raw) {
  if (raw === null || raw === undefined || raw === '') return 0;
  const num = Number(String(raw).trim());
  if (!Number.isFinite(num) || num <= 0) return 0;
  return Math.round((num / 1_000_000) * 1000) / 1000;
}

function normalizeMprisStatus(raw) {
  const normalized = String(raw || '').trim().toLowerCase();
  if (normalized === 'playing') return { status: 'Playing', playing: true };
  if (normalized === 'paused') return { status: 'Paused', playing: false };
  return { status: 'Stopped', playing: false };
}

function parseQuotedArrayItems(rawText) {
  const items = [];
  const tokenRe = /'((?:\\.|[^'\\])*)'|"((?:\\.|[^"\\])*)"/g;
  let match;
  while ((match = tokenRe.exec(rawText)) !== null) {
    const val = (match[1] !== undefined ? match[1] : match[2])
      .replace(/\\'/g, "'")
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, '\\')
      .trim();
    if (val) items.push(val);
  }
  return items;
}

function normalizeMprisArtist(raw) {
  if (raw === null || raw === undefined) return '';
  if (Array.isArray(raw)) {
    return raw
      .map((item) => String(item ?? '').trim())
      .filter(Boolean)
      .join(', ');
  }
  const text = String(raw).trim();
  if (!text) return '';
  if (/^(?:@as\s*)?\[\s*\]$/.test(text)) return '';
  if (text.startsWith('[') && text.endsWith(']')) {
    const parsedItems = parseQuotedArrayItems(text);
    if (parsedItems.length > 0) return parsedItems.join(', ');
    const inner = text.slice(1, -1).trim();
    if (!inner) return '';
    return inner
      .split(',')
      .map((part) => part.trim())
      .filter(Boolean)
      .join(', ');
  }
  return text;
}

function buildPlaybackSnapshot(fields = {}) {
  const { status, playing } = normalizeMprisStatus(fields.status);
  const title = String(fields.title || '').trim();
  const artist = normalizeMprisArtist(fields.artist);
  const album = String(fields.album || '').trim();
  const duration = microsecondsToSeconds(fields.lengthUs);
  let elapsed = microsecondsToSeconds(fields.positionUs);
  const artworkUrl = String(fields.artworkUrl || '').trim();
  const appId = String(fields.playerName || fields.appId || '').trim();

  if (!title) {
    return createEmptyPlaybackState();
  }

  if (status === 'Stopped') {
    return {
      playing: false,
      title,
      artist,
      album,
      duration,
      elapsed: 0,
      appId,
      artworkUrl
    };
  }

  if (duration > 0 && elapsed > duration) {
    elapsed = duration;
  }

  return {
    playing,
    title,
    artist,
    album,
    duration,
    elapsed,
    appId,
    artworkUrl
  };
}

function parsePlayerctlLine(line) {
  if (typeof line !== 'string') return null;
  const trimmed = line.replace(/\r?\n$/, '');
  if (!trimmed.trim()) return null;

  const sep = trimmed.includes(MPRIS_FIELD_SEP) ? MPRIS_FIELD_SEP : '\t';
  const parts = trimmed.split(sep);
  const [
    status = '',
    title = '',
    artist = '',
    album = '',
    lengthUs = '',
    artworkUrl = '',
    positionUs = '',
    playerName = ''
  ] = parts;

  return buildPlaybackSnapshot({
    status,
    title,
    artist,
    album,
    lengthUs,
    artworkUrl,
    positionUs,
    playerName
  });
}

function unwrapGVariantString(raw) {
  const text = String(raw || '').trim();
  const m = text.match(/^'((?:\\.|[^'\\])*)'$/) || text.match(/^"((?:\\.|[^"\\])*)"$/);
  if (!m) return text;
  return m[1]
    .replace(/\\'/g, "'")
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, '\\');
}

function extractGVariantField(source, key) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`['"]${escapedKey}['"]\\s*:\\s*<`);
  const match = re.exec(source);
  if (!match) return '';
  let idx = match.index + match[0].length;
  let depth = 1;
  let quote = null;
  let escaped = false;
  const start = idx;

  while (idx < source.length && depth > 0) {
    const ch = source[idx];
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === quote) {
        quote = null;
      }
    } else if (ch === '\'' || ch === '"') {
      quote = ch;
    } else if (ch === '<') {
      depth++;
    } else if (ch === '>') {
      depth--;
      if (depth === 0) break;
    }
    idx++;
  }
  return source.slice(start, idx).trim();
}

function extractGVariantNumber(raw) {
  if (!raw) return 0;
  const match = String(raw).match(/(-?\d+(?:\.\d+)?)\s*$/);
  return match ? Number(match[1]) : 0;
}

function parseGdbusGetAll(output, playerName = '') {
  if (typeof output !== 'string' || !output.trim()) return createEmptyPlaybackState();
  const status = unwrapGVariantString(extractGVariantField(output, 'PlaybackStatus'));
  const positionUs = extractGVariantNumber(extractGVariantField(output, 'Position'));
  const metadataBlock = extractGVariantField(output, 'Metadata') || output;

  const title = unwrapGVariantString(extractGVariantField(metadataBlock, 'xesam:title'));
  const artistRaw = extractGVariantField(metadataBlock, 'xesam:artist');
  const album = unwrapGVariantString(extractGVariantField(metadataBlock, 'xesam:album'));
  const lengthUs = extractGVariantNumber(extractGVariantField(metadataBlock, 'mpris:length'));
  const artworkUrl = unwrapGVariantString(extractGVariantField(metadataBlock, 'mpris:artUrl'));

  return buildPlaybackSnapshot({
    status,
    title,
    artist: artistRaw,
    album,
    lengthUs,
    artworkUrl,
    positionUs,
    playerName
  });
}

function extractDbusSendDictEntry(output, key) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const keyRe = new RegExp(`string\\s+"${escapedKey}"\\s*\\n\\s*variant\\s+([\\s\\S]*?)(?=\\n\\s*\\)|\\n\\s*dict entry\\()`, 'm');
  const match = keyRe.exec(output);
  return match ? match[1].trim() : '';
}

function parseDbusSendGetAll(output, playerName = '') {
  if (typeof output !== 'string' || !output.trim()) return createEmptyPlaybackState();

  const statusEntry = extractDbusSendDictEntry(output, 'PlaybackStatus');
  const statusMatch = statusEntry.match(/^string\s+"((?:\\.|[^"\\])*)"/);
  const status = statusMatch ? statusMatch[1] : '';

  const positionEntry = extractDbusSendDictEntry(output, 'Position');
  const posMatch = positionEntry.match(/(?:int64|uint64|int32|uint32)\s+(-?\d+)/);
  const positionUs = posMatch ? Number(posMatch[1]) : 0;

  const titleEntry = extractDbusSendDictEntry(output, 'xesam:title');
  const titleMatch = titleEntry.match(/^string\s+"((?:\\.|[^"\\])*)"/);
  const title = titleMatch ? titleMatch[1] : '';

  const albumEntry = extractDbusSendDictEntry(output, 'xesam:album');
  const albumMatch = albumEntry.match(/^string\s+"((?:\\.|[^"\\])*)"/);
  const album = albumMatch ? albumMatch[1] : '';

  const artEntry = extractDbusSendDictEntry(output, 'mpris:artUrl');
  const artMatch = artEntry.match(/^string\s+"((?:\\.|[^"\\])*)"/);
  const artworkUrl = artMatch ? artMatch[1] : '';

  const lengthEntry = extractDbusSendDictEntry(output, 'mpris:length');
  const lenMatch = lengthEntry.match(/(?:int64|uint64|int32|uint32)\s+(-?\d+)/);
  const lengthUs = lenMatch ? Number(lenMatch[1]) : 0;

  const artistEntry = extractDbusSendDictEntry(output, 'xesam:artist');
  const artists = [];
  const strRe = /string\s+"((?:\\.|[^"\\])*)"/g;
  let m;
  while ((m = strRe.exec(artistEntry)) !== null) {
    const val = m[1].trim();
    if (val) artists.push(val);
  }

  return buildPlaybackSnapshot({
    status,
    title,
    artist: artists,
    album,
    lengthUs,
    artworkUrl,
    positionUs,
    playerName
  });
}

function sortMprisBuses(busNames) {
  const mprisBuses = (busNames || []).filter((name) => typeof name === 'string' && name.startsWith('org.mpris.MediaPlayer2.'));
  return mprisBuses.sort((a, b) => {
    const la = a.toLowerCase();
    const lb = b.toLowerCase();
    const ia = PREFERRED_PLAYER_ORDER.findIndex((p) => la.includes(p));
    const ib = PREFERRED_PLAYER_ORDER.findIndex((p) => lb.includes(p));
    const pa = ia === -1 ? 999 : ia;
    const pb = ib === -1 ? 999 : ib;
    if (pa !== pb) return pa - pb;
    return la.localeCompare(lb);
  });
}

function parseDbusNameList(output) {
  if (typeof output !== 'string') return [];
  const names = [];
  const re = /['"](org\.mpris\.MediaPlayer2\.[^'"]+)['"]/g;
  let m;
  while ((m = re.exec(output)) !== null) {
    names.push(m[1]);
  }
  return sortMprisBuses(Array.from(new Set(names)));
}

function runExecFile(execFileFn, cmd, args, timeoutMs = 1500) {
  return new Promise((resolve, reject) => {
    execFileFn(cmd, args, { encoding: 'utf8', timeout: timeoutMs }, (err, stdout, stderr) => {
      if (err) {
        err.stderr = stderr;
        reject(err);
        return;
      }
      resolve(stdout);
    });
  });
}

function startMprisWatcher({
  onState,
  onError = () => {},
  spawnFn = spawn,
  execFileFn = execFile,
  pollIntervalMs = 1000,
  positionPollMs = 2000,
  retryDelayMs = 2500
} = {}) {
  let stopped = false;
  let activeProc = null;
  let retryTimer = null;
  let positionTimer = null;
  let pollTimer = null;
  let latestState = createEmptyPlaybackState();
  let usingFallback = false;
  let dbusPollInFlight = false;

  const emitState = (next) => {
    if (stopped || !next) return;
    latestState = next;
    onState(next);
  };

  const clearTimers = () => {
    if (retryTimer) { clearTimeout(retryTimer); retryTimer = null; }
    if (positionTimer) { clearInterval(positionTimer); positionTimer = null; }
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  };

  const stopPositionSync = () => {
    if (positionTimer) {
      clearInterval(positionTimer);
      positionTimer = null;
    }
  };

  const startPositionSync = () => {
    if (positionTimer || stopped || usingFallback) return;
    positionTimer = setInterval(async () => {
      if (stopped || !latestState.playing || !latestState.title) return;
      try {
        const out = await runExecFile(execFileFn, 'playerctl', ['position'], 1000);
        const sec = Number(String(out || '').trim());
        if (Number.isFinite(sec) && sec >= 0 && latestState.playing && latestState.title) {
          const clamped = latestState.duration > 0 ? Math.min(latestState.duration, sec) : sec;
          if (Math.abs(clamped - latestState.elapsed) > 0.65) {
            emitState({ ...latestState, elapsed: Math.round(clamped * 1000) / 1000 });
          }
        }
      } catch (_) {}
    }, positionPollMs);
  };

  const schedulePlayerctlRetry = () => {
    if (stopped || retryTimer || usingFallback) return;
    retryTimer = setTimeout(() => {
      retryTimer = null;
      if (!stopped && !usingFallback) startPlayerctlFollow();
    }, retryDelayMs);
  };

  async function pollDbusOnce(backend) {
    if (stopped || dbusPollInFlight) return;
    dbusPollInFlight = true;
    try {
      const listArgs = backend === 'gdbus'
        ? ['call', '--session', '--dest', 'org.freedesktop.DBus', '--object-path', '/org/freedesktop/DBus', '--method', 'org.freedesktop.DBus.ListNames']
        : ['--print-reply', '--session', '--dest=org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus.ListNames'];
      const listOut = await runExecFile(execFileFn, backend, listArgs, 1500);
      const buses = parseDbusNameList(listOut);
      if (!buses.length) {
        if (latestState.title || latestState.playing) {
          emitState(createEmptyPlaybackState());
        }
        return;
      }

      const candidates = [];
      for (const bus of buses) {
        try {
          const playerName = bus.replace(/^org\.mpris\.MediaPlayer2\./, '').split('.')[0];
          const getArgs = backend === 'gdbus'
            ? ['call', '--session', '--dest', bus, '--object-path', '/org/mpris/MediaPlayer2', '--method', 'org.freedesktop.DBus.Properties.GetAll', 'org.mpris.MediaPlayer2.Player']
            : ['--print-reply', '--session', `--dest=${bus}`, '/org/mpris/MediaPlayer2', 'org.freedesktop.DBus.Properties.GetAll', 'string:org.mpris.MediaPlayer2.Player'];
          const rawProps = await runExecFile(execFileFn, backend, getArgs, 1500);
          const parsed = backend === 'gdbus'
            ? parseGdbusGetAll(rawProps, playerName)
            : parseDbusSendGetAll(rawProps, playerName);
          if (parsed.title) candidates.push(parsed);
        } catch (_) {}
      }

      const chosen = candidates.find((c) => c.playing) || candidates[0] || createEmptyPlaybackState();
      emitState(chosen);
    } catch (err) {
      onError(err);
    } finally {
      dbusPollInFlight = false;
    }
  }

  async function startDbusFallback() {
    if (stopped || usingFallback) return;
    usingFallback = true;
    stopPositionSync();

    let backend = null;
    for (const candidate of ['gdbus', 'dbus-send']) {
      try {
        await runExecFile(execFileFn, candidate, ['--version'], 1000);
        backend = candidate;
        break;
      } catch (err) {
        if (err && err.code !== 'ENOENT') {
          backend = candidate;
          break;
        }
      }
    }

    if (!backend) {
      onError(new Error('Neither playerctl, gdbus, nor dbus-send is available for Linux MPRIS2 playback detection.'));
      return;
    }

    await pollDbusOnce(backend);
    if (!stopped) {
      pollTimer = setInterval(() => {
        pollDbusOnce(backend).catch(() => {});
      }, pollIntervalMs);
    }
  }

  function startPlayerctlFollow() {
    if (stopped || usingFallback) return;
    let buffer = '';
    const proc = spawnFn('playerctl', ['--follow', 'metadata', '--format', PLAYERCTL_FORMAT], {
      stdio: ['ignore', 'pipe', 'pipe']
    });
    activeProc = proc;

    proc.stdout.on('data', (chunk) => {
      buffer += chunk.toString('utf8');
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() || '';
      for (const line of lines) {
        const parsed = parsePlayerctlLine(line);
        if (!parsed) continue;
        emitState(parsed);
        if (parsed.playing) startPositionSync();
        else stopPositionSync();
      }
    });

    proc.on('error', (err) => {
      if (activeProc === proc) activeProc = null;
      if (err && err.code === 'ENOENT') {
        startDbusFallback().catch(onError);
      } else {
        onError(err);
        schedulePlayerctlRetry();
      }
    });

    proc.on('exit', () => {
      if (activeProc === proc) activeProc = null;
      stopPositionSync();
      if (!stopped && !usingFallback) {
        if (latestState.title || latestState.playing) {
          emitState(createEmptyPlaybackState());
        }
        schedulePlayerctlRetry();
      }
    });
  }

  startPlayerctlFollow();

  return {
    stop() {
      stopped = true;
      clearTimers();
      if (activeProc && !activeProc.killed) {
        try {
          activeProc.kill();
        } catch (_) {}
      }
      activeProc = null;
    }
  };
}

async function sendMprisCommand(command, { execFileFn = execFile } = {}) {
  const playerctlMap = {
    togglePlayPause: 'play-pause',
    next: 'next',
    previous: 'previous'
  };
  const dbusMethodMap = {
    togglePlayPause: 'PlayPause',
    next: 'Next',
    previous: 'Previous'
  };
  const pcCmd = playerctlMap[command];
  const dbusMethod = dbusMethodMap[command];
  if (!pcCmd || !dbusMethod) return false;

  try {
    await runExecFile(execFileFn, 'playerctl', [pcCmd], 1500);
    return true;
  } catch (err) {
    if (!err || err.code !== 'ENOENT') return false;
  }

  try {
    const listOut = await runExecFile(
      execFileFn,
      'gdbus',
      ['call', '--session', '--dest', 'org.freedesktop.DBus', '--object-path', '/org/freedesktop/DBus', '--method', 'org.freedesktop.DBus.ListNames'],
      1500
    );
    const buses = parseDbusNameList(listOut);
    if (!buses.length) return false;
    await runExecFile(
      execFileFn,
      'gdbus',
      ['call', '--session', '--dest', buses[0], '--object-path', '/org/mpris/MediaPlayer2', '--method', `org.mpris.MediaPlayer2.Player.${dbusMethod}`],
      1500
    );
    return true;
  } catch (_) {
    try {
      const listOut = await runExecFile(
        execFileFn,
        'dbus-send',
        ['--print-reply', '--session', '--dest=org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus.ListNames'],
        1500
      );
      const buses = parseDbusNameList(listOut);
      if (!buses.length) return false;
      await runExecFile(
        execFileFn,
        'dbus-send',
        ['--session', `--dest=${buses[0]}`, '/org/mpris/MediaPlayer2', `org.mpris.MediaPlayer2.Player.${dbusMethod}`],
        1500
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

module.exports = {
  MPRIS_FIELD_SEP,
  PLAYERCTL_FORMAT,
  EMPTY_PLAYBACK_STATE,
  createEmptyPlaybackState,
  microsecondsToSeconds,
  normalizeMprisStatus,
  normalizeMprisArtist,
  buildPlaybackSnapshot,
  parsePlayerctlLine,
  parseGdbusGetAll,
  parseDbusSendGetAll,
  sortMprisBuses,
  parseDbusNameList,
  startMprisWatcher,
  sendMprisCommand
};

'use strict';

const { EventEmitter } = require('events');
const {
  MPRIS_FIELD_SEP,
  microsecondsToSeconds,
  normalizeMprisStatus,
  normalizeMprisArtist,
  buildPlaybackSnapshot,
  parsePlayerctlLine,
  parseGdbusGetAll,
  parseDbusSendGetAll,
  parseDbusNameList,
  startMprisWatcher
} = require('../mpris_bridge');

let failures = 0;
function check(cond, name) {
  if (cond) {
    console.log(`PASS ${name}`);
  } else {
    failures++;
    console.error(`FAIL ${name}`);
  }
}

// 1. Microseconds -> seconds conversion
check(microsecondsToSeconds('245000000') === 245, 'microsecondsToSeconds converts string microseconds to seconds');
check(microsecondsToSeconds(12345678) === 12.346, 'microsecondsToSeconds rounds to millisecond precision');
check(microsecondsToSeconds(0) === 0, 'microsecondsToSeconds handles zero');
check(microsecondsToSeconds(-500000) === 0, 'microsecondsToSeconds clamps negative values to 0');
check(microsecondsToSeconds('') === 0 && microsecondsToSeconds(null) === 0 && microsecondsToSeconds('NaN') === 0, 'microsecondsToSeconds handles empty/null/NaN safely');

// 2. Status normalization (Playing / Paused / Stopped)
check(normalizeMprisStatus('Playing').playing === true && normalizeMprisStatus('Playing').status === 'Playing', 'normalizeMprisStatus handles Playing');
check(normalizeMprisStatus('paused').playing === false && normalizeMprisStatus('paused').status === 'Paused', 'normalizeMprisStatus handles Paused');
check(normalizeMprisStatus('Stopped').playing === false && normalizeMprisStatus('Stopped').status === 'Stopped', 'normalizeMprisStatus handles Stopped');
check(normalizeMprisStatus('').playing === false && normalizeMprisStatus('').status === 'Stopped', 'normalizeMprisStatus defaults unknown/empty to Stopped');

// 3. Artist metadata (empty / array / GVariant array string)
check(normalizeMprisArtist(['YOASOBI', 'Ayase']) === 'YOASOBI, Ayase', 'normalizeMprisArtist joins string arrays');
check(normalizeMprisArtist([]) === '', 'normalizeMprisArtist returns empty string for empty array');
check(normalizeMprisArtist("['Aimer', 'Sawano Hiroyuki']") === 'Aimer, Sawano Hiroyuki', 'normalizeMprisArtist parses GVariant quoted array strings');
check(normalizeMprisArtist('@as []') === '' && normalizeMprisArtist('[]') === '', 'normalizeMprisArtist handles empty GVariant array literals');
check(normalizeMprisArtist(null) === '' && normalizeMprisArtist('') === '', 'normalizeMprisArtist handles null and empty string');

// 4. playerctl line parser
const linePlaying = [
  'Playing',
  '夜に駆ける',
  'YOASOBI',
  'THE BOOK',
  '260000000',
  'https://example.com/art.jpg',
  '42500000',
  'spotify'
].join(MPRIS_FIELD_SEP);

const parsedPlaying = parsePlayerctlLine(linePlaying);
check(
  parsedPlaying &&
  parsedPlaying.playing === true &&
  parsedPlaying.title === '夜に駆ける' &&
  parsedPlaying.artist === 'YOASOBI' &&
  parsedPlaying.album === 'THE BOOK' &&
  parsedPlaying.duration === 260 &&
  parsedPlaying.elapsed === 42.5 &&
  parsedPlaying.artworkUrl === 'https://example.com/art.jpg' &&
  parsedPlaying.appId === 'spotify',
  'parsePlayerctlLine parses full Playing line with microseconds conversion'
);

const linePaused = [
  'Paused',
  'Hati-Hati di Jalan',
  "['Tulus']",
  'Manusia',
  '242000000',
  'file:///tmp/cover.png',
  '300000000',
  'vlc'
].join(MPRIS_FIELD_SEP);

const parsedPaused = parsePlayerctlLine(linePaused);
check(
  parsedPaused &&
  parsedPaused.playing === false &&
  parsedPaused.artist === 'Tulus' &&
  parsedPaused.elapsed === 242,
  'parsePlayerctlLine handles Paused, array artist, and clamps elapsed to duration'
);

const lineStopped = ['Stopped', 'Old Song', 'Artist', 'Album', '180000000', '', '95000000', 'mpv'].join(MPRIS_FIELD_SEP);
const parsedStopped = parsePlayerctlLine(lineStopped);
check(
  parsedStopped &&
  parsedStopped.playing === false &&
  parsedStopped.elapsed === 0,
  'parsePlayerctlLine resets elapsed to 0 and playing=false on Stopped'
);

const lineEmptyMeta = ['Playing', '', '[]', '', '0', '', '0', 'spotify'].join(MPRIS_FIELD_SEP);
const parsedEmpty = parsePlayerctlLine(lineEmptyMeta);
check(
  parsedEmpty &&
  parsedEmpty.playing === false &&
  parsedEmpty.title === '' &&
  parsedEmpty.artist === '' &&
  parsedEmpty.duration === 0,
  'parsePlayerctlLine returns idle empty state when title is empty'
);

check(parsePlayerctlLine('   \n') === null, 'parsePlayerctlLine ignores blank lines');

// 5. gdbus GetAll parser
const gdbusSample = `({'PlaybackStatus': <'Playing'>, 'Position': <int64 61500000>, 'Metadata': <{'mpris:trackid': <objectpath '/org/mpris/MediaPlayer2/Track/1'>, 'mpris:length': <int64 210000000>, 'mpris:artUrl': <'https://i.scdn.co/image/abc'>, 'xesam:title': <'It\\'s Gonna Be Fine'>, 'xesam:artist': <['Artist One', 'Artist Two']>, 'xesam:album': <'Greatest Hits'>}>},)`;
const parsedGdbus = parseGdbusGetAll(gdbusSample, 'spotify');
check(
  parsedGdbus.playing === true &&
  parsedGdbus.title === "It's Gonna Be Fine" &&
  parsedGdbus.artist === 'Artist One, Artist Two' &&
  parsedGdbus.album === 'Greatest Hits' &&
  parsedGdbus.duration === 210 &&
  parsedGdbus.elapsed === 61.5 &&
  parsedGdbus.artworkUrl === 'https://i.scdn.co/image/abc' &&
  parsedGdbus.appId === 'spotify',
  'parseGdbusGetAll decodes GVariant metadata, escaped quotes, artist array, and microseconds'
);

const gdbusEmptyArtist = `({'PlaybackStatus': <'Paused'>, 'Position': <int64 0>, 'Metadata': <{'xesam:title': <'Instrumental'>, 'xesam:artist': <@as []>, 'mpris:length': <uint64 120000000>}>},)`;
const parsedGdbusEmptyArtist = parseGdbusGetAll(gdbusEmptyArtist, 'vlc');
check(
  parsedGdbusEmptyArtist.playing === false &&
  parsedGdbusEmptyArtist.title === 'Instrumental' &&
  parsedGdbusEmptyArtist.artist === '' &&
  parsedGdbusEmptyArtist.duration === 120,
  'parseGdbusGetAll handles @as [] empty artist arrays'
);

// 6. dbus-send GetAll parser
const dbusSendSample = `method return time=1700000000.000000 sender=:1.42 -> destination=:1.99 serial=10 reply_serial=2
   array [
      dict entry(
         string "PlaybackStatus"
         variant             string "Playing"
      )
      dict entry(
         string "Position"
         variant             int64 15000000
      )
      dict entry(
         string "Metadata"
         variant             array [
               dict entry(
                  string "xesam:title"
                  variant                      string "Midnight City"
               )
               dict entry(
                  string "xesam:artist"
                  variant                      array [
                        string "M83"
                        string "Guest"
                     ]
               )
               dict entry(
                  string "xesam:album"
                  variant                      string "Hurry Up"
               )
               dict entry(
                  string "mpris:length"
                  variant                      int64 243000000
               )
               dict entry(
                  string "mpris:artUrl"
                  variant                      string "file:///home/user/art.jpg"
               )
            ]
      )
   ]`;
const parsedDbusSend = parseDbusSendGetAll(dbusSendSample, 'vlc');
check(
  parsedDbusSend.playing === true &&
  parsedDbusSend.title === 'Midnight City' &&
  parsedDbusSend.artist === 'M83, Guest' &&
  parsedDbusSend.album === 'Hurry Up' &&
  parsedDbusSend.duration === 243 &&
  parsedDbusSend.elapsed === 15 &&
  parsedDbusSend.artworkUrl === 'file:///home/user/art.jpg',
  'parseDbusSendGetAll decodes dbus-send dict entries and artist array'
);

// 7. D-Bus name sorting
const buses = parseDbusNameList(`(['org.freedesktop.DBus', 'org.mpris.MediaPlayer2.mpv', 'org.mpris.MediaPlayer2.spotify'],)`);
check(
  buses.length === 2 &&
  buses[0] === 'org.mpris.MediaPlayer2.spotify' &&
  buses[1] === 'org.mpris.MediaPlayer2.mpv',
  'parseDbusNameList filters MPRIS2 buses and prioritizes preferred players'
);

// 8. Watcher ENOENT fallback from playerctl -> gdbus
async function testWatcherFallback() {
  const emitted = [];
  const mockSpawn = () => {
    const proc = new EventEmitter();
    proc.stdout = new EventEmitter();
    proc.stderr = new EventEmitter();
    proc.killed = false;
    proc.kill = () => { proc.killed = true; };
    process.nextTick(() => {
      const err = new Error('spawn playerctl ENOENT');
      err.code = 'ENOENT';
      proc.emit('error', err);
    });
    return proc;
  };
  const mockExecFile = (cmd, args, _opts, cb) => {
    if (cmd === 'gdbus' && args[0] === '--version') {
      cb(null, '2.78.0', '');
      return;
    }
    if (cmd === 'gdbus' && args.includes('org.freedesktop.DBus.ListNames')) {
      cb(null, "(['org.mpris.MediaPlayer2.spotify'],)", '');
      return;
    }
    if (cmd === 'gdbus' && args.includes('org.freedesktop.DBus.Properties.GetAll')) {
      cb(null, gdbusSample, '');
      return;
    }
    cb(new Error(`Unexpected execFile: ${cmd}`), '', '');
  };

  const watcher = startMprisWatcher({
    onState: (s) => emitted.push(s),
    spawnFn: mockSpawn,
    execFileFn: mockExecFile,
    pollIntervalMs: 5000
  });

  await new Promise((r) => setTimeout(r, 80));
  watcher.stop();

  check(
    emitted.length >= 1 &&
    emitted[0].playing === true &&
    emitted[0].title === "It's Gonna Be Fine" &&
    emitted[0].artist === 'Artist One, Artist Two',
    'startMprisWatcher falls back to gdbus polling when playerctl is ENOENT'
  );

  // Also test buildPlaybackSnapshot directly for empty snapshot
  const emptySnap = buildPlaybackSnapshot({ status: 'Playing', title: '', artist: [] });
  check(emptySnap.playing === false && emptySnap.title === '', 'buildPlaybackSnapshot normalizes empty metadata');

  if (failures > 0) {
    console.error(`${failures} failing MPRIS2 bridge test(s)`);
    process.exit(1);
  }
  console.log('All MPRIS2 bridge tests passed');
}

testWatcherFallback().catch((err) => {
  console.error(err);
  process.exit(1);
});

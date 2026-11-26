'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  cleanTitle,
  cleanArtist,
  resolveExpectedTitleArtist,
  buildQueryCandidates,
  scoreCandidate,
  parseYRC,
  parseLRC,
  romanizeKoreanHangul,
  isRTLScript,
  DiskLyricsCache,
  computeLineProgress
} = require('../lyrics-engine');

let failures = 0;
function check(cond, name) {
  if (cond) {
    console.log(`PASS ${name}`);
  } else {
    failures++;
    console.error(`FAIL ${name}`);
  }
}

check(cleanTitle('YOASOBI「夜に駆ける」Official Music Video') === '夜に駆ける', 'cleanTitle extracts Japanese quoted title');
check(cleanTitle('Tulus \u2013 Hati-Hati di Jalan - Official Music Video') === 'Tulus - Hati-Hati di Jalan', 'cleanTitle normalizes en-dash and trims noise');
check(cleanArtist('Hindia - Topic') === 'Hindia', 'cleanArtist strips - Topic');

const pair = resolveExpectedTitleArtist('Tulus - Hati-Hati di Jalan (Official Video)', 'Musica Studios');
check(pair.title === 'Hati-Hati di Jalan' && pair.artist === 'Tulus', 'extracts true title & artist when uploader differs');

const q = buildQueryCandidates('Tulus - Hati-Hati di Jalan', 'Musica Studios');
check(q.some((c) => c.track === 'Hati-Hati di Jalan' && c.artist === 'Tulus'), 'query builder includes parsed pair');

const orig = scoreCandidate({
  trackName: 'Wish You Were Here',
  artistName: 'Neck Deep',
  rawInputTitle: 'Wish You Were Here',
  expectedTitle: 'Wish You Were Here',
  expectedArtist: 'Neck Deep',
  refDuration: 248.2,
  targetDuration: 248.3,
  hasSynced: true,
  hasWordTimings: true
});
const spedUp = scoreCandidate({
  trackName: 'Wish You Were Here (Sped Up)',
  artistName: 'Neck Deep',
  rawInputTitle: 'Wish You Were Here',
  expectedTitle: 'Wish You Were Here',
  expectedArtist: 'Neck Deep',
  refDuration: 248.2,
  targetDuration: 248.3,
  hasSynced: true,
  hasWordTimings: false
});
const unrelated = scoreCandidate({
  trackName: 'Unrelated Song',
  artistName: 'Neck Deep',
  rawInputTitle: 'Wish You Were Here',
  expectedTitle: 'Wish You Were Here',
  expectedArtist: 'Neck Deep',
  refDuration: 248.2,
  targetDuration: 248.3,
  hasSynced: true,
  hasWordTimings: false
});
check(orig > spedUp + 40, 'original track dominates Sped Up remix');
check(unrelated < 65, 'zero title overlap rejected below 65');

const yrc = parseYRC('[1000,1500](1000,500,0)Hello (1500,1000,0)world');
check(yrc.length === 1 && yrc[0].words.length === 2, 'parseYRC decodes word-level timestamps');

const lrc = parseLRC('[00:10.00]Say it again (say it again)\n[00:15.00]Next');
check(lrc.length === 2 && lrc[0].mainText === 'Say it again' && lrc[0].backingText === 'say it again', 'parseLRC splits main & backing vocal');
check(computeLineProgress(yrc[0], 1.75, 5.0) > 0.5, 'computeLineProgress interpolates word cursor accurately');

check(romanizeKoreanHangul('사랑해요 괜찮아 빨리') === 'saranghaeyo gwaenchana ppalli', 'algorithmic Korean Hangul handles liaison and assimilation');
check(isRTLScript('حبيبي يا نور العين') === true, 'detects Arabic RTL script');

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'notchlyrics-win-test-'));
const cache = new DiskLyricsCache(tmpDir);
cache.save({ lines: lrc, sourceName: 'LRCLIB', referenceDuration: 210 }, 'k|a|210', 'k|a');
const reloaded = cache.load('k|a|210', 'k|a', 210);
check(reloaded && reloaded.lines.length === 2, 'disk cache saves and reloads synced track');
fs.rmSync(tmpDir, { recursive: true, force: true });

if (failures > 0) {
  console.error(`${failures} failing Windows engine test(s)`);
  process.exit(1);
}
console.log('All Windows engine tests passed');

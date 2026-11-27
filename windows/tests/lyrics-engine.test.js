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
  splitMainAndBacking,
  parseYRC,
  parseLRC,
  parseKuwoSearchResponse,
  mapKuwoLrcList,
  romanizeKoreanHangul,
  isRTLScript,
  DiskLyricsCache,
  buildTrackCacheKeys,
  clearTrackCache,
  fetchLyrics,
  findActiveLineIndex,
  computeLineProgress,
  computeFrameState
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

const jpNativeLines = Array.from({ length: 6 }, (_, i) => ({ time: i * 18, mainText: '夜に駆ける夢を見てる' }));
const jpEngLines = Array.from({ length: 6 }, (_, i) => ({ time: i * 18, mainText: 'Into the night we run with you and see the sky' }));
const jpScore = scoreCandidate({
  trackName: '夜に駆ける', artistName: 'YOASOBI', rawInputTitle: '夜に駆ける',
  expectedTitle: '夜に駆ける', expectedArtist: 'YOASOBI',
  refDuration: 260, targetDuration: 260, hasSynced: true, hasWordTimings: false, parsedLines: jpNativeLines
});
const engTransScore = scoreCandidate({
  trackName: '夜に駆ける', artistName: 'YOASOBI', rawInputTitle: '夜に駆ける',
  expectedTitle: '夜に駆ける', expectedArtist: 'YOASOBI',
  refDuration: 260, targetDuration: 260, hasSynced: true, hasWordTimings: false, parsedLines: jpEngLines
});
check(jpScore > 140 && engTransScore < 65, 'Japanese song prioritizes native Kana lyrics and rejects English translations');

const yrc = parseYRC('[1000,1500](1000,500,0)Hello (1500,1000,0)world');
check(yrc.length === 1 && yrc[0].words.length === 2, 'parseYRC decodes word-level timestamps');

const lrc = parseLRC('[00:10.00]Say it again (say it again)\n[00:15.00]Next');
check(lrc.length === 2 && lrc[0].mainText === 'Say it again' && lrc[0].backingText === 'say it again', 'parseLRC splits main & backing vocal');
check(computeLineProgress(yrc[0], 1.75, 5.0) > 0.5, 'computeLineProgress interpolates word cursor accurately');
check(computeLineProgress(yrc[0], 1.35, 5.0, 2.0) > computeLineProgress(yrc[0], 1.35, 5.0, 0.5), 'wordSpeedScale adjusts karaoke sweep pace smoothly');
const {
  LANGUAGES,
  TRANSLATIONS,
  t
} = require('../i18n');

check(typeof fetchLyrics === 'function', 'fetchLyrics pipeline exports cleanly with multi-source support');
let winI18nGaps = 0;
for (const [k, row] of Object.entries(TRANSLATIONS)) {
  for (const lang of LANGUAGES) {
    if (!row[lang.code] || !String(row[lang.code]).trim()) winI18nGaps++;
  }
}
check(winI18nGaps === 0 && t('en', 'languageMenu') === 'Settings Language' && t('id', 'languageMenu') === 'Bahasa Pengaturan', 'Windows multi-language UI covers all 6 supported languages');

check(romanizeKoreanHangul('사랑해요 괜찮아 빨리') === 'saranghaeyo gwaenchana ppalli', 'algorithmic Korean Hangul handles liaison and assimilation');
check(isRTLScript('حبيبي يا نور العين') === true, 'detects Arabic RTL script');

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'notchlyrics-win-test-'));
const cache = new DiskLyricsCache(tmpDir);
cache.save({ lines: lrc, sourceName: 'LRCLIB', referenceDuration: 210 }, 'k|a|210', 'k|a');
const reloaded = cache.load('k|a|210', 'k|a', 210);
const hashBase = path.basename(cache._pathFor('k|a|210'), '.json');
check(reloaded && reloaded.lines.length === 2, 'disk cache saves and reloads synced track');
check(hashBase.length >= 32, 'disk cache uses >= 32 hex chars (128-bit SHA-256) key');
fs.rmSync(tmpDir, { recursive: true, force: true });

// cleanArtist comma & "&" group preservation
check(cleanArtist('Earth, Wind & Fire') === 'Earth, Wind & Fire', 'cleanArtist preserves Earth, Wind & Fire intact');
check(cleanArtist('Tyler, The Creator') === 'Tyler, The Creator', 'cleanArtist preserves Tyler, The Creator intact');
check(cleanArtist('Sammy Davis, Jr.') === 'Sammy Davis, Jr.', 'cleanArtist preserves Jr. suffix intact');
check(cleanArtist('Dua Lipa feat. DaBaby') === 'Dua Lipa', 'cleanArtist strips collaboration feat. suffix');
check(cleanArtist('Kenshi Yonezu, Yojiro Noda') === 'Kenshi Yonezu', 'cleanArtist splits true multi-artist commas');

// cleanTitle jpQuote & | / // metadata guard
check(cleanTitle('Artist - Track | Official Music Video') === 'Artist - Track', 'cleanTitle strips | Official Music Video');
check(cleanTitle('Artist - Track // Lyrics Video') === 'Artist - Track', 'cleanTitle strips // Lyrics Video');
check(cleanTitle('Artist - Track | Part II') === 'Artist - Track | Part II', 'cleanTitle keeps non-metadata | suffix intact');
check(cleanTitle('Main Song 「Anime OP」 Full Theme') === 'Main Song 「Anime OP」 Full Theme', 'cleanTitle keeps main title when text exists after Japanese quote');

// splitMainAndBacking inline syntactic parens vs backing vocals & ad-libs
const inlineMain = splitMainAndBacking("(I can't get no) satisfaction");
check(inlineMain.main === "(I can't get no) satisfaction" && inlineMain.backing === null, 'splitMainAndBacking preserves inline parenthesized main lyrics');
const adLibLead = splitMainAndBacking('(Ooh yeah) Dancing in the rain');
check(adLibLead.main === 'Dancing in the rain' && adLibLead.backing === 'Ooh yeah', 'splitMainAndBacking extracts leading ad-lib backing');

// parseLRC empty break endTime & Enhanced LRC <mm:ss.xx>
const breakParsed = parseLRC('[00:45.00]Aku pulang\n[00:48.00]\n[00:56.00]Sampai');
check(breakParsed.length === 2 && breakParsed[0].endTime === 48.0, 'parseLRC uses empty timestamp row as endTime instrumental break');
check(computeLineProgress(breakParsed[0], 47.9, 56.0) === 1, 'computeLineProgress respects line.endTime instead of nextLineTime across breaks');

const enhParsed = parseLRC('[00:12.00]<00:12.00>Hello <00:12.50>world\n[00:14.00]Next');
check(
  enhParsed.length === 2 &&
  enhParsed[0].words.length === 2 &&
  enhParsed[0].words[0].text === 'Hello ' &&
  enhParsed[0].words[0].duration === 0.5 &&
  enhParsed[0].words[1].text === 'world',
  'parseLRC parses Enhanced LRC word tags into YRC-compatible line.words'
);

// Kuwo search parser & direct structured lrclist mapping
const kuwoParsed = parseKuwoSearchResponse("{'abslist':[{'ARTIST':'Aimer&Sawano','SONGNAME':'ninelie','DURATION':'260','MUSICRID':'MUSIC_998877'}]}");
check(kuwoParsed.length === 1 && kuwoParsed[0].rid === '998877' && kuwoParsed[0].artist === 'Aimer, Sawano', 'parseKuwoSearchResponse parses JS-like abslist safely');
const kuwoMapped = mapKuwoLrcList([
  { time: '0.50', lineLyric: 'Aimer - ninelie' },
  { time: '10.00', lineLyric: 'First line (echo)' },
  { time: '14.50', lineLyric: '' },
  { time: '22.00', lineLyric: 'Second line' }
]);
check(
  kuwoMapped.length === 2 &&
  kuwoMapped[0].mainText === 'First line' &&
  kuwoMapped[0].backingText === 'echo' &&
  kuwoMapped[0].endTime === 14.5 &&
  kuwoMapped[1].time === 22.0,
  'mapKuwoLrcList maps structured Kuwo rows & instrumental breaks directly'
);

// Binary search / incremental cursor line lookup
const timedLines = [
  { time: 5.0, mainText: 'Line one' },
  { time: 10.0, mainText: 'Line two' },
  { time: 15.0, mainText: 'Line three' },
  { time: 20.0, mainText: 'Line four' }
];
check(findActiveLineIndex(timedLines, 2.0, -1) === -1, 'findActiveLineIndex returns -1 before first lyric');
check(findActiveLineIndex(timedLines, 11.2, 0) === 1, 'findActiveLineIndex advances cleanly from sequential hint');
check(findActiveLineIndex(timedLines, 11.5, 1) === 1, 'findActiveLineIndex keeps O(1) cursor within active line');
check(findActiveLineIndex(timedLines, 21.0, 0) === 3, 'findActiveLineIndex binary searches forward seek');
check(findActiveLineIndex(timedLines, 5.5, 3) === 0, 'findActiveLineIndex binary searches backward seek');

// Manual offset affects computeFrameState elapsed calculation
const baseSnap = {
  isPlaying: false,
  duration: 60,
  trackTitle: 'Offset Track',
  manualOffsetSeconds: 0,
  lines: timedLines
};
check(computeFrameState(baseSnap, 9.7, -1).mainText === 'Line one', 'computeFrameState with 0.0s offset shows Line one at 9.7s');
check(computeFrameState({ ...baseSnap, manualOffsetSeconds: 0.5 }, 9.7, -1).mainText === 'Line two', 'computeFrameState with +0.5s offset advances into Line two at 9.7s');
check(computeFrameState({ ...baseSnap, manualOffsetSeconds: -0.5 }, 10.2, -1).mainText === 'Line one', 'computeFrameState with -0.5s offset delays transition at 10.2s');

// Per-track cache clear without deleting other cached songs
const tmpCacheDir = fs.mkdtempSync(path.join(os.tmpdir(), 'notchlyrics-clear-test-'));
const dc = new DiskLyricsCache(tmpCacheDir);
const keysA = buildTrackCacheKeys('Song Alpha', 'Artist A', 200);
const keysB = buildTrackCacheKeys('Song Beta', 'Artist B', 180);
dc.save({ lines: lrc, sourceName: 'LRCLIB', referenceDuration: 200 }, keysA.cacheKey, keysA.fuzzyKey);
dc.save({ lines: lrc, sourceName: 'LRCLIB', referenceDuration: 180 }, keysB.cacheKey, keysB.fuzzyKey);
const didClear = clearTrackCache({ title: 'Song Alpha', artist: 'Artist A', duration: 200, cacheDir: tmpCacheDir });
check(didClear === true && dc.load(keysA.cacheKey, keysA.fuzzyKey, 200) === null, 'clearTrackCache removes target song cache');
check(dc.load(keysB.cacheKey, keysB.fuzzyKey, 180) !== null, 'clearTrackCache preserves other cached tracks');
fs.rmSync(tmpCacheDir, { recursive: true, force: true });

if (failures > 0) {
  console.error(`${failures} failing Windows engine test(s)`);
  process.exit(1);
}
console.log('All Windows engine tests passed');

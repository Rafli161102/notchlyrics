'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function normalizeDashSeparators(text) {
  return String(text || '').replace(/\s+[\u2013\u2014\u2015~]\s+/g, ' - ');
}

function cleanTitle(raw) {
  let s = String(raw || '');
  const jpQuote = s.match(/[\u300C\u300E]([^\u300D\u300F]+)[\u300D\u300F]/);
  if (jpQuote && jpQuote[1] && jpQuote[1].trim().length >= 2) {
    s = jpQuote[1].trim();
  }
  s = s.replace(/\s*[(\[]\s*(Official\s*(Music\s*)?Video|Official\s*Audio|Official\s*MV|Official\s*Lyric\s*Video|Lyric\s*Video|Lyrics?\s*Video|Lyrics?|Lirik(\s*Terjemahan)?|Sub\s*(Indo|Eng|Indonesia|English)|Audio(\s*Only)?|Visualizer|M\/?V|HD|4K|Live(\s*Performance)?|Explicit|Clean(\s*Version)?|Single\s*Version|Radio\s*Edit|Album\s*Version|Remaster(ed)?(\s*\d+)?|Slowed(\s*\+\s*Reverb)?|Sped\s*Up|Speed\s*Up|Karaoke|Color\s*Coded|Prod\.?\s*by\s+[^)\]]+)\s*[)\]]/gi, '');
  s = s.replace(/^\s*\[(MV|M\/V|Lyrics?|Audio|Official)\]\s*/i, '');
  s = s.replace(/\s*[-\u2013\u2014]\s*(Official\s*(Music\s*)?Video|Official\s*Audio|Official\s*MV|Lyric\s*Video|Lyrics?|Lirik(\s*Terjemahan)?|Audio(\s*Only)?|Remaster(ed)?(\s*\d+)?|Single\s*Version|Radio\s*Edit|YouTube)\s*$/i, '');
  s = s.replace(/\s*\|\s*.*$/, '');
  s = s.replace(/\s*\/\/\s*.*$/, '');
  return normalizeDashSeparators(s).trim();
}

function cleanArtist(raw) {
  let s = String(raw || '')
    .replace(/\s*[-\u2013\u2014]\s*Topic$/i, '')
    .replace(/\s*VEVO$/i, '')
    .replace(/\s*(Official|Channel)$/i, '');
  s = s.split(',')[0] || s;
  s = s.replace(/\s+(feat\.?|ft\.?|featuring|x|&)\s+.*$/i, '');
  return s.trim();
}

function stripFeaturing(text) {
  return String(text || '')
    .replace(/\s*[(\[]?\s*(feat\.?|ft\.?|featuring|with|prod\.?\s*by)\s+[^)\]]+[)\]]?/gi, '')
    .trim();
}

function isRTLScript(text) {
  return /[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]/.test(String(text || ''));
}

function containsHangul(text) {
  return /[\uAC00-\uD7A3]/.test(String(text || ''));
}

function romanizeKoreanHangul(text) {
  const initials = ['g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h'];
  const medials = ['a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i'];
  const finals = ['', 'k', 'k', 'k', 'n', 'n', 'n', 't', 'l', 'k', 'm', 'b', 'l', 't', 'p', 'l', 'm', 'p', 'p', 't', 't', 'ng', 't', 't', 'k', 't', 'p', 't'];
  const liaisonCoda = ['', 'g', 'kk', 'ks', 'n', 'nj', 'n', 'd', 'r', 'lg', 'lm', 'lb', 'ls', 'lt', 'lp', 'r', 'm', 'b', 'bs', 's', 'ss', 'ng', 'j', 'ch', 'k', 't', 'p', ''];

  const chars = Array.from(String(text || ''));
  let out = '';
  let prevFinal = 0;

  for (let i = 0; i < chars.length; i++) {
    const code = chars[i].codePointAt(0);
    if (code >= 0xAC00 && code <= 0xD7A3) {
      const sIdx = code - 0xAC00;
      const lIdx = Math.floor(sIdx / 588);
      const vIdx = Math.floor((sIdx % 588) / 28);
      const fIdx = sIdx % 28;

      let onset = initials[lIdx];
      if (lIdx === 5 && prevFinal === 8) onset = 'l';

      let finalStr = finals[fIdx];
      if (fIdx > 0 && fIdx !== 21 && i + 1 < chars.length) {
        const nextCode = chars[i + 1].codePointAt(0);
        if (nextCode >= 0xAC00 && nextCode <= 0xD7A3) {
          const nextL = Math.floor((nextCode - 0xAC00) / 588);
          if (nextL === 11) {
            finalStr = (fIdx === 17 && (lIdx === 9 || lIdx === 10 || lIdx === 12)) ? 'p' : liaisonCoda[fIdx];
          } else if (nextL === 18 && (fIdx === 1 || fIdx === 7 || fIdx === 12 || fIdx === 17)) {
            finalStr = liaisonCoda[fIdx];
          }
        }
      }

      out += onset + medials[vIdx] + finalStr;
      prevFinal = fIdx;
    } else {
      prevFinal = 0;
      out += chars[i];
    }
  }
  return out.replace(/\s{2,}/g, ' ').trim();
}

function romanizeText(text) {
  const s = String(text || '').trim();
  if (!s) return s;
  if (containsHangul(s)) return romanizeKoreanHangul(s);
  return s;
}

function resolveExpectedTitleArtist(rawTitle, rawArtist) {
  const baseTitle = cleanTitle(rawTitle);
  const baseArtist = cleanArtist(rawArtist);
  if (baseTitle.includes(' - ')) {
    const parts = baseTitle.split(' - ');
    if (parts.length >= 2) {
      const left = cleanArtist(parts[0]);
      const right = cleanTitle(parts.slice(1).join(' - '));
      if (left && right) {
        const normArt = baseArtist.toLowerCase();
        if (normArt && (normArt === right.toLowerCase() || right.toLowerCase().includes(normArt))) {
          return { title: cleanTitle(parts[0]), artist: right };
        }
        return { title: right, artist: left };
      }
    }
  }
  return { title: baseTitle, artist: baseArtist };
}

function buildQueryCandidates(rawTitle, rawArtist) {
  const baseTitle = cleanTitle(rawTitle);
  const baseArtist = cleanArtist(rawArtist);
  const pairs = [];
  const addPair = (track, artist) => {
    const ct = (track || '').trim();
    const ca = (artist || '').trim();
    if (!ct) return;
    if (!pairs.some((p) => p.track.toLowerCase() === ct.toLowerCase() && p.artist.toLowerCase() === ca.toLowerCase())) {
      pairs.push({ track: ct, artist: ca });
    }
  };

  if (baseTitle.includes(' - ')) {
    const parts = baseTitle.split(' - ');
    const left = cleanArtist(parts[0]);
    const right = cleanTitle(parts.slice(1).join(' - '));
    addPair(right, left);
    addPair(stripFeaturing(right), left);
    if (baseArtist && baseArtist.toLowerCase() !== left.toLowerCase()) addPair(right, baseArtist);
    addPair(left, right);
    addPair(right, '');
  }

  addPair(baseTitle, baseArtist);
  addPair(stripFeaturing(baseTitle), baseArtist);
  if (baseArtist) {
    addPair(baseTitle, '');
    addPair(stripFeaturing(baseTitle), '');
  }
  return pairs;
}

function normalizedTokens(text) {
  const cleaned = String(text || '').toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ');
  return new Set(cleaned.split(/\s+/).filter(Boolean));
}

function scoreCandidate({ trackName, artistName, rawInputTitle, expectedTitle, expectedArtist, refDuration, targetDuration, hasSynced, hasWordTimings, parsedLines }) {
  let score = hasSynced ? 100 : 20;
  if (hasWordTimings) score += 26;

  if (targetDuration > 20 && refDuration > 20) {
    const diff = Math.abs(refDuration - targetDuration);
    if (diff <= 1.5) score += 34;
    else if (diff <= 3.5) score += 24 - (diff - 1.5) * 4.5;
    else if (diff <= 8.0) score += 8 - diff * 2.5;
    else score -= Math.min(95, diff * 3.8);
  }

  const normTrack = String(trackName || '').toLowerCase().trim();
  const normExpTitle = String(expectedTitle || '').toLowerCase().trim();
  const normRawAll = String(rawInputTitle || '').toLowerCase();

  if (normExpTitle) {
    const tTok = normalizedTokens(normTrack);
    const eTok = normalizedTokens(normExpTitle);
    const rTok = normalizedTokens(normRawAll);
    let overlapE = 0;
    tTok.forEach((t) => { if (eTok.has(t)) overlapE++; });
    let overlapR = 0;
    tTok.forEach((t) => { if (rTok.has(t)) overlapR++; });
    const overlap = Math.max(overlapE, overlapR);
    const union = new Set([...tTok, ...eTok]).size || 1;
    const jaccard = overlap / union;

    if (normTrack === normExpTitle) score += 34;
    else if (normTrack.includes(normExpTitle) || normExpTitle.includes(normTrack) || (normTrack && normRawAll.includes(normTrack))) score += 20;
    else if (jaccard >= 0.42) score += 18 * jaccard;
    else if (overlap >= 2 && overlap >= Math.min(tTok.size, eTok.size)) score += 12;
    else if (overlap === 0) score -= 125;
    else score -= 72;
  }

  const normArtist = String(artistName || '').toLowerCase().trim();
  const normExpArtist = String(expectedArtist || '').toLowerCase().trim();
  if (normArtist) {
    const aTok = normalizedTokens(normArtist);
    const eTok = normalizedTokens(normExpArtist);
    const rawTok = normalizedTokens(normRawAll);
    let aOverlap = false;
    aTok.forEach((t) => { if (eTok.has(t)) aOverlap = true; });
    const inRawTitle = aTok.size > 0 && [...aTok].every((t) => rawTok.has(t));

    if (normExpArtist && (normArtist === normExpArtist || normArtist.includes(normExpArtist) || normExpArtist.includes(normArtist) || aOverlap)) {
      score += 30;
    } else if (inRawTitle || normRawAll.includes(normArtist)) {
      score += 26;
    } else if (normExpArtist) {
      score -= 46;
    }
  }

  const variantTags = ['remix', 'live', 'cover', 'karaoke', 'instrumental', 'sped up', 'slowed', 'nightcore', 'acoustic', '8d', 'lofi', 'lo-fi', 'tribute'];
  for (const tag of variantTags) {
    const inCand = normTrack.includes(tag);
    const requested = normRawAll.includes(tag) || normExpArtist.includes(tag);
    if (inCand && !requested) {
      score -= 58;
      break;
    }
  }

  if (parsedLines && hasSynced) {
    if (parsedLines.length < 4 && targetDuration > 35) score -= 85;
    else if (targetDuration > 40) {
      const lastTime = parsedLines[parsedLines.length - 1]?.time || 0;
      if (lastTime > targetDuration + 18) score -= 48;
      else if (lastTime < targetDuration * 0.25) score -= 42;
    }
  }
  return score;
}

function splitMainAndBacking(raw) {
  let working = String(raw || '').trim();
  const backingParts = [];
  let lastRatio = 0;
  const totalLen = Math.max(1, working.length);

  working = working.replace(/(?:\[bg:\s*([^\]]+)\]|<bg>([^<]+)<\/bg>)/gi, (match, g1, g2, offset) => {
    lastRatio = Math.max(lastRatio, offset / totalLen);
    const cleaned = (g1 || g2 || '').trim();
    if (cleaned) backingParts.push(cleaned);
    return '';
  });

  const ignoreTags = new Set(['x2', 'x3', 'x4', '2x', '3x', '4x', 'instrumental', 'intro', 'outro', 'verse', 'chorus', 'bridge', 'solo']);
  working = working.replace(/\(([^()]{1,60})\)/g, (match, inner, offset) => {
    const t = inner.trim();
    const low = t.toLowerCase();
    if (!t || ignoreTags.has(low) || low.startsWith('verse ') || low.startsWith('chorus ')) return match;
    lastRatio = Math.max(lastRatio, offset / Math.max(1, working.length));
    backingParts.push(t);
    return '';
  });

  const mainCleaned = working.replace(/\s{2,}/g, ' ').trim();
  const backingText = backingParts.length ? backingParts.join(' · ') : null;
  const backingIsSuffix = Boolean(mainCleaned) && lastRatio >= 0.42;
  return { main: mainCleaned, backing: backingText, backingIsSuffix };
}

function parseYRC(yrc) {
  const headerRe = /^\[(\d+),(\d+)\]/;
  const wordRe = /\((\d+),(\d+),\d+\)(.*?)(?=\(\d+,\d+,\d+\)|$)/g;
  const credits = ['作词', '作曲', '编曲', '制作人', '混音', '母带', '和声', '吉他', '贝斯', '鼓', '录音'];
  const result = [];

  for (const rawLine of String(yrc || '').split(/\r?\n/)) {
    const trimmed = rawLine.trim();
    if (!trimmed || trimmed.startsWith('{')) continue;
    const hMatch = trimmed.match(headerRe);
    if (!hMatch) continue;
    const body = trimmed.slice(hMatch[0].length);
    const words = [];
    wordRe.lastIndex = 0;
    let m;
    while ((m = wordRe.exec(body)) !== null) {
      if (m[3]) {
        words.push({ time: Number(m[1]) / 1000, duration: Math.max(0.05, Number(m[2]) / 1000), text: m[3] });
      }
    }
    if (!words.length) continue;
    const joined = words.map((w) => w.text).join('').trim();
    if (!joined || credits.some((c) => joined.startsWith(c))) continue;
    const split = splitMainAndBacking(joined);
    result.push({
      time: words[0].time,
      endTime: words[words.length - 1].time + words[words.length - 1].duration,
      mainText: split.main,
      backingText: split.backing,
      backingIsSuffix: split.backingIsSuffix,
      words
    });
  }
  return result.sort((a, b) => a.time - b.time);
}

function parseLRC(lrc) {
  const timeRe = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
  const entries = [];
  for (const rawLine of String(lrc || '').split(/\r?\n/)) {
    const matches = [...rawLine.matchAll(timeRe)];
    if (!matches.length) continue;
    const last = matches[matches.length - 1];
    const text = rawLine.slice(last.index + last[0].length).trim();
    if (!text) continue;
    for (const m of matches) {
      const fracStr = m[3] || '';
      const div = fracStr.length === 3 ? 1000 : (fracStr.length === 2 ? 100 : 10);
      const t = Number(m[1]) * 60 + Number(m[2]) + (fracStr ? Number(fracStr) / div : 0);
      entries.push({ time: t, text });
    }
  }
  entries.sort((a, b) => a.time - b.time);
  const parsed = [];
  for (const entry of entries) {
    const cleanLine = entry.text.replace(/<\d{1,2}:\d{2}(?:[.:]\d{1,3})?>/g, '');
    const split = splitMainAndBacking(cleanLine);
    if (split.main || split.backing) {
      parsed.push({
        time: entry.time,
        mainText: split.main,
        backingText: split.backing,
        backingIsSuffix: split.backingIsSuffix,
        words: []
      });
    }
  }
  return parsed;
}

class DiskLyricsCache {
  constructor(cacheDir) {
    this.cacheDir = cacheDir;
    fs.mkdirSync(this.cacheDir, { recursive: true });
  }

  _pathFor(key) {
    const hex = crypto.createHash('sha256').update(String(key)).digest('hex').slice(0, 16);
    return path.join(this.cacheDir, `${hex}.json`);
  }

  load(cacheKey, fuzzyKey, targetDuration = 0) {
    for (const key of [cacheKey, fuzzyKey]) {
      if (!key) continue;
      try {
        const p = this._pathFor(key);
        if (!fs.existsSync(p)) continue;
        const decoded = JSON.parse(fs.readFileSync(p, 'utf8'));
        if (!decoded?.lines?.length) continue;
        if (key !== cacheKey && targetDuration > 20 && decoded.referenceDuration > 20 && Math.abs(decoded.referenceDuration - targetDuration) > 8) {
          continue;
        }
        return decoded;
      } catch (_) {}
    }
    return null;
  }

  save(result, cacheKey, fuzzyKey) {
    if (!result?.lines?.length || result.sourceName === 'None') return;
    try {
      const data = JSON.stringify(result);
      fs.writeFileSync(this._pathFor(cacheKey), data, 'utf8');
      if (fuzzyKey && fuzzyKey !== cacheKey) {
        fs.writeFileSync(this._pathFor(fuzzyKey), data, 'utf8');
      }
    } catch (_) {}
  }
}

async function fetchJson(url, timeoutMs = 2800, headers = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal, headers });
    if (!res.ok) return null;
    return await res.json();
  } catch (_) {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function fetchLyrics({ title, artist, album = '', duration = 0, cacheDir }) {
  const cacheKey = `${String(title).toLowerCase()}|${String(artist).toLowerCase()}|${Math.round(duration || 0)}`;
  const resolved = resolveExpectedTitleArtist(title, artist);
  const fuzzyKey = `${resolved.title.toLowerCase()}|${resolved.artist.toLowerCase()}`;
  const diskCache = cacheDir ? new DiskLyricsCache(cacheDir) : null;
  if (diskCache) {
    const hit = diskCache.load(cacheKey, fuzzyKey, duration);
    if (hit) return hit;
  }

  const candidates = buildQueryCandidates(title, artist);
  const first = candidates[0] || { track: resolved.title, artist: resolved.artist };
  const requests = [];

  if (first.track && first.artist) {
    const durParam = duration > 15 ? `&duration=${Math.round(duration)}` : '';
    const albParam = album ? `&album_name=${encodeURIComponent(album)}` : '';
    requests.push(fetchJson(`https://lrclib.net/api/get?track_name=${encodeURIComponent(first.track)}&artist_name=${encodeURIComponent(first.artist)}${albParam}${durParam}`).then((j) => j ? [j] : []));
    requests.push(fetchJson(`https://lrclib.net/api/search?track_name=${encodeURIComponent(first.track)}&artist_name=${encodeURIComponent(first.artist)}`));
  }
  const qStr = first.artist ? `${first.track} ${first.artist}` : first.track;
  if (qStr) {
    requests.push(fetchJson(`https://lrclib.net/api/search?q=${encodeURIComponent(qStr)}`));
  }

  const batches = await Promise.all(requests);
  const pool = [];

  for (const arr of batches) {
    if (!Array.isArray(arr)) continue;
    for (const item of arr.slice(0, 10)) {
      if (item.syncedLyrics) {
        const lines = parseLRC(item.syncedLyrics);
        if (!lines.length) continue;
        const sc = scoreCandidate({
          trackName: item.trackName || '',
          artistName: item.artistName || '',
          rawInputTitle: title,
          expectedTitle: resolved.title,
          expectedArtist: resolved.artist,
          refDuration: item.duration || duration,
          targetDuration: duration,
          hasSynced: true,
          hasWordTimings: false,
          parsedLines: lines
        });
        pool.push({ lines, sourceName: 'LRCLIB', isEstimated: false, hasWordTimings: false, referenceDuration: item.duration || duration, matchScore: sc });
      }
    }
  }

  // Concurrent NetEase YRC / LRC search
  if (qStr) {
    const ne = await fetchJson(`https://music.163.com/api/search/get?s=${encodeURIComponent(qStr)}&type=1&limit=5`, 2800, { 'User-Agent': 'Mozilla/5.0' });
    const songs = ne?.result?.songs || [];
    for (const song of songs.slice(0, 2)) {
      const sDur = (song.duration || 0) / 1000;
      const sArtist = song.artists?.[0]?.name || '';
      const payload = await fetchJson(`https://music.163.com/api/song/lyric?os=pc&id=${song.id}&lv=-1&yv=-1`, 2600, { 'User-Agent': 'Mozilla/5.0' });
      const yrcRaw = payload?.yrc?.lyric;
      const lrcRaw = payload?.lrc?.lyric;
      if (yrcRaw) {
        const yrcLines = parseYRC(yrcRaw);
        if (yrcLines.length) {
          const sc = scoreCandidate({ trackName: song.name || '', artistName: sArtist, rawInputTitle: title, expectedTitle: resolved.title, expectedArtist: resolved.artist, refDuration: sDur || duration, targetDuration: duration, hasSynced: true, hasWordTimings: true, parsedLines: yrcLines });
          pool.push({ lines: yrcLines, sourceName: 'NetEase YRC', isEstimated: false, hasWordTimings: true, referenceDuration: sDur || duration, matchScore: sc });
        }
      } else if (lrcRaw) {
        const lrcLines = parseLRC(lrcRaw);
        if (lrcLines.length) {
          const sc = scoreCandidate({ trackName: song.name || '', artistName: sArtist, rawInputTitle: title, expectedTitle: resolved.title, expectedArtist: resolved.artist, refDuration: sDur || duration, targetDuration: duration, hasSynced: true, hasWordTimings: false, parsedLines: lrcLines });
          pool.push({ lines: lrcLines, sourceName: 'NetEase LRC', isEstimated: false, hasWordTimings: false, referenceDuration: sDur || duration, matchScore: sc });
        }
      }
    }
  }

  const validSynced = pool.filter((p) => !p.isEstimated && p.matchScore >= 65);
  validSynced.sort((a, b) => b.matchScore - a.matchScore);
  const picked = validSynced[0] || { lines: [], sourceName: 'None', isEstimated: false, hasWordTimings: false, referenceDuration: duration };
  if (picked.lines.length && diskCache) {
    diskCache.save(picked, cacheKey, fuzzyKey);
  }
  return picked;
}

function computeLineProgress(line, elapsed, nextLineTime) {
  if (!line) return 1;
  if (line.words && line.words.length) {
    const totalChars = Math.max(1, line.words.reduce((acc, w) => acc + w.text.length, 0));
    let before = 0;
    for (let i = 0; i < line.words.length; i++) {
      const w = line.words[i];
      const end = w.time + Math.max(0.07, w.duration);
      if (elapsed < w.time) return before / totalChars;
      if (elapsed <= end) {
        const frac = (elapsed - w.time) / Math.max(0.07, w.duration);
        return Math.min(1, Math.max(0, (before + frac * w.text.length) / totalChars));
      }
      if (i + 1 < line.words.length && elapsed < line.words[i + 1].time) {
        return (before + w.text.length) / totalChars;
      }
      before += w.text.length;
    }
    return 1;
  }
  const gap = Math.max(0.5, nextLineTime - line.time);
  const span = Math.min(gap * 0.86, Math.max(1.0, (line.mainText || '').length * 0.085));
  return Math.min(1, Math.max(0, (elapsed - line.time) / Math.max(0.4, span)));
}

module.exports = {
  normalizeDashSeparators,
  cleanTitle,
  cleanArtist,
  stripFeaturing,
  isRTLScript,
  romanizeKoreanHangul,
  romanizeText,
  resolveExpectedTitleArtist,
  buildQueryCandidates,
  scoreCandidate,
  splitMainAndBacking,
  parseYRC,
  parseLRC,
  DiskLyricsCache,
  fetchLyrics,
  computeLineProgress
};

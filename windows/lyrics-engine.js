'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {
  findActiveLineIndex,
  computeLineProgress,
  computeFrameState
} = require('./renderer/lyrics-timing');

function normalizeDashSeparators(text) {
  return String(text || '').replace(/\s+[\u2013\u2014\u2015~]\s+/g, ' - ');
}

function cleanTitle(raw) {
  let s = String(raw || '');
  const streamMetaAfterSep = '(?:Official|Lyrics?|Lirik|MV|M\\/V|Music\\s*Video|Audio|Video|Live|Topic|Visualizer|HD|4K|Sub(?:titles?)?|Karaoke|Full|Prod\\.?)';
  s = s.replace(new RegExp(`\\s*\\|\\s*(?=${streamMetaAfterSep}\\b).*$`, 'i'), '');
  s = s.replace(new RegExp(`\\s*\\/\\/\\s*(?=${streamMetaAfterSep}\\b).*$`, 'i'), '');
  s = s.replace(/\s*[(\[]\s*(Official\s*(Music\s*)?Video|Official\s*Audio|Official\s*MV|Official\s*Lyric\s*Video|Lyric\s*Video|Lyrics?\s*Video|Lyrics?|Lirik(\s*Terjemahan)?|Sub\s*(Indo|Eng|Indonesia|English)|Audio(\s*Only)?|Visualizer|M\/?V|HD|4K|Live(\s*Performance)?|Explicit|Clean(\s*Version)?|Single\s*Version|Radio\s*Edit|Album\s*Version|Remaster(ed)?(\s*\d+)?|Slowed(\s*\+\s*Reverb)?|Sped\s*Up|Speed\s*Up|Karaoke|Color\s*Coded|Prod\.?\s*by\s+[^)\]]+)\s*[)\]]/gi, '');
  s = s.replace(/^\s*\[(MV|M\/V|Lyrics?|Audio|Official)\]\s*/i, '');
  s = s.replace(/\s*[-\u2013\u2014]\s*(Official\s*(Music\s*)?Video|Official\s*Audio|Official\s*MV|Lyric\s*Video|Lyrics?|Lirik(\s*Terjemahan)?|Audio(\s*Only)?|Remaster(ed)?(\s*\d+)?|Single\s*Version|Radio\s*Edit|YouTube)\s*$/i, '');
  s = s.replace(/(?:\s+|(?<=[\u300D\u300F\)\]]))(Official\s*(Music\s*)?Video|Official\s*Audio|Official\s*MV|Music\s*Video)\s*$/i, '');

  // Unwrap 「...」 / 『...』 only when outside text is a short uploader/artist prefix (e.g. "YOASOBI「夜に駆ける」"),
  // never when a valid main title precedes or follows the quote.
  const jpQuote = s.match(/([\u300C\u300E])([^\u300D\u300F]+)[\u300D\u300F]/);
  if (jpQuote && jpQuote[2] && jpQuote[2].trim().length >= 2) {
    const idx = jpQuote.index;
    const prefix = s.slice(0, idx).trim();
    const suffix = s.slice(idx + jpQuote[0].length).trim();
    const prefixWords = prefix ? prefix.split(/\s+/).filter(Boolean) : [];
    const hasDashSep = /\s[-–—]\s/.test(prefix) || /\s[-–—]\s/.test(suffix);
    const quoteInner = jpQuote[2].trim();
    const quoteLooksLikeTag = /^(ver\.?|version|live|remix|cover|inst\.?|instrumental|acoustic|op|ed|ost|part\s*\d+|part\s*[ivx]+)$/i.test(quoteInner);
    if (!hasDashSep && suffix.length === 0 && prefixWords.length <= 2 && !quoteLooksLikeTag) {
      s = quoteInner;
    }
  }

  return normalizeDashSeparators(s).trim();
}

function cleanArtist(raw) {
  let s = String(raw || '')
    .replace(/\s*[-\u2013\u2014]\s*Topic$/i, '')
    .replace(/\s*VEVO$/i, '')
    .replace(/\s*(Official|Channel)$/i, '')
    .trim();

  // Strip only collaboration suffixes (feat./ft./featuring), never "&" in band names
  s = s.replace(/\s*[(\[]?\s*\b(?:feat\.?|ft\.?|featuring)\b.*$/i, '').trim();

  // Split comma only when NOT a known single-entity comma pattern like "Earth, Wind & Fire", "Tyler, The Creator", ", Jr.", etc.
  if (s.includes(',')) {
    const isSingleCommaEntity =
      /^[^,]+,\s+[^,]+\s+&\s+[^,]+$/i.test(s) ||
      /^[^,]+,\s+(The|Jr\.?|Sr\.?|Inc\.?|Ltd\.?|LLC)\b/i.test(s);
    if (!isSingleCommaEntity) {
      s = s.split(',')[0].trim();
    }
  }
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

function scriptConsistencyScore({ lines, trackName, artistName, rawInputTitle, expectedTitle, expectedArtist }) {
  const metaText = `${rawInputTitle} ${expectedTitle} ${expectedArtist} ${trackName} ${artistName}`;
  const expectsJP = /[\u3040-\u30FF]/.test(metaText);
  const expectsKO = /[\uAC00-\uD7A3]/.test(metaText);
  const expectsCJK = /[\u4E00-\u9FFF]/.test(metaText);
  const sample = (lines || []).slice(0, 16).map((l) => l.mainText || '').join(' ');
  if (!sample) return 0;

  const hasJP = /[\u3040-\u30FF]/.test(sample);
  const hasKO = /[\uAC00-\uD7A3]/.test(sample);
  const cjkCount = (sample.match(/[\u4E00-\u9FFF]/g) || []).length;
  const nonLatin = (sample.match(/[^\u0000-\u024F\s\p{P}\p{N}]/gu) || []).length;
  const alphaCount = Math.max(1, (sample.match(/\p{L}/gu) || []).length);
  const ratio = nonLatin / alphaCount;
  const lower = ` ${sample.toLowerCase()} `;
  const enMarkers = [' the ', ' and ', ' you ', ' my ', ' your ', ' into ', ' night ', ' love ', ' with ', ' that '];
  const enHits = enMarkers.filter((w) => lower.includes(w)).length;

  if (expectsJP) {
    if (hasJP) return 36;
    if (enHits >= 3 && !hasJP && cjkCount === 0) return -150;
    if (ratio < 0.05) return -65;
  } else if (expectsKO) {
    if (hasKO) return 36;
    if (enHits >= 3 && !hasKO) return -150;
    if (ratio < 0.05) return -65;
  } else if (expectsCJK) {
    if (cjkCount >= 8) return 30;
    if (enHits >= 3 && cjkCount === 0) return -140;
  } else if (ratio >= 0.45 && (hasJP || hasKO || cjkCount >= 8)) {
    return -140;
  }
  return 0;
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
  const expTokCount = normalizedTokens(normExpTitle).size;

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
      score -= (expTokCount <= 2) ? 105 : 78;
    }
  }

  const variantTags = ['remix', 'live', 'cover', 'karaoke', 'instrumental', '(inst', 'inst)', 'off vocal', 'sped up', 'spedup', 'slowed', 'nightcore', 'acoustic', '8d', 'lofi', 'lo-fi', 'tribute', 'english ver', 'english version', 'eng ver', 'english cover', 'indonesian ver', 'tv size', 'short ver'];
  for (const tag of variantTags) {
    const inCand = normTrack.includes(tag);
    const requested = normRawAll.includes(tag) || normExpArtist.includes(tag);
    if (inCand && !requested) {
      score -= 68;
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
    score += scriptConsistencyScore({ lines: parsedLines, trackName, artistName, rawInputTitle, expectedTitle, expectedArtist });
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
  const adLibPattern = /^(?:oh+|ooh+|yeah+|yea+|ah+|uh+|uh-huh|m+m+|h+m+|hey+|la+|na+|da+|wh?oa+h*|ha+|ayy+|yo+)(?:[\s,!~-]+(?:oh+|ooh+|yeah+|yea+|ah+|uh+|uh-huh|m+m+|h+m+|hey+|la+|na+|da+|wh?oa+h*|ha+|ayy+|yo+))*$/i;

  const parenMatches = [...working.matchAll(/\(([^()]{1,60})\)/g)];
  let nextWorking = '';
  let cursor = 0;
  for (const m of parenMatches) {
    const idx = m.index;
    const matchStr = m[0];
    const t = m[1].trim();
    const low = t.toLowerCase();
    const before = working.slice(0, idx).trim();
    const after = working.slice(idx + matchStr.length).trim();

    const isMetadataTag = !t || ignoreTags.has(low) || low.startsWith('verse ') || low.startsWith('chorus ');
    const isStandaloneLine = before.length === 0 && after.length === 0;
    const isEndOfLineBacking = before.length > 0 && /^[\s.,!?~♪"]*$/.test(after);
    const isAdLib = adLibPattern.test(t);

    if (!isMetadataTag && (isStandaloneLine || isEndOfLineBacking || isAdLib)) {
      lastRatio = Math.max(lastRatio, idx / Math.max(1, working.length));
      backingParts.push(t);
      nextWorking += working.slice(cursor, idx);
    } else {
      nextWorking += working.slice(cursor, idx + matchStr.length);
    }
    cursor = idx + matchStr.length;
  }
  nextWorking += working.slice(cursor);
  working = nextWorking;

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

function parseEnhancedLRCWords(lineTime, rawText, nextEntryTime) {
  const tagRe = /<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>/g;
  const tags = [...String(rawText || '').matchAll(tagRe)];
  if (!tags.length) return [];

  const segments = [];
  const prefix = rawText.slice(0, tags[0].index);
  const toSeconds = (m) => {
    const fracStr = m[3] || '';
    const div = fracStr.length === 3 ? 1000 : (fracStr.length === 2 ? 100 : 10);
    return Number(m[1]) * 60 + Number(m[2]) + (fracStr ? Number(fracStr) / div : 0);
  };

  const firstTagTime = toSeconds(tags[0]);
  if (prefix) {
    segments.push({ time: lineTime, nextTime: firstTagTime, text: prefix });
  }
  for (let i = 0; i < tags.length; i++) {
    const start = toSeconds(tags[i]);
    const textStart = tags[i].index + tags[i][0].length;
    const textEnd = (i + 1 < tags.length) ? tags[i + 1].index : rawText.length;
    const segText = rawText.slice(textStart, textEnd);
    const nextT = (i + 1 < tags.length) ? toSeconds(tags[i + 1]) : null;
    if (segText) {
      segments.push({ time: start, nextTime: nextT, text: segText });
    }
  }

  return segments.map((seg, idx) => {
    let dur = 0.35;
    if (seg.nextTime !== null && seg.nextTime > seg.time) {
      dur = seg.nextTime - seg.time;
    } else if (typeof nextEntryTime === 'number' && nextEntryTime > seg.time) {
      dur = Math.min(nextEntryTime - seg.time, Math.max(0.25, seg.text.trim().length * 0.09));
    } else {
      dur = Math.max(0.22, seg.text.trim().length * 0.09);
    }
    return {
      time: seg.time,
      duration: Math.max(0.05, dur),
      text: seg.text
    };
  });
}

function parseLRC(lrc) {
  const timeRe = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
  const entries = [];
  for (const rawLine of String(lrc || '').split(/\r?\n/)) {
    const matches = [...rawLine.matchAll(timeRe)];
    if (!matches.length) continue;
    const last = matches[matches.length - 1];
    const text = rawLine.slice(last.index + last[0].length).trim();
    const isBreak = text.length === 0;
    for (const m of matches) {
      const fracStr = m[3] || '';
      const div = fracStr.length === 3 ? 1000 : (fracStr.length === 2 ? 100 : 10);
      const t = Number(m[1]) * 60 + Number(m[2]) + (fracStr ? Number(fracStr) / div : 0);
      entries.push({ time: t, text, isBreak });
    }
  }
  entries.sort((a, b) => a.time - b.time);
  const parsed = [];
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    if (entry.isBreak) {
      if (parsed.length > 0 && parsed[parsed.length - 1].endTime == null) {
        const prev = parsed[parsed.length - 1];
        prev.endTime = Math.max(prev.time + 0.35, entry.time);
      }
      continue;
    }
    const nextEntryTime = (i + 1 < entries.length) ? entries[i + 1].time : null;
    const words = parseEnhancedLRCWords(entry.time, entry.text, nextEntryTime);
    const cleanLine = entry.text.replace(/<\d{1,2}:\d{2}(?:[.:]\d{1,3})?>/g, '');
    const split = splitMainAndBacking(cleanLine);
    if (split.main || split.backing) {
      const endTime = words.length
        ? words[words.length - 1].time + words[words.length - 1].duration
        : undefined;
      parsed.push({
        time: entry.time,
        endTime,
        mainText: split.main,
        backingText: split.backing,
        backingIsSuffix: split.backingIsSuffix,
        words
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
    const hex = crypto.createHash('sha256').update(String(key)).digest('hex').slice(0, 32);
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

  remove(cacheKey, fuzzyKey) {
    let removed = false;
    for (const key of [cacheKey, fuzzyKey]) {
      if (!key) continue;
      try {
        const p = this._pathFor(key);
        if (fs.existsSync(p)) {
          fs.unlinkSync(p);
          removed = true;
        }
      } catch (_) {}
    }
    return removed;
  }
}

function buildTrackCacheKeys(title, artist, duration = 0) {
  const cacheKey = `${String(title || '').toLowerCase()}|${String(artist || '').toLowerCase()}|${Math.round(Number(duration) || 0)}`;
  const resolved = resolveExpectedTitleArtist(title, artist);
  const fuzzyKey = `${resolved.title.toLowerCase()}|${resolved.artist.toLowerCase()}`;
  return { cacheKey, fuzzyKey, resolved };
}

function clearTrackCache({ title, artist = '', duration = 0, cacheDir }) {
  if (!cacheDir || !title) return false;
  const { cacheKey, fuzzyKey } = buildTrackCacheKeys(title, artist, duration);
  const diskCache = new DiskLyricsCache(cacheDir);
  return diskCache.remove(cacheKey, fuzzyKey);
}

async function fetchText(url, timeoutMs = 2800, headers = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal, headers });
    if (!res.ok) return null;
    return await res.text();
  } catch (_) {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function fetchJson(url, timeoutMs = 2800, headers = {}) {
  const txt = await fetchText(url, timeoutMs, headers);
  if (!txt) return null;
  try {
    return JSON.parse(txt);
  } catch (_) {
    return null;
  }
}

function parseKuwoSearchResponse(body) {
  const raw = String(body || '').trim();
  if (!raw) return [];

  // Attempt strict JSON parse first
  try {
    const parsed = JSON.parse(raw);
    const list = parsed?.abslist || parsed?.data?.abslist;
    if (Array.isArray(list)) {
      return list
        .filter((it) => it && String(it.MUSICRID || '').includes('MUSIC_'))
        .map((it) => ({
          rid: String(it.MUSICRID).replace(/^MUSIC_/i, ''),
          song: String(it.SONGNAME || it.NAME || ''),
          artist: String(it.ARTIST || '').replace(/&/g, ', '),
          refDur: Number(it.DURATION || 0)
        }));
    }
  } catch (_) {}

  // Fallback for JS-like single-quoted/unquoted abslist objects
  const items = [];
  const objMatches = raw.match(/\{[^{}]*(?:'MUSICRID'|"MUSICRID"|MUSICRID\s*:)[^{}]*\}/gi) || [];
  const readField = (objStr, key) => {
    const m = objStr.match(new RegExp(`(?:['"]?${key}['"]?)\\s*:\\s*(?:'([^']*)'|"([^"]*)"|([^,}\\s]+))`, 'i'));
    return m ? (m[1] ?? m[2] ?? m[3] ?? '') : '';
  };
  for (const chunk of objMatches) {
    const ridRaw = readField(chunk, 'MUSICRID');
    const ridM = String(ridRaw).match(/MUSIC_(\d+)/i);
    if (!ridM) continue;
    items.push({
      rid: ridM[1],
      song: readField(chunk, 'SONGNAME') || readField(chunk, 'NAME'),
      artist: String(readField(chunk, 'ARTIST') || '').replace(/&/g, ', '),
      refDur: Number(readField(chunk, 'DURATION') || 0)
    });
  }
  return items;
}

function mapKuwoLrcList(lrclist) {
  if (!Array.isArray(lrclist) || !lrclist.length) return [];
  const entries = [];
  for (let i = 0; i < lrclist.length; i++) {
    const txt = String(lrclist[i]?.lineLyric || '').trim();
    const tVal = Number(lrclist[i]?.time);
    if (!Number.isFinite(tVal) || tVal < 0) continue;
    if (i === 0 && (txt.includes('词：') || txt.includes('曲：') || txt.includes(' - '))) continue;
    entries.push({ time: tVal, txt });
  }
  entries.sort((a, b) => a.time - b.time);

  const lines = [];
  for (const row of entries) {
    if (!row.txt) {
      if (lines.length > 0 && lines[lines.length - 1].endTime == null) {
        const prev = lines[lines.length - 1];
        prev.endTime = Math.max(prev.time + 0.35, row.time);
      }
      continue;
    }
    const split = splitMainAndBacking(row.txt);
    if (split.main || split.backing) {
      lines.push({
        time: row.time,
        endTime: undefined,
        mainText: split.main,
        backingText: split.backing,
        backingIsSuffix: split.backingIsSuffix,
        words: []
      });
    }
  }
  return lines;
}

async function fetchKuwoForCandidate(cand, { title, resolvedTitle, resolvedArtist, duration }) {
  const kw = cand.artist ? `${cand.track} ${cand.artist}` : cand.track;
  if (!kw) return [];
  const body = await fetchText(`https://search.kuwo.cn/r.s?all=${encodeURIComponent(kw)}&ft=music&pn=0&rn=4&rformat=json&encoding=utf8`, 2800, { 'User-Agent': 'Mozilla/5.0' });
  if (!body) return [];
  const rawItems = parseKuwoSearchResponse(body);
  const items = rawItems.map((it) => {
    const song = it.song || resolvedTitle;
    const artist = it.artist || resolvedArtist;
    const refDur = it.refDur || duration;
    const pre = scoreCandidate({ trackName: song, artistName: artist, rawInputTitle: title, expectedTitle: resolvedTitle, expectedArtist: resolvedArtist, refDuration: refDur, targetDuration: duration, hasSynced: true, hasWordTimings: false });
    return { rid: it.rid, song, artist, refDur, pre };
  });
  items.sort((a, b) => b.pre - a.pre);
  const out = [];
  for (const item of items.slice(0, 2)) {
    const payload = await fetchJson(`https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=${item.rid}`, 2600, { 'User-Agent': 'Mozilla/5.0' });
    const lrclist = payload?.data?.lrclist || [];
    const parsed = mapKuwoLrcList(lrclist);
    if (!parsed.length) continue;
    const sc = scoreCandidate({ trackName: item.song, artistName: item.artist, rawInputTitle: title, expectedTitle: resolvedTitle, expectedArtist: resolvedArtist, refDuration: item.refDur, targetDuration: duration, hasSynced: true, hasWordTimings: false, parsedLines: parsed });
    out.push({ lines: parsed, sourceName: 'Kuwo LRC', isEstimated: false, hasWordTimings: false, referenceDuration: item.refDur, matchScore: sc });
  }
  return out;
}

async function fetchLyrics({ title, artist, album = '', duration = 0, cacheDir, forceRefresh = false }) {
  const { cacheKey, fuzzyKey, resolved } = buildTrackCacheKeys(title, artist, duration);
  const diskCache = cacheDir ? new DiskLyricsCache(cacheDir) : null;
  if (diskCache) {
    if (forceRefresh) {
      diskCache.remove(cacheKey, fuzzyKey);
    } else {
      const hit = diskCache.load(cacheKey, fuzzyKey, duration);
      if (hit) return hit;
    }
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

  // Concurrent NetEase YRC / LRC + Kugou LRC multi-source racing
  if (qStr) {
    const nePromise = (async () => {
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
    })();

    const kgPromise = (async () => {
      const kw = first.artist ? `${first.artist} - ${first.track}` : first.track;
      const kg = await fetchJson(`https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=${encodeURIComponent(kw)}&duration=${Math.round((duration || 0) * 1000)}`, 2800, { 'User-Agent': 'Mozilla/5.0' });
      const cands = kg?.candidates || [];
      for (const item of cands.slice(0, 2)) {
        if (!item?.id || !item?.accesskey) continue;
        const dl = await fetchJson(`https://lyrics.kugou.com/download?ver=1&client=pc&id=${item.id}&accesskey=${item.accesskey}&fmt=lrc&charset=utf8`, 2600, { 'User-Agent': 'Mozilla/5.0' });
        if (!dl?.content) continue;
        const rawLrc = Buffer.from(dl.content, 'base64').toString('utf8').replace(/^\uFEFF/, '');
        const lines = parseLRC(rawLrc);
        if (!lines.length) continue;
        const refDur = (Number(item.duration) || 0) / 1000 || duration;
        const sc = scoreCandidate({
          trackName: item.song || resolved.title,
          artistName: item.singer || resolved.artist,
          rawInputTitle: title,
          expectedTitle: resolved.title,
          expectedArtist: resolved.artist,
          refDuration: refDur,
          targetDuration: duration,
          hasSynced: true,
          hasWordTimings: false,
          parsedLines: lines
        });
        pool.push({ lines, sourceName: 'Kugou LRC', isEstimated: false, hasWordTimings: false, referenceDuration: refDur, matchScore: sc });
      }
    })();

    const kwPromise = (async () => {
      const hits = await fetchKuwoForCandidate(first, { title, resolvedTitle: resolved.title, resolvedArtist: resolved.artist, duration });
      pool.push(...hits);
    })();

    await Promise.all([nePromise, kgPromise, kwPromise]);
  }

  let validSynced = pool.filter((p) => !p.isEstimated && p.matchScore >= 65);

  // Canonical Metadata Resolver (iTunes + Deezer) for Romanized / misspelled tracks
  if (!validSynced.length && qStr) {
    const enc = encodeURIComponent(qStr);
    const [itJson, dzJson] = await Promise.all([
      fetchJson(`https://itunes.apple.com/search?term=${enc}&media=music&entity=song&limit=4`, 2600),
      fetchJson(`https://api.deezer.com/search?q=${enc}&limit=4`, 2600)
    ]);
    const meta = [];
    for (const r of (itJson?.results || [])) {
      const tn = cleanTitle(r.trackName || '');
      const an = cleanArtist(r.artistName || '');
      if (tn && an) meta.push({ track: tn, artist: an, dur: (r.trackTimeMillis || 0) / 1000 });
    }
    for (const r of (dzJson?.data || [])) {
      const tn = cleanTitle(r.title || '');
      const an = cleanArtist(r.artist?.name || '');
      if (tn && an) meta.push({ track: tn, artist: an, dur: Number(r.duration || 0) });
    }
    meta.sort((a, b) => scoreCandidate({ trackName: b.track, artistName: b.artist, rawInputTitle: title, expectedTitle: resolved.title, expectedArtist: resolved.artist, refDuration: b.dur, targetDuration: duration, hasSynced: true, hasWordTimings: false }) - scoreCandidate({ trackName: a.track, artistName: a.artist, rawInputTitle: title, expectedTitle: resolved.title, expectedArtist: resolved.artist, refDuration: a.dur, targetDuration: duration, hasSynced: true, hasWordTimings: false }));
    if (meta[0]) {
      const top = meta[0];
      const [lrcCanon, kwCanon] = await Promise.all([
        fetchJson(`https://lrclib.net/api/get?track_name=${encodeURIComponent(top.track)}&artist_name=${encodeURIComponent(top.artist)}`, 2600),
        fetchKuwoForCandidate(top, { title, resolvedTitle: top.track, resolvedArtist: top.artist, duration })
      ]);
      pool.push(...kwCanon);
      if (lrcCanon?.syncedLyrics) {
        const lines = parseLRC(lrcCanon.syncedLyrics);
        if (lines.length) {
          const sc = scoreCandidate({ trackName: lrcCanon.trackName || top.track, artistName: lrcCanon.artistName || top.artist, rawInputTitle: title, expectedTitle: top.track, expectedArtist: top.artist, refDuration: lrcCanon.duration || duration, targetDuration: duration, hasSynced: true, hasWordTimings: false, parsedLines: lines });
          pool.push({ lines, sourceName: 'LRCLIB', isEstimated: false, hasWordTimings: false, referenceDuration: lrcCanon.duration || duration, matchScore: sc });
        }
      }
      validSynced = pool.filter((p) => !p.isEstimated && p.matchScore >= 65);
    }
  }

  validSynced.sort((a, b) => b.matchScore - a.matchScore);
  const picked = validSynced[0] || { lines: [], sourceName: 'None', isEstimated: false, hasWordTimings: false, referenceDuration: duration };
  if (picked.lines.length && diskCache) {
    diskCache.save(picked, cacheKey, fuzzyKey);
  }
  return picked;
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
  parseKuwoSearchResponse,
  mapKuwoLrcList,
  DiskLyricsCache,
  buildTrackCacheKeys,
  clearTrackCache,
  fetchLyrics,
  findActiveLineIndex,
  computeLineProgress,
  computeFrameState
};

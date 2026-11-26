'use strict';

function cleanTitle(raw) {
  let s = String(raw || '');
  const jp = s.match(/[\u300C\u300E]([^\u300D\u300F]+)[\u300D\u300F]/);
  if (jp && jp[1]) s = jp[1].trim();
  s = s.replace(/\s*[(\[]\s*(Official\s*(Music\s*)?Video|Official\s*Audio|Lyric\s*Video|Lyrics?|Lirik|Audio|M\/?V|HD|4K|Explicit|Remaster(ed)?(\s*\d+)?)\s*[)\]]/gi, '');
  s = s.replace(/\s*[-\u2013\u2014]\s*(Official.*|Lyric.*|YouTube)$/i, '');
  return s.replace(/\s+[\u2013\u2014~]\s+/g, ' - ').trim();
}

function cleanArtist(raw) {
  return String(raw || '').replace(/\s*[-\u2013\u2014]\s*Topic$/i, '').replace(/\s*VEVO$/i, '').trim();
}

function parseLRC(lrc) {
  const re = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
  const out = [];
  for (const row of String(lrc || '').split(/\r?\n/)) {
    const matches = [...row.matchAll(re)];
    if (!matches.length) continue;
    const text = row.slice(matches[matches.length - 1].index + matches[matches.length - 1][0].length).replace(/<\d+:\d+(?:[.:]\d+)?>/g, '').trim();
    if (!text) continue;
    for (const m of matches) {
      const f = m[3] || '';
      const t = Number(m[1]) * 60 + Number(m[2]) + (f ? Number(f) / (f.length === 3 ? 1000 : f.length === 2 ? 100 : 10) : 0);
      out.push({ time: t, text });
    }
  }
  return out.sort((a, b) => a.time - b.time);
}

async function searchLyrics({ title, artist, duration }) {
  let t = cleanTitle(title);
  let a = cleanArtist(artist);
  if (t.includes(' - ') && !a) {
    const parts = t.split(' - ');
    a = cleanArtist(parts[0]);
    t = cleanTitle(parts.slice(1).join(' - '));
  }
  const cacheKey = `nl_ext_${t.toLowerCase()}|${a.toLowerCase()}`;
  const cached = await chrome.storage.local.get(cacheKey);
  if (cached && cached[cacheKey]) return cached[cacheKey];

  const urls = [];
  if (t && a) {
    const dur = duration > 15 ? `&duration=${Math.round(duration)}` : '';
    urls.push(`https://lrclib.net/api/get?track_name=${encodeURIComponent(t)}&artist_name=${encodeURIComponent(a)}${dur}`);
    urls.push(`https://lrclib.net/api/search?q=${encodeURIComponent(`${t} ${a}`)}`);
  } else if (t) {
    urls.push(`https://lrclib.net/api/search?q=${encodeURIComponent(t)}`);
  }

  for (const url of urls) {
    try {
      const res = await fetch(url);
      if (!res.ok) continue;
      const json = await res.json();
      const items = Array.isArray(json) ? json : [json];
      const match = items.find((item) => item && item.syncedLyrics && (!duration || !item.duration || Math.abs(item.duration - duration) <= 10));
      if (match) {
        const lines = parseLRC(match.syncedLyrics);
        if (lines.length) {
          const payload = { lines, trackName: match.trackName || t, artistName: match.artistName || a };
          chrome.storage.local.set({ [cacheKey]: payload });
          return payload;
        }
      }
    } catch (_) {}
  }
  return { lines: [], trackName: t, artistName: a };
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg && msg.type === 'FETCH_LYRICS') {
    searchLyrics(msg.payload).then(sendResponse);
    return true;
  }
  return false;
});

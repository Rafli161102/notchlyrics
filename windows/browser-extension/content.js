(() => {
  'use strict';

  const HOST_ID = 'notchlyrics-extension-host';
  if (document.getElementById(HOST_ID)) return;

  const host = document.createElement('div');
  host.id = HOST_ID;
  host.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:2147483647;pointer-events:none;display:flex;justify-content:center;';
  document.documentElement.appendChild(host);

  const shadow = host.attachShadow({ mode: 'open' });
  shadow.innerHTML = `
    <style>
      .notch {
        pointer-events: auto;
        width: 336px; height: 48px;
        background: #000000; color: #ffffff;
        border: 0.5px solid rgba(255,255,255,0.14); border-top: none;
        border-radius: 0 0 13px 13px;
        padding: 6px 14px 8px;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
        display: flex; flex-direction: column; justify-content: center;
        position: relative; overflow: hidden; box-sizing: border-box;
        transition: width 260ms cubic-bezier(0.22,1,0.36,1), height 260ms cubic-bezier(0.22,1,0.36,1), border-radius 260ms cubic-bezier(0.22,1,0.36,1);
      }
      .notch.expanded { width: 544px; height: 110px; border-radius: 0 0 21px 21px; padding: 8px 16px; justify-content: space-between; }
      .upper { display: flex; align-items: center; gap: 0; flex: 1 1 auto; }
      .notch.expanded .upper { gap: 13px; }
      .art { width: 0; height: 0; opacity: 0; border-radius: 10px; object-fit: cover; transition: opacity 200ms ease, width 200ms ease; }
      .notch.expanded .art.show { width: 52px; height: 52px; opacity: 1; }
      .lyric { margin: 0; font-size: 13px; font-weight: 600; line-height: 1.24; text-align: center; white-space: normal; word-break: break-word; color: #ffffff; flex: 1; }
      .notch.expanded .lyric { text-align: left; }
      .lower { display: none; align-items: center; gap: 10px; height: 34px; border-top: 0.5px solid rgba(255,255,255,0.14); padding-top: 4px; }
      .notch.expanded .lower { display: flex; }
      .meta { flex: 1; min-width: 0; }
      .title, .sub { margin: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .title { font-size: 12px; font-weight: 600; }
      .sub { font-size: 10.5px; color: rgba(255,255,255,0.7); }
      .time { font-size: 10.5px; font-variant-numeric: tabular-nums; color: rgba(255,255,255,0.72); white-space: nowrap; }
      .ctrls { display: flex; gap: 6px; }
      button { width: 28px; height: 28px; border-radius: 8px; border: 0.5px solid rgba(255,255,255,0.15); background: rgba(255,255,255,0.08); color: #fff; cursor: pointer; font-size: 10px; }
      button:hover { background: rgba(255,255,255,0.2); }
      .prog { position: absolute; left: 14px; right: 14px; bottom: 2px; height: 1.5px; background: rgba(255,255,255,0.16); }
      .prog span { display: block; height: 100%; width: 0; background: #f4d06f; }
    </style>
    <div id="nl-root" class="notch">
      <div class="upper">
        <img id="nl-art" class="art" alt="">
        <p id="nl-lyric" class="lyric">NotchLyrics ready</p>
      </div>
      <div class="lower">
        <div class="meta">
          <p id="nl-title" class="title"></p>
          <p id="nl-sub" class="sub"></p>
        </div>
        <span id="nl-time" class="time">00:00 / 00:00</span>
        <div class="ctrls">
          <button id="nl-prev" title="Previous">&#9664;&#9664;</button>
          <button id="nl-play" title="Play / Pause">&#9654;</button>
          <button id="nl-next" title="Next">&#9654;&#9654;</button>
        </div>
      </div>
      <div class="prog"><span id="nl-fill"></span></div>
    </div>
  `;

  const root = shadow.getElementById('nl-root');
  const art = shadow.getElementById('nl-art');
  const lyricEl = shadow.getElementById('nl-lyric');
  const titleEl = shadow.getElementById('nl-title');
  const subEl = shadow.getElementById('nl-sub');
  const timeEl = shadow.getElementById('nl-time');
  const playBtn = shadow.getElementById('nl-play');
  const fillEl = shadow.getElementById('nl-fill');

  let collapseTimer = null;
  root.addEventListener('mouseenter', () => {
    if (collapseTimer) { clearTimeout(collapseTimer); collapseTimer = null; }
    root.classList.add('expanded');
  });
  root.addEventListener('mouseleave', () => {
    collapseTimer = setTimeout(() => root.classList.remove('expanded'), 100);
  });

  function fmt(sec) {
    const s = Math.max(0, Math.floor(sec || 0));
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
  }

  let activeKey = '';
  let lines = [];

  function findActiveMedia() {
    const list = [...document.querySelectorAll('video,audio')];
    return list.find((m) => !m.paused && m.duration > 10) || list.find((m) => m.duration > 10) || null;
  }

  shadow.getElementById('nl-play').addEventListener('click', () => {
    const m = findActiveMedia();
    if (m) { if (m.paused) m.play(); else m.pause(); }
  });

  function tick() {
    const media = findActiveMedia();
    const md = navigator.mediaSession?.metadata;
    const title = md?.title || document.title.replace(/ - YouTube$/i, '') || '';
    const artist = md?.artist || '';
    const album = md?.album || '';
    const artworkSrc = md?.artwork?.[0]?.src || '';

    if (!media || !title) {
      root.style.display = 'none';
      return;
    }
    root.style.display = 'flex';

    const dur = media.duration || 0;
    const el = media.currentTime || 0;
    const key = `${title.toLowerCase()}|${artist.toLowerCase()}`;
    if (key !== activeKey) {
      activeKey = key;
      lines = [];
      lyricEl.textContent = `Searching: ${title}`;
      chrome.runtime.sendMessage({ type: 'FETCH_LYRICS', payload: { title, artist, duration: dur } }, (res) => {
        if (activeKey === key && res?.lines) lines = res.lines;
      });
    }

    titleEl.textContent = title;
    subEl.textContent = [artist, album].filter(Boolean).join(' · ');
    timeEl.textContent = `${fmt(el)} / ${fmt(dur)}`;
    fillEl.style.width = `${dur > 0 ? Math.min(100, (el / dur) * 100) : 0}%`;
    playBtn.innerHTML = media.paused ? '&#9654;' : '&#10074;&#10074;';
    if (artworkSrc) {
      art.src = artworkSrc;
      art.classList.add('show');
    } else {
      art.classList.remove('show');
    }

    if (lines.length) {
      let idx = -1;
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].time <= el + 0.1) idx = i;
        else break;
      }
      lyricEl.textContent = idx >= 0 ? lines[idx].text : title;
    } else {
      lyricEl.textContent = title;
    }
  }

  setInterval(tick, 120);
})();

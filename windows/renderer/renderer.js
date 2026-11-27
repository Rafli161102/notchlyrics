(() => {
  'use strict';

  const colorCache = new Map();

  function extractAlbumAccent(artworkUrl, cb) {
    if (!artworkUrl) {
      cb(null);
      return;
    }
    if (colorCache.has(artworkUrl)) {
      cb(colorCache.get(artworkUrl));
      return;
    }
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      try {
        const canvas = document.createElement('canvas');
        canvas.width = 24;
        canvas.height = 24;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0, 24, 24);
        const { data } = ctx.getImageData(0, 0, 24, 24);
        let rSum = 0;
        let gSum = 0;
        let bSum = 0;
        let wSum = 0;
        for (let i = 0; i < data.length; i += 4) {
          const r = data[i];
          const g = data[i + 1];
          const b = data[i + 2];
          const maxC = Math.max(r, g, b);
          const minC = Math.min(r, g, b);
          const sat = maxC > 0 ? (maxC - minC) / maxC : 0;
          const weight = 0.2 + sat * 2.5;
          rSum += r * weight;
          gSum += g * weight;
          bSum += b * weight;
          wSum += weight;
        }
        // Brighten accent cleanly for >= 4.5:1 readability on pure OLED #000000 black
        const rOut = Math.min(255, Math.max(125, Math.round((rSum / Math.max(1, wSum)) * 1.25)));
        const gOut = Math.min(255, Math.max(125, Math.round((gSum / Math.max(1, wSum)) * 1.25)));
        const bOut = Math.min(255, Math.max(125, Math.round((bSum / Math.max(1, wSum)) * 1.25)));
        const accent = `rgb(${rOut}, ${gOut}, ${bOut})`;
        colorCache.set(artworkUrl, accent);
        cb(accent);
      } catch (_) {
        cb(null);
      }
    };
    img.onerror = () => cb(null);
    img.src = artworkUrl;
  }

  let latestArtwork = '';
  let resolvedAccent = '#f4d06f';
  let latestSnapshot = null;
  let syncedAtPerfMs = performance.now();
  let cursorIdx = -1;
  let rafId = null;
  let lastRenderSig = '';
  let windowShown = true;

  function computeLiveElapsed(snapshot) {
    const base = Math.max(0, Number(snapshot?.baseElapsed) || 0);
    if (!snapshot?.isPlaying) return base;
    const dt = Math.max(0, (performance.now() - syncedAtPerfMs) / 1000);
    const raw = base + dt;
    const dur = Number(snapshot?.duration) || 0;
    return dur > 0 ? Math.min(dur, raw) : raw;
  }

  function renderCurrentFrame(force = false) {
    if (!latestSnapshot || !window.NotchLyrics || !window.NotchLyricsTiming) return;
    const rawElapsed = computeLiveElapsed(latestSnapshot);
    const frame = window.NotchLyricsTiming.computeFrameState(latestSnapshot, rawElapsed, cursorIdx);
    cursorIdx = frame.lineIndex;

    const sig = `${latestSnapshot.style}|${latestSnapshot.isPlaying}|${latestSnapshot.trackTitle}|${frame.lineIndex}|${frame.mainText}|${Math.round(frame.lineProgress * 180)}|${Math.round(frame.songProgress * 1000)}|${Math.floor(frame.elapsedTime)}|${resolvedAccent}`;
    if (!force && sig === lastRenderSig) return;
    lastRenderSig = sig;

    window.NotchLyrics.update({
      style: latestSnapshot.style,
      mainText: frame.mainText,
      backingText: frame.backingText,
      trackTitle: latestSnapshot.trackTitle,
      artist: latestSnapshot.artist,
      album: latestSnapshot.album,
      artworkUrl: latestSnapshot.artworkUrl,
      isPlaying: latestSnapshot.isPlaying,
      songProgress: frame.songProgress,
      lineProgress: frame.lineProgress,
      elapsedTime: frame.elapsedTime,
      duration: latestSnapshot.duration,
      accentColor: resolvedAccent
    });
  }

  function shouldAnimate() {
    if (!latestSnapshot || !latestSnapshot.isPlaying) return false;
    if (document.hidden || !windowShown) return false;
    const hasLyrics = Array.isArray(latestSnapshot.lines) && latestSnapshot.lines.length > 0;
    const hasDuration = Number(latestSnapshot.duration) > 0;
    return hasLyrics || hasDuration;
  }

  function stopRafLoop() {
    if (rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
  }

  function stepRaf() {
    rafId = null;
    if (!shouldAnimate()) return;
    renderCurrentFrame(false);
    rafId = requestAnimationFrame(stepRaf);
  }

  function syncRafLoop() {
    if (shouldAnimate()) {
      if (rafId === null) {
        rafId = requestAnimationFrame(stepRaf);
      }
    } else {
      stopRafLoop();
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && latestSnapshot) {
      renderCurrentFrame(true);
    }
    syncRafLoop();
  });

  if (window.NotchLyrics && window.NotchLyricsDesktop) {
    window.NotchLyrics.onCommand((cmd) => window.NotchLyricsDesktop.sendCommand(cmd));
    window.NotchLyrics.onHoverChange((expanded) => window.NotchLyricsDesktop.setHovered(expanded));

    window.NotchLyricsDesktop.onState((snapshot) => {
      if (typeof snapshot.windowVisible === 'boolean') {
        windowShown = snapshot.windowVisible;
      }
      latestSnapshot = snapshot;
      syncedAtPerfMs = performance.now();
      cursorIdx = -1;

      if (snapshot.artworkUrl && snapshot.artworkUrl !== latestArtwork) {
        latestArtwork = snapshot.artworkUrl;
        extractAlbumAccent(snapshot.artworkUrl, (acc) => {
          resolvedAccent = acc || '#f4d06f';
          renderCurrentFrame(true);
        });
      } else if (!snapshot.artworkUrl) {
        latestArtwork = '';
        resolvedAccent = '#f4d06f';
      }

      renderCurrentFrame(true);
      syncRafLoop();
    });
  }
})();

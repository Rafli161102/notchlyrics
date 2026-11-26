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

  if (window.NotchLyrics && window.NotchLyricsDesktop) {
    window.NotchLyrics.onCommand((cmd) => window.NotchLyricsDesktop.sendCommand(cmd));
    window.NotchLyrics.onHoverChange((expanded) => window.NotchLyricsDesktop.setHovered(expanded));

    window.NotchLyricsDesktop.onState((state) => {
      if (state.artworkUrl && state.artworkUrl !== latestArtwork) {
        latestArtwork = state.artworkUrl;
        extractAlbumAccent(state.artworkUrl, (acc) => {
          resolvedAccent = acc || '#f4d06f';
        });
      } else if (!state.artworkUrl) {
        latestArtwork = '';
        resolvedAccent = '#f4d06f';
      }
      window.NotchLyrics.update({
        ...state,
        accentColor: resolvedAccent
      });
    });
  }
})();

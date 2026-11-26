# NotchLyrics Web Overlay

Standalone browser-rendered Notch overlay (`notch.html`, `notch.css`, `notch.js`) with zero build steps or external runtime dependencies.

## Features
- Golden Ratio (`phi = 1.618`) proportions (`336x48` collapsed -> `544x110` expanded across `attachedBezel`, `floatingIsland`, and `edgeDockStrip` variants).
- Pure `#000000` OLED black background; `accentColor` and `backingColor` tint only lyric highlights, backing vocals, and progress bar elements.
- Multi-line wrapping with automatic font scaling (`applyAutoFitFont`) so long lyrics fit cleanly without ellipsis truncation.
- Live `MM:SS / MM:SS` playback readout (`tabular-nums`) and transport buttons in the hover-expanded panel.
- Respects `prefers-reduced-motion`.

## JS Contract

```js
window.NotchLyrics.update({
  style: 'attachedBezel', // 'attachedBezel' | 'floatingIsland' | 'edgeDockStrip'
  mainText: 'Current lyric line',
  backingText: 'Ooh',
  title: 'Song Title',
  artist: 'Artist Name',
  album: 'Album Name',
  artworkUrl: 'https://...',
  accentColor: '#f4d06f',
  isPlaying: true,
  elapsedTime: 84,
  duration: 248,
  songProgress: 0.34,
  lineProgress: 0.55
});

window.NotchLyrics.onCommand((command) => {
  // 'previous' | 'togglePlayPause' | 'next'
});
```

Frames or host wrappers can also send `postMessage({ source: 'notchlyrics', type: 'state', state })`.

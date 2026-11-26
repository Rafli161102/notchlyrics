# NotchLyrics web notch

Browser-rendered notch UI for **Windows Chrome, Brave, Edge, Firefox, and other browsers**. No build step and no external scripts.

Open `notch.html`, or embed it in a browser extension, local web app, or native host. This page is **not by itself an OS-level always-on-top overlay**: a browser page cannot draw above every Windows app or read system-wide Now Playing on another app. Use a Chrome/Brave extension or native companion host for OS integration; the UI itself is browser-based.

## UI contract

```js
window.NotchLyrics.update({
  mainText: '...',
  backingText: '...',
  title: '...',
  trackTitle: '...',
  artist: '...',
  album: '...',
  artworkUrl: 'https://...',
  isPlaying: true,
  progress: 0.48, // or songProgress
  songProgress: 0.48
});

window.NotchLyrics.onCommand((command) => {
  // previous, togglePlayPause, next
});
```

Or `postMessage`:

```js
targetWindow.postMessage({
  source: 'notchlyrics',
  type: 'state',
  state: { mainText: '...', title: '...', artist: '...', album: '...' }
}, '*');
```

Commands are emitted as `{ source: 'notchlyrics', type: 'command', command }`, a `notchlyrics-command` `CustomEvent`, and to `onCommand` listeners.

Hover or keyboard-focus the notch to expand. Native buttons handle click, Enter, Space, and visible focus. `prefers-reduced-motion` disables transitions. Empty data is not replaced with fabricated metadata.

(() => {
  'use strict';

  const notch = document.getElementById('notch');
  const artwork = document.getElementById('artwork');
  const mainLyric = document.getElementById('main-lyric');
  const backingLyric = document.getElementById('backing-lyric');
  const trackTitle = document.getElementById('track-title');
  const artist = document.getElementById('artist');
  const album = document.getElementById('album');
  const playPause = document.getElementById('play-pause');
  const progressFill = document.getElementById('progress-fill');

  const commands = new Set();
  let isPlaying = false;

  function emitCommand(command) {
    const message = { source: 'notchlyrics', type: 'command', command };
    commands.forEach((listener) => listener(command));
    window.parent.postMessage(message, '*');
    window.dispatchEvent(new CustomEvent('notchlyrics-command', { detail: { command } }));
  }

  document.querySelectorAll('[data-command]').forEach((button) => {
    button.addEventListener('click', () => emitCommand(button.dataset.command));
  });

  notch.addEventListener('mouseenter', () => notch.classList.add('expanded'));
  notch.addEventListener('mouseleave', () => notch.classList.remove('expanded'));
  notch.addEventListener('focusin', () => notch.classList.add('expanded'));
  notch.addEventListener('focusout', (event) => {
    if (!notch.contains(event.relatedTarget)) notch.classList.remove('expanded');
  });
  notch.addEventListener('keydown', (event) => {
    if (event.target !== notch) return;
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      emitCommand('togglePlayPause');
    }
  });

  function setText(element, value) {
    element.textContent = value || '';
  }

  function update(state = {}) {
    setText(mainLyric, state.mainText);
    const backing = (state.backingText || '').trim();
    setText(backingLyric, backing);
    backingLyric.hidden = !backing;
    setText(trackTitle, state.title || state.trackTitle);
    setText(artist, state.artist);
    setText(album, state.album);

    isPlaying = Boolean(state.isPlaying);
    playPause.textContent = isPlaying ? 'Pause' : 'Play';
    playPause.setAttribute('aria-label', isPlaying ? 'Jeda' : 'Putar');

    const progress = Number(state.progress ?? state.songProgress ?? 0);
    progressFill.style.width = `${Math.min(100, Math.max(0, progress * 100))}%`;

    if (state.artworkUrl) {
      artwork.src = state.artworkUrl;
      artwork.classList.add('has-image');
    } else {
      artwork.removeAttribute('src');
      artwork.classList.remove('has-image');
    }
  }

  window.addEventListener('message', (event) => {
    if (!event.data || event.data.source !== 'notchlyrics') return;
    if (event.data.type === 'state') update(event.data.state || event.data.payload || event.data);
  });

  window.NotchLyrics = {
    update,
    setExpanded(expanded) { notch.classList.toggle('expanded', Boolean(expanded)); },
    onCommand(listener) { commands.add(listener); return () => commands.delete(listener); },
    emitCommand
  };
})();

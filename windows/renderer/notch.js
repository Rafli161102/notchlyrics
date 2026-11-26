(() => {
  'use strict';

  const notch = document.getElementById('notch');
  const artwork = document.getElementById('artwork');
  const mainLyric = document.getElementById('main-lyric');
  const backingLyric = document.getElementById('backing-lyric');
  const trackTitle = document.getElementById('track-title');
  const artistAlbum = document.getElementById('artist-album');
  const timeReadout = document.getElementById('time-readout');
  const playPause = document.getElementById('play-pause');
  const progressFill = document.getElementById('progress-fill');
  const progressBead = document.getElementById('progress-bead');

  const commands = new Set();
  const hoverListeners = new Set();
  let collapseTimer = null;
  let lastMainSignature = '';

  function emitCommand(command) {
    const message = { source: 'notchlyrics', type: 'command', command };
    commands.forEach((listener) => listener(command));
    if (window.parent && window.parent !== window) {
      window.parent.postMessage(message, '*');
    }
    window.dispatchEvent(new CustomEvent('notchlyrics-command', { detail: { command } }));
  }

  document.querySelectorAll('[data-command]').forEach((button) => {
    button.addEventListener('click', (event) => {
      event.stopPropagation();
      emitCommand(button.dataset.command);
    });
  });

  function setExpanded(expanded) {
    const next = Boolean(expanded);
    const changed = notch.classList.contains('expanded') !== next;
    notch.classList.toggle('expanded', next);
    if (changed) {
      hoverListeners.forEach((fn) => fn(next));
    }
  }

  notch.addEventListener('mouseenter', () => {
    if (collapseTimer) {
      clearTimeout(collapseTimer);
      collapseTimer = null;
    }
    setExpanded(true);
  });

  notch.addEventListener('mouseleave', () => {
    if (collapseTimer) clearTimeout(collapseTimer);
    collapseTimer = setTimeout(() => setExpanded(false), 100);
  });

  notch.addEventListener('focusin', () => setExpanded(true));
  notch.addEventListener('focusout', (event) => {
    if (!notch.contains(event.relatedTarget)) setExpanded(false);
  });

  notch.addEventListener('keydown', (event) => {
    if (event.target !== notch) return;
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      emitCommand('togglePlayPause');
    }
  });

  function formatTime(seconds) {
    const clamped = Math.max(0, Math.floor(Number(seconds) || 0));
    const hrs = Math.floor(clamped / 3600);
    const mins = Math.floor((clamped % 3600) / 60);
    const secs = clamped % 60;
    const pad = (n) => String(n).padStart(2, '0');
    return hrs > 0 ? `${hrs}:${pad(mins)}:${pad(secs)}` : `${pad(mins)}:${pad(secs)}`;
  }

  function formatTimePair(elapsed, duration) {
    const safeDur = Math.max(0, Number(duration) || 0);
    const safeElapsed = safeDur > 0 ? Math.min(Math.max(0, Number(elapsed) || 0), safeDur) : Math.max(0, Number(elapsed) || 0);
    return safeDur > 0 ? `${formatTime(safeElapsed)} / ${formatTime(safeDur)}` : formatTime(safeElapsed);
  }

  function renderKaraokeText(text, lineProgress) {
    const clean = text || '';
    const chars = Array.from(clean);
    if (!chars.length) {
      mainLyric.textContent = '';
      return;
    }
    const clamped = Math.min(1, Math.max(0, Number(lineProgress ?? 1)));
    const splitIdx = Math.round(chars.length * clamped);
    if (splitIdx >= chars.length || splitIdx <= 0) {
      mainLyric.textContent = clean;
      return;
    }
    const sungSpan = document.createElement('span');
    sungSpan.className = 'sung';
    sungSpan.textContent = chars.slice(0, splitIdx).join('');

    const upcomingSpan = document.createElement('span');
    upcomingSpan.className = 'upcoming';
    upcomingSpan.textContent = chars.slice(splitIdx).join('');

    mainLyric.replaceChildren(sungSpan, upcomingSpan);
  }

  function applyAutoFitFont(text, expanded) {
    const len = (text || '').length;
    if (len > 75) {
      mainLyric.style.fontSize = expanded ? '11.5px' : '10.5px';
    } else if (len > 48) {
      mainLyric.style.fontSize = expanded ? '12.5px' : '11.5px';
    } else {
      mainLyric.style.fontSize = expanded ? '13.5px' : '12.5px';
    }
  }

  function update(state = {}) {
    if (state.style) {
      notch.classList.remove('style-attached', 'style-floating', 'style-strip');
      if (state.style === 'floatingIsland') notch.classList.add('style-floating');
      else if (state.style === 'edgeDockStrip') notch.classList.add('style-strip');
      else notch.classList.add('style-attached');
    }

    // Pure OLED black background is preserved unconditionally; album accent applies strictly to text & indicators
    const rootStyle = document.documentElement.style;
    if (state.accentColor) {
      rootStyle.setProperty('--notch-accent', state.accentColor);
    }
    if (state.backingColor) {
      rootStyle.setProperty('--notch-backing', state.backingColor);
    }
    if (state.textColor) {
      rootStyle.setProperty('--notch-text', state.textColor);
    }

    const mainText = state.mainText || '';
    if (mainText !== lastMainSignature) {
      lastMainSignature = mainText;
      mainLyric.style.opacity = '0.78';
      requestAnimationFrame(() => { mainLyric.style.opacity = '1'; });
    }
    applyAutoFitFont(mainText, notch.classList.contains('expanded'));
    renderKaraokeText(mainText, state.lineProgress);

    const backing = (state.backingText || '').trim();
    backingLyric.textContent = backing;
    backingLyric.hidden = !backing;

    trackTitle.textContent = state.title || state.trackTitle || '';
    const subParts = [state.artist, state.album].map((s) => (s || '').trim()).filter(Boolean);
    artistAlbum.textContent = subParts.join(' · ');

    timeReadout.textContent = formatTimePair(state.elapsedTime, state.duration);

    const playing = Boolean(state.isPlaying);
    playPause.innerHTML = playing ? '&#10074;&#10074;' : '&#9654;';
    playPause.setAttribute('aria-label', playing ? 'Pause' : 'Play');

    const progress = Math.min(1, Math.max(0, Number(state.progress ?? state.songProgress ?? 0)));
    const pct = `${(progress * 100).toFixed(2)}%`;
    progressFill.style.width = pct;
    progressBead.style.left = pct;
    progressBead.style.opacity = progress > 0.002 ? '1' : '0';

    if (state.artworkUrl) {
      if (artwork.getAttribute('src') !== state.artworkUrl) {
        artwork.src = state.artworkUrl;
      }
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
    setExpanded,
    onCommand(listener) { commands.add(listener); return () => commands.delete(listener); },
    onHoverChange(listener) { hoverListeners.add(listener); return () => hoverListeners.delete(listener); },
    emitCommand,
    formatTimePair
  };
})();

(() => {
  'use strict';

  const RELEASES_LATEST_URL = 'https://github.com/Rafli161102/notchlyrics/releases/latest';
  const RELEASES_API_URL = 'https://api.github.com/repos/Rafli161102/notchlyrics/releases/latest';

  const PLATFORM_INFO = {
    macos: {
      tabId: 'tab-macos',
      cta: 'Download for macOS (Universal .zip)',
      summary: 'macOS 14.2+ Universal (Apple Silicon + Intel) · TouchBarLyrics-2.4.0-macOS.zip',
      matchAsset: (name) => name.endsWith('.zip') && name.toLowerCase().includes('macos')
    },
    windows: {
      tabId: 'tab-windows',
      cta: 'Download for Windows (x64 / ARM64)',
      summary: 'Windows 10/11 Installer & Portable (.exe) · NotchLyrics Setup 2.4.0.exe',
      matchAsset: (name) => name.endsWith('.exe') && name.toLowerCase().includes('setup')
    },
    linux: {
      tabId: 'tab-linux',
      cta: 'Download for Linux (.AppImage / .deb)',
      summary: 'Linux x64 (X11 / Wayland MPRIS2) · .AppImage & .deb packages',
      matchAsset: (name) => name.endsWith('.AppImage') || name.endsWith('.deb')
    }
  };

  function detectClientOS() {
    const uaDataPlatform = (navigator.userAgentData && navigator.userAgentData.platform) || '';
    const raw = `${uaDataPlatform} ${navigator.platform || ''} ${navigator.userAgent || ''}`.toLowerCase();
    if (raw.includes('mac')) return 'macos';
    if (raw.includes('win')) return 'windows';
    if (raw.includes('linux') && !raw.includes('android')) return 'linux';
    return 'macos';
  }

  const osChips = Array.from(document.querySelectorAll('.os-chip'));
  const primaryBtn = document.getElementById('primary-download-btn');
  const downloadMeta = document.getElementById('download-meta');
  const releaseStatusText = document.getElementById('release-status-text');

  let selectedOS = detectClientOS();
  let resolvedAssets = [];
  let releaseTag = 'v2.4.0';

  function updateDownloadPanel(osKey) {
    selectedOS = PLATFORM_INFO[osKey] ? osKey : 'macos';
    const info = PLATFORM_INFO[selectedOS];

    osChips.forEach((chip) => {
      chip.setAttribute('aria-pressed', chip.dataset.os === selectedOS ? 'true' : 'false');
    });

    const matched = resolvedAssets.find((asset) => info.matchAsset(asset.name));
    if (matched) {
      primaryBtn.href = matched.browser_download_url;
      primaryBtn.removeAttribute('aria-disabled');
      primaryBtn.removeAttribute('tabindex');
      primaryBtn.textContent = info.cta;
      downloadMeta.textContent = `${info.summary.split('·')[0].trim()} · `NaN` (${releaseTag})`;
    } else {
      primaryBtn.removeAttribute('href');
      primaryBtn.setAttribute('aria-disabled', 'true');
      primaryBtn.setAttribute('tabindex', '-1');
      primaryBtn.textContent = 'Not available yet';
      downloadMeta.textContent = `No ${selectedOS} package is available in ${releaseTag} yet.`;
    }
  }

  osChips.forEach((chip) => {
    chip.addEventListener('click', () => {
      updateDownloadPanel(chip.dataset.os);
      activateTab(PLATFORM_INFO[chip.dataset.os].tabId, false);
    });
  });

  async function hydrateLatestRelease() {
    if (!releaseStatusText) return;
    try {
      const res = await fetch(RELEASES_API_URL, { headers: { Accept: 'application/vnd.github+json' } });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (data && Array.isArray(data.assets) && data.assets.length > 0) {
        resolvedAssets = data.assets;
        releaseTag = data.tag_name || releaseTag;
        updateDownloadPanel(selectedOS);
        const hasSelectedAsset = resolvedAssets.some((asset) => PLATFORM_INFO[selectedOS].matchAsset(asset.name));
        releaseStatusText.textContent = hasSelectedAsset
          ? `Latest GitHub release ${releaseTag} resolved (${resolvedAssets.length} downloadable assets).`
          : `Latest release ${releaseTag} does not contain a ${selectedOS} package yet.`;
      } else {
        releaseStatusText.textContent = 'No downloadable assets are available in the latest GitHub release yet.';
      }
    } catch (_) {
      releaseStatusText.innerHTML = 'Direct links point to <a href="' + RELEASES_LATEST_URL + '">GitHub Releases</a>.';
    }
  }

  // Mobile navigation toggle
  const navToggle = document.getElementById('nav-toggle');
  const siteNav = document.getElementById('site-nav');
  if (navToggle && siteNav) {
    navToggle.addEventListener('click', () => {
      const open = siteNav.classList.toggle('is-open');
      navToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    siteNav.querySelectorAll('a').forEach((link) => {
      link.addEventListener('click', () => {
        if (siteNav.classList.contains('is-open')) {
          siteNav.classList.remove('is-open');
          navToggle.setAttribute('aria-expanded', 'false');
        }
      });
    });
  }

  // Accessible ARIA Tabs
  const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
  const panels = Array.from(document.querySelectorAll('[role="tabpanel"]'));

  function activateTab(tabId, moveFocus = true) {
    tabs.forEach((tab) => {
      const isTarget = tab.id === tabId;
      tab.setAttribute('aria-selected', isTarget ? 'true' : 'false');
      tab.setAttribute('tabindex', isTarget ? '0' : '-1');
      if (isTarget && moveFocus) tab.focus();
    });
    panels.forEach((panel) => {
      const active = panel.getAttribute('aria-labelledby') === tabId;
      panel.hidden = !active;
    });
  }

  tabs.forEach((tab, idx) => {
    tab.addEventListener('click', () => activateTab(tab.id, false));
    tab.addEventListener('keydown', (event) => {
      let nextIdx = null;
      if (event.key === 'ArrowRight') nextIdx = (idx + 1) % tabs.length;
      else if (event.key === 'ArrowLeft') nextIdx = (idx - 1 + tabs.length) % tabs.length;
      else if (event.key === 'Home') nextIdx = 0;
      else if (event.key === 'End') nextIdx = tabs.length - 1;
      if (nextIdx !== null) {
        event.preventDefault();
        activateTab(tabs[nextIdx].id, true);
      }
    });
  });

  // Copy buttons
  document.querySelectorAll('.copy-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const text = btn.dataset.copy || '';
      const original = btn.textContent;
      try {
        await navigator.clipboard.writeText(text);
        btn.textContent = 'Copied';
      } catch (_) {
        btn.textContent = 'Copy manually';
      }
      setTimeout(() => {
        btn.textContent = original;
      }, 1800);
    });
  });

  // Interactive Live Notch Simulator
  const DEMO_TRACKS = [
    {
      badge: 'YN',
      title: 'Yoru ni Kakeru (Racing Into the Night)',
      artist: 'YOASOBI · THE BOOK',
      duration: 260,
      lines: [
        { time: 0, text: 'Shizumu you ni tokete yuku you ni', backing: '' },
        { time: 4.2, text: 'Futaridake no sora ga hirogaru yoru ni', backing: '(yoru ni)' },
        { time: 8.6, text: 'Sayonara dake datta sono hitokoto de', backing: '' }
      ]
    },
    {
      badge: 'TL',
      title: 'Hati-Hati di Jalan',
      artist: 'Tulus · Manusia',
      duration: 242,
      lines: [
        { time: 0, text: 'Kukira kita akan bersama', backing: '' },
        { time: 4.0, text: 'Begitu banyak yang sama antara kita', backing: '(antara kita)' },
        { time: 8.2, text: 'Namun ternyata tak sejalan', backing: '' }
      ]
    },
    {
      badge: 'NL',
      title: 'Starlight Resonance',
      artist: 'Demo Duet · Golden Ratio Sync',
      duration: 198,
      lines: [
        { time: 0, text: 'Hold the cadence steady through the chorus', backing: '(steady through the chorus)' },
        { time: 4.5, text: 'Every syllable lands cleanly on the beat', backing: '' },
        { time: 8.8, text: 'Pure OLED contrast against the bezel', backing: '(against the bezel)' }
      ]
    }
  ];

  const demoNotch = document.getElementById('demo-notch');
  const demoArt = document.getElementById('demo-art');
  const demoMainLyric = document.getElementById('demo-main-lyric');
  const demoBackingLyric = document.getElementById('demo-backing-lyric');
  const demoTrackTitle = document.getElementById('demo-track-title');
  const demoArtistAlbum = document.getElementById('demo-artist-album');
  const demoTimer = document.getElementById('demo-timer');
  const demoProgressFill = document.getElementById('demo-progress-fill');
  const demoProgressBead = document.getElementById('demo-progress-bead');
  const styleButtons = Array.from(document.querySelectorAll('[data-style]'));
  const expandBtn = document.getElementById('sim-expand');
  const togglePlayBtn = document.getElementById('sim-toggle-play');
  const simPlayBtn = document.getElementById('sim-play');
  const simPrevBtn = document.getElementById('sim-prev');
  const simNextBtn = document.getElementById('sim-next');

  let trackIdx = 0;
  let simElapsed = 2.6;
  let simPlaying = false;
  let lastTickMs = performance.now();
  let rafHandle = null;

  function formatMMSS(sec) {
    const s = Math.max(0, Math.floor(sec));
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
  }

  function renderDemoFrame() {
    const track = DEMO_TRACKS[trackIdx];
    const loopDur = 13.0;
    const tLoop = simElapsed % loopDur;

    let activeIdx = 0;
    for (let i = track.lines.length - 1; i >= 0; i--) {
      if (tLoop >= track.lines[i].time) {
        activeIdx = i;
        break;
      }
    }
    const line = track.lines[activeIdx];
    const nextTime = activeIdx + 1 < track.lines.length ? track.lines[activeIdx + 1].time : loopDur;
    const lineSpan = Math.max(0.5, nextTime - line.time);
    const lineProgress = Math.min(1, Math.max(0, (tLoop - line.time) / lineSpan));

    const chars = Array.from(line.text);
    const splitIdx = Math.round(chars.length * lineProgress);
    const sungSpan = document.createElement('span');
    sungSpan.className = 'sung';
    sungSpan.textContent = chars.slice(0, splitIdx).join('');
    const upcomingSpan = document.createElement('span');
    upcomingSpan.className = 'upcoming';
    upcomingSpan.textContent = chars.slice(splitIdx).join('');
    demoMainLyric.replaceChildren(sungSpan, upcomingSpan);

    demoBackingLyric.textContent = line.backing;
    demoBackingLyric.hidden = !line.backing;

    demoArt.textContent = track.badge;
    demoTrackTitle.textContent = track.title;
    demoArtistAlbum.textContent = track.artist;

    const displayElapsed = 40 + tLoop;
    demoTimer.textContent = `${formatMMSS(displayElapsed)} / ${formatMMSS(track.duration)}`;

    const pct = `${((displayElapsed / track.duration) * 100).toFixed(2)}%`;
    demoProgressFill.style.width = pct;
    demoProgressBead.style.left = pct;
  }

  function syncPlayButtons() {
    if (togglePlayBtn) {
      togglePlayBtn.setAttribute('aria-pressed', simPlaying ? 'true' : 'false');
      togglePlayBtn.textContent = simPlaying ? 'Pause Sweep' : 'Play Sweep';
    }
    if (simPlayBtn) {
      simPlayBtn.innerHTML = simPlaying ? '&#10074;&#10074;' : '&#9654;';
      simPlayBtn.setAttribute('aria-label', simPlaying ? 'Pause demo lyrics' : 'Play demo lyrics');
    }
  }

  function stepDemo(now) {
    rafHandle = null;
    if (!simPlaying) return;
    const dt = Math.max(0, (now - lastTickMs) / 1000);
    lastTickMs = now;
    simElapsed += dt;
    renderDemoFrame();
    rafHandle = requestAnimationFrame(stepDemo);
  }

  function setSimPlaying(next) {
    simPlaying = Boolean(next);
    syncPlayButtons();
    if (simPlaying) {
      lastTickMs = performance.now();
      if (rafHandle === null) rafHandle = requestAnimationFrame(stepDemo);
    } else if (rafHandle !== null) {
      cancelAnimationFrame(rafHandle);
      rafHandle = null;
    }
  }

  function setNotchExpanded(expanded) {
    const next = Boolean(expanded);
    demoNotch.classList.toggle('expanded', next);
    if (expandBtn) {
      expandBtn.setAttribute('aria-pressed', next ? 'true' : 'false');
      expandBtn.textContent = next ? 'Collapse Card' : 'Expand Card';
    }
  }

  styleButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const style = btn.dataset.style;
      demoNotch.classList.remove('style-attached', 'style-floating', 'style-strip');
      if (style === 'floatingIsland') demoNotch.classList.add('style-floating');
      else if (style === 'edgeDockStrip') demoNotch.classList.add('style-strip');
      else demoNotch.classList.add('style-attached');

      styleButtons.forEach((b) => {
        const active = b === btn;
        b.classList.toggle('is-active', active);
        b.setAttribute('aria-pressed', active ? 'true' : 'false');
      });
    });
  });

  if (expandBtn) {
    expandBtn.addEventListener('click', () => {
      setNotchExpanded(!demoNotch.classList.contains('expanded'));
    });
  }

  if (togglePlayBtn) {
    togglePlayBtn.addEventListener('click', () => setSimPlaying(!simPlaying));
  }

  if (simPlayBtn) {
    simPlayBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      setSimPlaying(!simPlaying);
    });
  }

  if (simPrevBtn) {
    simPrevBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      trackIdx = (trackIdx - 1 + DEMO_TRACKS.length) % DEMO_TRACKS.length;
      simElapsed = 2.6;
      renderDemoFrame();
    });
  }

  if (simNextBtn) {
    simNextBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      trackIdx = (trackIdx + 1) % DEMO_TRACKS.length;
      simElapsed = 2.6;
      renderDemoFrame();
    });
  }

  if (demoNotch) {
    demoNotch.addEventListener('mouseenter', () => setNotchExpanded(true));
    demoNotch.addEventListener('mouseleave', () => setNotchExpanded(false));
    demoNotch.addEventListener('keydown', (event) => {
      if (event.target !== demoNotch) return;
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        setNotchExpanded(!demoNotch.classList.contains('expanded'));
      }
    });
  }

  // Initialize state cleanly
  updateDownloadPanel(selectedOS);
  activateTab(PLATFORM_INFO[selectedOS].tabId, false);
  renderDemoFrame();
  syncPlayButtons();
  hydrateLatestRelease();
})();

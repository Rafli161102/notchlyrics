(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.NotchLyricsTiming = factory();
  }
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  /**
   * Finds the greatest index i with lines[i].time <= elapsed, or -1.
   * Uses O(1) hint-cursor verification before falling back to binary search.
   */
  function findActiveLineIndex(lines, elapsed, hintIndex = -1) {
    if (!Array.isArray(lines) || !lines.length) return -1;
    if (elapsed < lines[0].time) return -1;

    if (Number.isInteger(hintIndex) && hintIndex >= 0 && hintIndex < lines.length) {
      if (lines[hintIndex].time <= elapsed) {
        if (hintIndex + 1 >= lines.length || lines[hintIndex + 1].time > elapsed) {
          return hintIndex;
        }
        if (lines[hintIndex + 1].time <= elapsed && (hintIndex + 2 >= lines.length || lines[hintIndex + 2].time > elapsed)) {
          return hintIndex + 1;
        }
      }
    }

    let low = 0;
    let high = lines.length - 1;
    let found = -1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      if (lines[mid].time <= elapsed) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  function computeLineProgress(line, elapsed, nextLineTime, wordSpeedScale = 1.0) {
    if (!line) return 1;
    const speed = Math.min(2.2, Math.max(0.4, Number(wordSpeedScale) || 1.0));
    if (line.words && line.words.length) {
      const totalChars = Math.max(1, line.words.reduce((acc, w) => acc + w.text.length, 0));
      const effElapsed = line.time + (elapsed - line.time) * speed;
      let before = 0;
      for (let i = 0; i < line.words.length; i++) {
        const w = line.words[i];
        const end = w.time + Math.max(0.07, w.duration);
        if (effElapsed < w.time) return before / totalChars;
        if (effElapsed <= end) {
          const frac = (effElapsed - w.time) / Math.max(0.07, w.duration);
          return Math.min(1, Math.max(0, (before + frac * w.text.length) / totalChars));
        }
        if (i + 1 < line.words.length && effElapsed < line.words[i + 1].time) {
          return (before + w.text.length) / totalChars;
        }
        before += w.text.length;
      }
      return 1;
    }
    const effectiveEnd = (typeof line.endTime === 'number' && Number.isFinite(line.endTime)) ? line.endTime : nextLineTime;
    const gap = Math.max(0.5, effectiveEnd - line.time);
    const span = Math.min(gap * 0.86, Math.max(0.75, (line.mainText || '').length * 0.078)) / speed;
    return Math.min(1, Math.max(0, (elapsed - line.time) / Math.max(0.35, span)));
  }

  function computeFrameState(snapshot, rawElapsed, hintIndex = -1) {
    const safeRaw = Math.max(0, Number(rawElapsed) || 0);
    const duration = Math.max(0, Number(snapshot?.duration) || 0);
    const manualOffset = Number(snapshot?.manualOffsetSeconds) || 0;
    const playingLead = snapshot?.isPlaying ? 0.11 : 0;
    const elapsed = safeRaw + playingLead + manualOffset;
    const lines = Array.isArray(snapshot?.lines) ? snapshot.lines : [];

    let lineIndex = -1;
    let mainText = snapshot?.idleText || '';
    let backingText = '';
    let lineProgress = 1;

    if (lines.length) {
      lineIndex = findActiveLineIndex(lines, elapsed, hintIndex);
      if (lineIndex >= 0) {
        const cur = lines[lineIndex];
        const nextTime = lineIndex + 1 < lines.length
          ? lines[lineIndex + 1].time
          : (duration > cur.time ? duration : cur.time + 5);
        mainText = cur.mainText || '';
        backingText = cur.backingText || '';
        lineProgress = computeLineProgress(cur, elapsed, nextTime, snapshot?.wordSpeedScale ?? 1.0);
      } else {
        mainText = snapshot?.trackTitle || mainText;
        lineProgress = 0;
      }
    }

    const songProgress = duration > 0 ? Math.min(1, Math.max(0, safeRaw / duration)) : 0;
    return {
      lineIndex,
      mainText,
      backingText,
      lineProgress,
      songProgress,
      elapsedTime: safeRaw
    };
  }

  return {
    findActiveLineIndex,
    computeLineProgress,
    computeFrameState
  };
}));

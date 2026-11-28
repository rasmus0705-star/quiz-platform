'use strict';

(() => {
  const styles = () => {
    const own = getComputedStyle(document.documentElement);
    if (own.getPropertyValue('--qj-suspense-ms').trim()) return own;
    try {
      if (window.parent !== window) {
        const parentStyles = window.parent.getComputedStyle(window.parent.document.documentElement);
        if (parentStyles.getPropertyValue('--qj-suspense-ms').trim()) return parentStyles;
      }
    } catch { /* The standalone scoreboard uses its local defaults. */ }
    return own;
  };
  const numberToken = (name, fallback) => Number.parseFloat(styles().getPropertyValue(name)) || fallback;
  const colorToken = (name, fallback) => styles().getPropertyValue(name).trim() || fallback;
  const reducedMotion = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches || false;
  const motion = Object.freeze({
    suspenseMs: numberToken('--qj-suspense-ms', 1600),
    revealMs: numberToken('--qj-reveal-ms', 1300),
    bannerMs: numberToken('--qj-banner-ms', 2600),
  });
  const playerPalette = Object.freeze([
    [colorToken('--player-fox', '#ff4d6d'), 'Ræven'],
    [colorToken('--player-owl', '#4dabff'), 'Uglen'],
    [colorToken('--player-bear', '#ffd23f'), 'Bjørnen'],
    [colorToken('--player-hare', '#3ddc97'), 'Haren'],
    [colorToken('--player-wolf', '#b388ff'), 'Ulven'],
    [colorToken('--player-lynx', '#ff8c42'), 'Lossen'],
    [colorToken('--player-eagle', '#00e5ff'), 'Ørnen'],
    [colorToken('--player-badger', '#ff6ec7'), 'Grævlingen'],
  ].map(item => Object.freeze(item)));

  window.QJ = Object.assign(window.QJ || {}, {
    reducedMotion,
    motion,
    motionDuration: milliseconds => reducedMotion() ? milliseconds / 2 : milliseconds,
    playerPalette,
  });
})();

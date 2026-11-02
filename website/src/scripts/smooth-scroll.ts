/**
 * Smooth scrolling. A mouse wheel moves in notches, and the pinned scene and
 * layered planes on this page are driven by the scroll position, so notches
 * show up as small jumps. Lenis eases the scroll position between them.
 *
 * It keeps the native scrollbar, keyboard scrolling and find-in-page, and it
 * turns itself off for visitors who ask for reduced motion.
 */
import Lenis from 'lenis';

export function startSmoothScroll(): void {
  const headerHeight = parseFloat(getComputedStyle(document.documentElement).fontSize) * 4;
  new Lenis({
    autoRaf: true,
    lerp: 0.12,
    // Anchor links ("How it works", "Questions") scroll smoothly too, and stop
    // below the fixed header instead of under it.
    anchors: { offset: -(headerHeight + 16) },
    respectReducedMotion: true,
  });
}

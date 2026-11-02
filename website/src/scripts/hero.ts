/**
 * The hero's two moving parts, kept apart on purpose.
 *
 * The dictation runs on a clock: two taps on the language's hotkey, the sentence
 * arrives word by word, one tap pastes it, a pause, and again. It plays
 * the same whether or not the visitor scrolls.
 *
 * Scrolling only adds depth on top, and never holds the page: as the hero moves
 * up, the window tilts from leaning back to flat and comes forward, the grid
 * behind it drifts slower than the page, and the keyboard row, the nearest
 * plane, slides away fastest.
 */
import { DictationDemo, SPOKEN_WORDS_PER_SECOND, secondsFor } from './dictation-demo';

const clamp = (value: number, min = 0, max = 1) => Math.min(max, Math.max(min, value));

export function startHero(hero: HTMLElement): void {
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const plane = (name: string) => hero.querySelector<HTMLElement>(`[data-plane="${name}"]`);
  const far = plane('far');
  const copy = plane('copy');
  const scene = plane('scene');
  const panel = plane('panel');
  const keys = plane('keys');
  const hotkey = hero.querySelector<HTMLElement>('[data-hotkey]');
  const note = hero.querySelector<HTMLElement>('[data-note]');
  const text = note?.querySelector<HTMLElement>('[data-demo-text]');
  if (!note || !text) return;

  const demo = new DictationDemo({
    phaseTarget: note,
    text,
    timer: hero.querySelector('[data-demo-timer]'),
    bars: [...hero.querySelectorAll<HTMLElement>('[data-demo-bars] > i')],
  });

  if (reduceMotion) {
    // No loop and no depth. The finished note, as it looks once pasted.
    demo.show(demo.wordCount, 'committed');
    return;
  }

  // One cycle, in seconds: two taps, speak, one tap, hold the result, start over.
  const taps = [0.5, 0.78];
  const listenFrom = 1.05;
  const stopAt = listenFrom + secondsFor(demo.wordCount) + 0.5;
  const cycle = stopAt + 4.5;

  let visible = true;
  new IntersectionObserver(([entry]) => {
    visible = entry?.isIntersecting ?? true;
  }).observe(hero);

  let cycleStart = performance.now();
  let previousFrame = cycleStart;

  const frame = (now: number) => {
    requestAnimationFrame(frame);
    const sinceLastFrame = now - previousFrame;
    previousFrame = now;
    if (!visible) {
      // Paused offscreen: move the start forward so it resumes where it stopped.
      cycleStart += sinceLastFrame;
      return;
    }

    // The dictation, on the clock.
    const elapsed = ((now - cycleStart) / 1000) % cycle;
    hotkey?.classList.toggle('is-pressed', [...taps, stopAt].some((at) => elapsed >= at && elapsed < at + 0.16));
    if (elapsed < listenFrom) {
      demo.show(0, 'idle');
    } else if (elapsed < stopAt) {
      const speaking = elapsed - listenFrom;
      demo.show(speaking * SPOKEN_WORDS_PER_SECOND, 'listening');
      demo.showTime(speaking);
    } else {
      demo.show(demo.wordCount, 'committed');
    }
    panel?.setAttribute('data-panel', demo.phase === 'listening' ? 'listening' : 'hidden');
    demo.animateLevels(now / 1000);

    // The depth, from the scroll. 0 at the top of the page, 1 after most of a
    // screen. Every value is a transform or an opacity.
    const progress = clamp(scrollY / (innerHeight * 0.9));
    const flatten = clamp(progress / 0.55);
    if (far) far.style.transform = `translate3d(0, ${(progress * 90).toFixed(2)}px, 0)`;
    if (copy) {
      copy.style.transform = `translate3d(0, ${(progress * 40).toFixed(2)}px, 0)`;
      copy.style.opacity = (1 - progress * 0.7).toFixed(3);
    }
    if (scene) {
      scene.style.transform =
        `rotateX(${((1 - flatten) * 14).toFixed(3)}deg) ` + `scale(${(0.95 + flatten * 0.05).toFixed(4)})`;
    }
    if (panel) panel.style.transform = `translate3d(0, ${(-progress * 16).toFixed(2)}px, 0)`;
    if (keys) {
      keys.style.transform = `translate3d(0, ${(progress * 110).toFixed(2)}px, 0)`;
      keys.style.opacity = (1 - clamp(progress * 1.2)).toFixed(3);
    }
  };
  requestAnimationFrame(frame);
}

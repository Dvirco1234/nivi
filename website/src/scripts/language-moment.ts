/**
 * The second language's dictation. It runs on time, never on scroll position, so
 * the page keeps moving under the wheel the whole way through.
 *
 * It plays once by itself the first time the section is well into view: two taps
 * on the key, the paragraph arrives word by word, one tap pastes it. After that
 * the keycap replays it with the app's own gesture: two taps start, one tap stops
 * and pastes. Like the app, a dictation started by hand keeps listening until the
 * stop tap, so the visitor is the one who pastes.
 */
import { DictationDemo } from './dictation-demo';

/** The app counts two taps within this window as a double tap. */
const DOUBLE_TAP_MS = 400;
/** A brisk speaker. The point of this moment is that the words arrive fast. */
const WORDS_PER_SECOND = 3.2;
/** The automatic play, in seconds from its start. */
const AUTO = { taps: [0, 0.28], listenFrom: 0.5, stopAfterWords: 0.45 } as const;

export function startLanguageMoment(root: HTMLElement): void {
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const keycap = root.querySelector<HTMLButtonElement>('[data-keycap]');
  const status = root.querySelector<HTMLElement>('[data-status]');
  const note = root.querySelector<HTMLElement>('[data-note]');
  const text = note?.querySelector<HTMLElement>('[data-demo-text]');
  if (!note || !text) return;

  const demo = new DictationDemo({
    phaseTarget: note,
    text,
    timer: root.querySelector('[data-demo-timer]'),
    bars: [...root.querySelectorAll<HTMLElement>('[data-demo-bars] > i')],
  });
  const label = {
    start: root.dataset['textStart'] ?? '',
    stop: root.dataset['textStop'] ?? '',
    pasted: root.dataset['textPasted'] ?? '',
    replay: root.dataset['textReplay'] ?? '',
  };

  const setStatus = (value: string) => {
    if (status && status.textContent !== value) status.textContent = value;
  };
  const press = () => {
    keycap?.classList.add('is-pressed');
    setTimeout(() => keycap?.classList.remove('is-pressed'), 130);
  };
  const render = () => {
    root.dataset['phase'] = demo.phase;
    setStatus(demo.phase === 'listening' ? label.stop : demo.phase === 'committed' ? label.replay : label.start);
  };

  // What is playing: nothing, the automatic play, or the visitor's own.
  let run: { by: 'auto' | 'hand'; startedAt: number; listenFrom: number } | null = null;
  let stopTapAt = 0;
  let autoTapsDone = 0;

  const commit = () => {
    demo.show(demo.wordCount, 'committed');
    run = null;
    render();
  };

  const frame = (now: number) => {
    requestAnimationFrame(frame);
    if (!run) return;
    const seconds = (now - run.startedAt) / 1000;

    if (run.by === 'auto') {
      // Each tap fires once, on the first frame past its time, however slow the
      // frames are.
      while (autoTapsDone < AUTO.taps.length && seconds >= (AUTO.taps[autoTapsDone] ?? Infinity)) {
        press();
        autoTapsDone += 1;
      }
      if (seconds >= stopTapAt) {
        press();
        commit();
        return;
      }
    }
    if (seconds >= run.listenFrom) {
      const speaking = seconds - run.listenFrom;
      demo.show(speaking * WORDS_PER_SECOND, 'listening');
      demo.showTime(speaking);
      render();
    }
    demo.animateLevels(now / 1000);
  };
  requestAnimationFrame(frame);

  const playAutomatically = () => {
    const now = performance.now();
    run = { by: 'auto', startedAt: now, listenFrom: AUTO.listenFrom };
    stopTapAt = AUTO.listenFrom + demo.wordCount / WORDS_PER_SECOND + AUTO.stopAfterWords;
    autoTapsDone = 0;
    demo.show(0, 'idle');
    render();
  };

  // The visitor's gesture: two quick taps start, one tap while listening stops.
  let lastTapAt = -Infinity;
  keycap?.addEventListener('click', () => {
    const now = performance.now();
    press();
    if (demo.phase === 'listening') {
      commit();
      lastTapAt = -Infinity;
      return;
    }
    if (now - lastTapAt <= DOUBLE_TAP_MS) {
      run = { by: 'hand', startedAt: now, listenFrom: 0 };
      demo.show(0, 'listening');
      render();
      lastTapAt = -Infinity;
      return;
    }
    lastTapAt = now;
  });

  if (reduceMotion) {
    // The finished paragraph, still. The keycap still plays it on request.
    commit();
    return;
  }

  render();
  let played = false;
  new IntersectionObserver(
    ([entry]) => {
      if (played || !entry?.isIntersecting) return;
      played = true;
      playAutomatically();
    },
    // Well into view, not just its first pixel, so the visitor is looking at it.
    { threshold: 0.55 },
  ).observe(note);
}

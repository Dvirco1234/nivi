/**
 * Drives one recreated dictation: the words in a note, and the recording panel's
 * timer and waveform while it runs.
 *
 * It mirrors what the real app does, in the same order: the panel listens, the
 * words arrive in the note while you speak (live mode), and the stop tap commits
 * them. It never touches a microphone. The words come from the page.
 *
 * The caller decides what moves time forward: a clock, the scroll position, or the
 * visitor tapping the keycap. Two dictations can share one panel, as long as only
 * the active one is asked to move it.
 */

export type DemoPhase = 'idle' | 'listening' | 'committed';

export interface DictationParts {
  /** Gets data-demo-phase, so CSS can style each phase. Must contain `text`. */
  phaseTarget: HTMLElement;
  /** Holds the full sentence in the markup. Split into words on start. */
  text: HTMLElement;
  timer?: HTMLElement | null;
  bars?: HTMLElement[];
}

const PUNCTUATION = /([,.?!:;])/g;
/** About 150 words a minute, a relaxed speaking pace. */
export const SPOKEN_WORDS_PER_SECOND = 2.5;

export class DictationDemo {
  readonly wordCount: number;

  readonly #phaseTarget: HTMLElement;
  readonly #timer: HTMLElement | null;
  readonly #bars: HTMLElement[];
  readonly #wordElements: HTMLElement[] = [];
  #phase: DemoPhase | null = null;
  #shownWords = -1;

  constructor({ phaseTarget, text, timer = null, bars = [] }: DictationParts) {
    this.#phaseTarget = phaseTarget;
    this.#timer = timer;
    this.#bars = bars;

    // The words ship in the markup, so the sentence is readable without script.
    // Here they are split once into spans that can be shown one at a time.
    const words = (text.textContent ?? '').trim().split(/\s+/);
    text.textContent = '';
    for (const word of words) {
      const span = document.createElement('span');
      span.className = 'demo-word';
      span.innerHTML = word.replace(PUNCTUATION, '<b class="demo-punct">$1</b>');
      text.append(span, ' ');
      this.#wordElements.push(span);
    }
    this.wordCount = words.length;
    this.show(0, 'idle');
  }

  get phase(): DemoPhase {
    return this.#phase ?? 'idle';
  }

  /**
   * Shows the first `words` words in the given phase. Cheap to call every frame:
   * it only touches the DOM when something changed.
   */
  show(words: number, phase: DemoPhase): void {
    const count = Math.max(0, Math.min(this.wordCount, Math.round(words)));
    if (phase !== this.#phase) {
      this.#phase = phase;
      this.#phaseTarget.dataset['demoPhase'] = phase;
    }
    if (count !== this.#shownWords) {
      this.#wordElements.forEach((element, index) => {
        element.classList.toggle('is-shown', index < count);
      });
      this.#shownWords = count;
    }
  }

  /** Writes the panel's elapsed time. Only the active dictation should call it. */
  showTime(seconds: number): void {
    if (!this.#timer) return;
    const value = `0:${String(Math.floor(seconds)).padStart(2, '0')}`;
    if (this.#timer.textContent !== value) this.#timer.textContent = value;
  }

  /**
   * Moves the waveform. While listening, each bar gets a level that rises and
   * falls like speech; otherwise the bars rest as dots, as in the real panel.
   * Only the active dictation should call it.
   */
  animateLevels(timeSeconds: number): void {
    const listening = this.#phase === 'listening';
    this.#bars.forEach((bar, index) => {
      let level = 0.12;
      if (listening) {
        // Two slow waves and one fast one. Speech has syllables (fast) inside
        // phrases (slow), and a plain sine looks like a machine.
        const phrase = 0.55 + 0.45 * Math.sin(timeSeconds * 1.3 + index * 0.21);
        const syllable = 0.5 + 0.5 * Math.sin(timeSeconds * 9.1 + index * 1.7);
        const texture = 0.5 + 0.5 * Math.sin(timeSeconds * 4.3 - index * 0.9);
        level = 0.16 + 0.84 * phrase * (0.55 * syllable + 0.45 * texture);
      }
      bar.style.setProperty('--level', level.toFixed(3));
    });
  }
}

/** Seconds of speech for a given number of words. */
export function secondsFor(words: number): number {
  return words / SPOKEN_WORDS_PER_SECOND;
}

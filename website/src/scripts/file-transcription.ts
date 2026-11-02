/**
 * The file transcription pane. When it is well into view it "transcribes" once,
 * on time: the progress bar fills, then the paragraphs appear one by one. The
 * format picker changes the saved file name, the way the app names its exports.
 */
const TRANSCRIBE_MS = 2400;
const PARAGRAPH_GAP_MS = 260;

export function startFileTranscription(pane: HTMLElement): void {
  const percent = pane.querySelector<HTMLElement>('[data-files-percent]');
  const progress = pane.querySelector<HTMLElement>('[data-files-progress]');
  const paragraphs = [...pane.querySelectorAll<HTMLElement>('[data-files-paragraph]')];
  const savedName = pane.querySelector<HTMLElement>('[data-files-name]');

  // The format picker works whether or not the animation has run.
  for (const radio of pane.querySelectorAll<HTMLInputElement>('[data-files-format]')) {
    radio.addEventListener('change', () => {
      if (radio.checked && savedName) savedName.textContent = `${savedName.dataset['base'] ?? ''}.${radio.value}`;
    });
  }

  const finish = () => {
    pane.dataset['state'] = 'done';
    progress?.style.setProperty('--progress', '1');
    if (percent) percent.textContent = '100%';
    paragraphs.forEach((paragraph) => paragraph.removeAttribute('data-hidden'));
  };

  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    finish();
    return;
  }

  paragraphs.forEach((paragraph) => paragraph.setAttribute('data-hidden', ''));
  const run = () => {
    pane.dataset['state'] = 'working';
    const startedAt = performance.now();
    const frame = (now: number) => {
      // Eased, so it starts quickly and slows near the end, as real progress does.
      const share = Math.min(1, (now - startedAt) / TRANSCRIBE_MS);
      const eased = 1 - (1 - share) ** 2;
      progress?.style.setProperty('--progress', eased.toFixed(3));
      if (percent) percent.textContent = `${Math.round(eased * 100)}%`;
      if (share < 1) {
        requestAnimationFrame(frame);
        return;
      }
      pane.dataset['state'] = 'done';
      paragraphs.forEach((paragraph, index) => {
        setTimeout(() => paragraph.removeAttribute('data-hidden'), index * PARAGRAPH_GAP_MS);
      });
    };
    requestAnimationFrame(frame);
  };

  const observer = new IntersectionObserver(
    ([entry]) => {
      if (!entry?.isIntersecting) return;
      observer.disconnect();
      run();
    },
    { threshold: 0.5 },
  );
  observer.observe(pane);
}

/**
 * The page's scroll side effects. None of them holds the scroll.
 *
 *   data-in              fades a group in once, when it arrives
 *   data-stagger="60"    on a data-in group: its children arrive 60ms apart
 *   data-parallax="-0.6" drifts an element against the page as it passes.
 *                        The number is the total travel in hundreds of pixels;
 *                        negative moves up faster than the page.
 *   data-wipe="up"       reveals an element with a wipe as it comes into view
 *   data-wipe-at="0.1 0.5"  where the wipe starts and ends, as a share of the
 *                        element's trip through the screen
 *
 * Only transform, opacity and clip-path change, and only for elements on screen.
 * Under reduced motion, groups still fade in, and nothing moves.
 */

const clamp = (value: number, min = 0, max = 1) => Math.min(max, Math.max(min, value));

/** 0 when the element's top enters at the bottom, 1 when its bottom leaves at the top. */
function tripThroughScreen(element: Element): number {
  const box = element.getBoundingClientRect();
  return clamp((innerHeight - box.top) / (innerHeight + box.height));
}

export function startScrollEffects(): void {
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.documentElement.classList.add('has-scroll-effects');

  // Arrivals.
  const arrivals = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add('is-in');
        arrivals.unobserve(entry.target);
      }
    },
    // Slightly inside the bottom edge, so it fires when the visitor is looking.
    { rootMargin: '0px 0px -12% 0px' },
  );
  for (const group of document.querySelectorAll<HTMLElement>('[data-in]')) {
    const gap = Number(group.dataset['stagger'] ?? 0);
    if (gap > 0) {
      [...group.children].forEach((child, index) => {
        (child as HTMLElement).style.setProperty('--in-delay', `${index * gap}ms`);
      });
    }
    arrivals.observe(group);
  }

  if (reduceMotion) {
    // Wipes show their content straight away.
    for (const element of document.querySelectorAll<HTMLElement>('[data-wipe]')) element.style.clipPath = 'none';
    return;
  }

  // Movement, only for elements on screen.
  const moving = [...document.querySelectorAll<HTMLElement>('[data-parallax], [data-wipe]')];
  const onScreen = new Set<HTMLElement>();
  const watch = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      const element = entry.target as HTMLElement;
      if (entry.isIntersecting) onScreen.add(element);
      else onScreen.delete(element);
    }
  });
  moving.forEach((element) => watch.observe(element));

  const update = () => {
    for (const element of onScreen) {
      const trip = tripThroughScreen(element);
      const rate = element.dataset['parallax'];
      if (rate !== undefined) {
        element.style.transform = `translate3d(0, ${(Number(rate) * (trip - 0.5) * 100).toFixed(2)}px, 0)`;
      }
      const direction = element.dataset['wipe'];
      if (direction !== undefined) {
        const [from = 0.1, to = 0.5] = (element.dataset['wipeAt'] ?? '').split(' ').map(Number);
        const hidden = (1 - clamp((trip - from) / (to - from))) * 100;
        // "down" travels downward, so the top shows first and the bottom is cut.
        // "up" travels upward, so the bottom shows first and the top is cut.
        const edge = direction === 'down' ? `0 0 ${hidden}% 0` : `${hidden}% 0 0 0`;
        element.style.clipPath = `inset(${edge})`;
      }
    }
  };
  // Every frame, but only work when something on screen needs it.
  const frame = () => {
    requestAnimationFrame(frame);
    if (onScreen.size > 0) update();
  };
  requestAnimationFrame(frame);
}

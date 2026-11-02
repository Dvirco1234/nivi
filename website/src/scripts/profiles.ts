/**
 * The profile tabs. They follow the usual tab pattern: click or Enter selects,
 * arrow keys move between tabs, Home and End jump to the ends.
 *
 * While the list is on screen and nobody has touched it, it moves to the next
 * profile every few seconds, so a visitor who only scrolls still sees all three.
 * The first click, key press or hover hands control to the visitor for good.
 */
const CYCLE_MS = 3800;

export function startProfiles(root: HTMLElement): void {
  const tabs = [...root.querySelectorAll<HTMLButtonElement>('[data-profile-tab]')];
  const panels = [...root.querySelectorAll<HTMLElement>('[data-profile-panel]')];
  if (tabs.length === 0) return;

  let current = 0;
  const select = (index: number, moveFocus = false) => {
    current = (index + tabs.length) % tabs.length;
    tabs.forEach((tab, i) => {
      const on = i === current;
      tab.setAttribute('aria-selected', String(on));
      tab.tabIndex = on ? 0 : -1;
    });
    panels.forEach((panel, i) => {
      panel.hidden = i !== current;
    });
    if (moveFocus) tabs[current]?.focus();
  };

  let visitorTookOver = false;
  const takeOver = () => {
    visitorTookOver = true;
  };
  root.addEventListener('pointerenter', takeOver);
  root.addEventListener('focusin', takeOver);

  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => {
      takeOver();
      select(index);
    });
    tab.addEventListener('keydown', (event) => {
      // Up and down follow the list. Left and right follow the reading direction,
      // so on the Hebrew page the left arrow moves forward.
      const forward = document.documentElement.dir === 'rtl' ? 'ArrowLeft' : 'ArrowRight';
      const back = forward === 'ArrowLeft' ? 'ArrowRight' : 'ArrowLeft';
      const moves: Record<string, number> = {
        ArrowDown: current + 1,
        [forward]: current + 1,
        ArrowUp: current - 1,
        [back]: current - 1,
        Home: 0,
        End: tabs.length - 1,
      };
      const next = moves[event.key];
      if (next === undefined) return;
      event.preventDefault();
      takeOver();
      select(next, true);
    });
  });

  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  let visible = false;
  new IntersectionObserver(
    ([entry]) => {
      visible = entry?.isIntersecting ?? false;
    },
    { threshold: 0.5 },
  ).observe(root);

  setInterval(() => {
    if (visible && !visitorTookOver && !document.hidden) select(current + 1);
  }, CYCLE_MS);
}

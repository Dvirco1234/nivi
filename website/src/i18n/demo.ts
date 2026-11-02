import type { TFunction } from 'i18next';

/** The two sample dictations on the page. */
export type DemoLanguage = 'english' | 'hebrew';

export interface DemoNote {
  key: DemoLanguage;
  title: string;
  words: string;
  lang: string;
  dir: 'ltr' | 'rtl';
  /** The hotkey symbol this language uses in the example setup. */
  hotkey: string;
  keyName: string;
  result: string;
  keycapLabel: string;
}

const LANGUAGE = {
  english: { lang: 'en', dir: 'ltr', titleKey: 'demo.noteTitle' },
  hebrew: { lang: 'he', dir: 'rtl', titleKey: 'demo.hebrew.noteTitle' },
} as const;

/**
 * Which sample plays first. Each language file decides: a visitor sees their own
 * language in the hero and the other one second.
 */
export function demoOrder(t: TFunction): [DemoLanguage, DemoLanguage] {
  const order = t('demo.order', { returnObjects: true }) as unknown;
  if (Array.isArray(order) && order[0] === 'hebrew') return ['hebrew', 'english'];
  return ['english', 'hebrew'];
}

export function demoNote(t: TFunction, key: DemoLanguage): DemoNote {
  const { lang, dir, titleKey } = LANGUAGE[key];
  return {
    key,
    title: t(titleKey),
    words: t(`demo.${key}.words`),
    lang,
    dir,
    hotkey: t(`demo.${key}.key`),
    keyName: t(`demo.${key}.keyName`),
    result: t(`demo.${key}.result`),
    keycapLabel: t(`demo.${key}.keycapLabel`),
  };
}

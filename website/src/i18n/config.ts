/**
 * The languages the site is published in.
 *
 * To add a language: add a JSON file to ./locales with the same keys as en.json,
 * then add one entry here. To remove one, delete both. Pages, the language switch
 * and the hreflang links all read from this list.
 */
export const locales = {
  en: { label: 'English', shortLabel: 'EN', dir: 'ltr', htmlLang: 'en', ogLocale: 'en_US' },
  he: { label: 'עברית', shortLabel: 'עב', dir: 'rtl', htmlLang: 'he', ogLocale: 'he_IL' },
} as const;

export type Locale = keyof typeof locales;

/** Served at the site root. Every other language lives under /<code>/. */
export const defaultLocale: Locale = 'en';

export const localeCodes = Object.keys(locales) as Locale[];

export function isLocale(value: string | undefined): value is Locale {
  return value !== undefined && value in locales;
}

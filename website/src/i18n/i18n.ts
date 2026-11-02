import i18next, { type TFunction } from 'i18next';
import { defaultLocale, locales, localeCodes, type Locale } from './config';

// Every JSON file in ./locales is picked up by name, so the list in config.ts and
// the files on disk are the only two places a language is declared.
const files = import.meta.glob<{ default: Record<string, unknown> }>('./locales/*.json', {
  eager: true,
});

function messagesFor(locale: Locale): Record<string, unknown> {
  const file = files[`./locales/${locale}.json`];
  if (!file) throw new Error(`Missing translation file: src/i18n/locales/${locale}.json`);
  return file.default;
}

const instances = new Map<Locale, TFunction>();

/**
 * Returns the translate function for one language.
 *
 * Runs at build time only. The pages are static, so no translation code or
 * message file is sent to the browser.
 */
export function useTranslations(locale: Locale): TFunction {
  const cached = instances.get(locale);
  if (cached) return cached;

  const instance = i18next.createInstance();
  void instance.init({
    lng: locale,
    fallbackLng: defaultLocale,
    resources: Object.fromEntries(
      localeCodes.map((code) => [code, { translation: messagesFor(code) }]),
    ),
    initAsync: false,
    returnObjects: true,
    returnNull: false,
    interpolation: { escapeValue: false },
  });

  const t = instance.t.bind(instance) as TFunction;
  instances.set(locale, t);
  return t;
}

/** A list from the message file, such as the FAQ entries. */
export function translateList<T>(t: TFunction, key: string): T[] {
  const value: unknown = t(key, { returnObjects: true });
  return Array.isArray(value) ? (value as T[]) : [];
}

/** The site-relative path of the home page in a language, with the base path. */
export function homePath(locale: Locale): string {
  const base = import.meta.env.BASE_URL.replace(/\/$/, '');
  return locale === defaultLocale ? `${base}/` : `${base}/${locale}/`;
}

/** A file in /public, with the base path. */
export function assetPath(path: string): string {
  const base = import.meta.env.BASE_URL.replace(/\/$/, '');
  return `${base}/${path.replace(/^\//, '')}`;
}

export function directionOf(locale: Locale): 'ltr' | 'rtl' {
  return locales[locale].dir;
}

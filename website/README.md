# Nivi website

The marketing site for Nivi. It is a separate app in this repo, next to the macOS app
and its update feed. It is built with Astro, in two languages (English and Hebrew),
and it sends no request to anyone but itself.

## Run it

```sh
cd website
npm install
npm run dev       # http://localhost:4321/nivi/
npm run build     # type-checks, then writes the static site to dist/
npm run preview   # serves dist/ as it will be deployed
```

The site lives under `/nivi/` because GitHub Pages serves it at
`dvirco1234.github.io/nivi`. When it gets its own domain, build with
`SITE_URL=https://the-domain SITE_BASE=/` and nothing else changes.

**Astro 6, not 7.** Astro 7 needs Node 22.23.4 or newer, and this Mac has 22.23.1.
Moving to 7 is a one-line change in `package.json` once Node is updated.

**`node_modules` is a symlink** to `node_modules.nosync` on the owner's Mac, because
the repo sits in iCloud Drive and iCloud ignores anything named `.nosync`. On any
other machine, `npm install` makes a normal folder and that is fine.

## Where things are

```
website/
├── astro.config.mjs        site URL and base path, read from SITE_URL / SITE_BASE
├── public/images/          the app icon, the social preview, real app screens
└── src/
    ├── pages/[...locale]/  one page, built once per language
    ├── layouts/            the HTML document: head, meta, hreflang, fonts, engine
    ├── components/
    │   ├── layout/         header and footer
    │   ├── sections/       one file per section, in page order
    │   └── demo/           the recreated recording panel and note window
    ├── scripts/            the opening scene, the dictation demo, smooth scrolling
    ├── i18n/               the language list, the i18next helper, one JSON per language
    ├── data/release.ts     the current version and download link, read from ../version.mk
    └── styles/             design tokens, base styles and site-wide rules
```

## Text and languages

Every word on the page is in `src/i18n/locales/<language>.json`. Components never
hold copy.

**To add a language:** copy `en.json` to `<code>.json`, translate the values, and add
one entry to `src/i18n/config.ts` (its label, and `ltr` or `rtl`). The page, the
language switch and the `hreflang` links follow from that list. **To remove one,**
delete both.

The layout uses logical properties (`inline-start`, `block-end`, and so on), so a
right-to-left language mirrors without any extra CSS. The recreated app pieces
stay left to right on purpose, as the real app does, and the Hebrew note stays
right to left on the English page.

## The download link

`src/data/release.ts` reads `VERSION` from the app's `version.mk` at build time. After
`make release`, rebuild the site and the button points at the new DMG.

## How the page moves

**Nothing holds the scroll.** There are no pinned or sticky sections; only the
header is fixed. Every wheel step moves the page. The motion is layered on top:

- **The hero's dictation plays on a clock** (`scripts/hero.ts`), whether or not
  the visitor scrolls. Scrolling only adds depth: the window tilts flat and comes
  forward, the grid drifts slower than the page, the keyboard row slides away.
- **The visitor's own language plays first.** `demo.order` in each language file
  decides: English then Hebrew on the English page, Hebrew then English on the
  Hebrew page. `src/i18n/demo.ts` turns a language into its note, key and labels.
- **The second dictation plays once by itself** when its window is well into view
  (`scripts/language-moment.ts`), on time, not on scroll position. The keycap
  replays it with the app's gesture: two taps start, one tap pastes.
- **Profiles** (`scripts/profiles.ts`) are real tabs. They cycle while on screen
  until the visitor touches them. The three examples use the app's real models,
  modes and hotkeys.
- **File transcription** (`scripts/file-transcription.ts`) runs its progress
  once when in view. The format picker is a set of radio buttons, and the saved
  name follows the app's own rule ("interview.m4a" becomes
  "interview transcript.docx").
- **Sections fade in once** as they arrive, and the app screens drift slightly at
  different rates (`scripts/scroll-effects.ts`: `data-in`, `data-stagger`,
  `data-parallax`, `data-wipe`).
- **Smooth scrolling** (Lenis, `scripts/smooth-scroll.ts`) eases the wheel. It
  keeps the native scrollbar and keyboard scrolling, and turns itself off for
  reduced motion.

An earlier version pinned the opening for several screens and tied the words to
the scroll position. It read as the scroll getting stuck, so do not bring pinning
back.

## Rules this site keeps

- **The demo is honest.** The recording panel and the note are rebuilt in HTML from
  the real app's design and say "Sample dictation, recreated in your browser". The
  gesture is the app's real one: double tap to start, single tap to stop and paste.
  The page never listens to the real right Command key, because a visitor who has
  Nivi installed would start a real recording.
- **No invented proof.** The testimonials section is built but hidden while
  `testimonials.items` is empty. Add only real quotes from real people who agreed to
  be quoted. No made-up numbers either.
- **Nothing third-party.** Fonts are self-hosted through Fontsource. There is no
  analytics and no cookie. The footer says so, so keep it true.
- **Real screens only.** `public/images/app/` holds photographs of the real
  Preferences views, made with `Tools/make-pref-shots.sh`. Do not photograph the
  History or Files tabs for the site: that harness reads the real history on the Mac
  it runs on.
- **Reduced motion keeps meaning.** With motion turned off, the hero and the Hebrew
  act show their finished text, and every section is complete and still.
- Plain language, short sentences, no em dashes, in both languages.

## Deploying

`.github/workflows/website.yml` builds this site on every push to `main` that
touches `website/`, `docs/appcast.xml` or `version.mk`, and publishes it with
GitHub Pages at https://dvirco1234.github.io/nivi/. It can also be started by hand
from the Actions tab.

Pages also serves the app's update feed, and every installed copy of Nivi reads
it from `/nivi/appcast.xml`. `make release` still writes the feed to
`docs/appcast.xml`. The workflow copies it into the site at that same address
and refuses to publish if it is missing or is not valid XML. A release pushes a
new feed and a new `version.mk`, so the site and the download button update by
themselves.

`make release` also still regenerates `docs/index.html`, the old plain download
page. Pages no longer serves it, so that step can be removed from the release
flow when it is next touched.

// @ts-check
import { defineConfig } from 'astro/config';

// The site is served from GitHub Pages under the repo name until it gets its own
// domain. When it does, set SITE_URL to the domain and SITE_BASE to "/", and
// nothing else changes: every link goes through import.meta.env.BASE_URL.
const site = process.env.SITE_URL ?? 'https://dvirco1234.github.io';
const base = process.env.SITE_BASE ?? '/nivi';

export default defineConfig({
  site,
  base,
  trailingSlash: 'ignore',
  build: {
    // One folder per page (he/index.html), so /he/ works on any static host.
    format: 'directory',
    // Small stylesheets go inline. One request fewer on first paint.
    inlineStylesheets: 'auto',
  },
  // Nothing on this page is worth prefetching, and prefetching is a network
  // request the visitor did not ask for.
  prefetch: false,
  devToolbar: { enabled: false },
});

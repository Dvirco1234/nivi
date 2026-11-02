import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * The current release, read from the app's own version.mk at build time.
 *
 * version.mk is the one place the app's version lives, and `make release` rewrites
 * it. Reading it here means the download button can never point at an old DMG:
 * rebuild the site after a release and the link follows.
 */
const repository = 'Dvirco1234/nivi';

function readVersion(): string {
  // Astro runs from the website folder, so the app's version.mk is one level up.
  const versionFile = resolve(process.cwd(), '..', 'version.mk');
  const match = /^VERSION\s*:=\s*(\S+)/m.exec(readFileSync(versionFile, 'utf8'));
  if (!match?.[1]) throw new Error(`No "VERSION := x.y.z" line in ${versionFile}`);
  return match[1];
}

export const version = readVersion();

export const links = {
  dmg: `https://github.com/${repository}/releases/download/v${version}/Nivi-${version}.dmg`,
  releases: `https://github.com/${repository}/releases`,
  source: `https://github.com/${repository}`,
  licence: `https://github.com/${repository}/blob/main/LICENSE`,
  install: `https://github.com/${repository}/blob/main/INSTALL.md`,
} as const;

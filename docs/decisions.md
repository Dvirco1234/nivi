# Decisions

Things that are settled, and why. Read this before undoing something on purpose.

Each entry is the decision, when it was made, and the reason. If a decision has a
known escape hatch or a named fallback, that is written down too.

## The app is called Nivi

2026-08-27. It was Dictato until then.

The name comes from the Hebrew *niv*, a turn of phrase. It was picked after two
rounds of candidates and an availability check that killed most of the obvious
names: Utter, Mila, Murmur, Quill, Scribe, Verbatim and others are all already
small Mac dictation or transcription apps. See
[naming/2026-08-27-app-name-candidates.md](naming/2026-08-27-app-name-candidates.md).

**Renaming again after a public release would strand every install.** The bundle
id `com.dvir.nivi` is what macOS and Sparkle use to tell one app from another.
Change it and existing copies stop getting updates, both versions sit in
`/Applications`, and every permission has to be granted again. The rename was
done before 0.1.0 shipped for exactly this reason. Do not repeat it casually.

The name and bundle id live in two variables at the top of the Makefile, so a
rename is a short checklist rather than a repo-wide find and replace. The
checklist is in [release-pipeline.md](release-pipeline.md).

## One public repo, not a separate releases repo

2026-09-02.

Sparkle fetches the update feed and the DMG over plain HTTPS with no login, so a
private repo cannot serve them. The original plan was to keep the source private
and publish from a second public repo, `nivi-releases`.

The owner then decided to make the source public, which removes the whole reason
for the split. Now the appcast and the download page are committed files served
by GitHub Pages from `docs/`, and the DMG is a GitHub Release asset, all in
`Dvirco1234/nivi`.

The DMG is a release asset rather than a committed file because a disk image in
git history can never be removed.

## Working notes are private, research notes are public

2026-08-31, revised the same day.

The first pass moved all the design and research notes into a private repo. The
owner asked what was actually sensitive in them. The honest answer was almost
nothing: no email, no employer, no credentials, one absolute path, and his first
name, which is already in the bundle id.

So the research notes under `docs/` are public **on purpose**. They are good
engineering content and the reasoning is often more useful than the result.

Only two things stayed private, and they are workflow artifacts rather than
documents: `.claude/` and `.superpowers/sdd/`. They live in
`~/personal/dev-workspace`, a private repo with one folder per project, and are
symlinked into this repo at their normal paths.

## `audio_ctx` must be a multiple of 4

2026-08-26. Non-negotiable.

whisper.cpp's Metal kernels need the tensor row stride byte-aligned. For an F16
model the stride is `audio_ctx * 2`, so `audio_ctx` must divide by 4. A value in
between aborts the whole process:

    ggml-metal.m:1925: GGML_ASSERT(nb01 % 8 == 0) failed

whisper.cpp does not validate this. Its own `stream` example passes `-ac`
straight through.

This crashed the app when the encoder context started being sized from the live
audio slice rather than the configured window, which made it vary every pass.
Roughly three passes in four landed on a bad number. `Sources/NiviCore/AudioContext.swift`
now rounds up to a multiple of 4, and `isUsableAudioContext()` falls back to
whisper's full context if anything is out of range. Proven with a probe against
the real model: aborts at 257, 258, 259, 371, 629, 631; clean at 256, 260, 268,
372, 500, 628, 732, 1496, 1500; then 207 distinct values swept with zero aborts.

An abort inside a C library takes the whole app down and loses the dictation, so
a wrong number must always degrade rather than crash.

## whisper.cpp is pinned as a submodule at v1.7.2

2026-09-02.

The pin is not tidiness. This app reads whisper.cpp internals, such as the Metal
alignment rule above, which lives in `ggml-metal.m`. A newer whisper.cpp can
change that in a way the build still succeeds through and only fails at runtime.
A submodule records the exact commit; a setup script would drift.

To move to a newer whisper.cpp, check out the tag inside `vendor/whisper.cpp`,
commit the new submodule pointer, and re-test the encoder context path.

## Preferences does not use SwiftUI `Form`

2026-08-25.

The Spokenly look puts a small section heading on the window background,
**outside** the rounded card it belongs to. A grouped `Form` cannot do that; it
owns its own card and puts headings inside. `ModelsSection` and `ProfilesSection`
already hand-rolled their cards, so this was the established direction anyway.

The cost is that controls lose the compact sizing a grouped `Form` applies for
free. `PrefRow` sets `.controlSize(.small)` on its trailing slot in one place to
get it back.

Worth knowing so it is not re-litigated: a macOS switch has exactly one size and
ignores `.controlSize`. Nivi's switch is 36x16pt and so is Spokenly's. Any brief
asking for a 26x15pt switch is quoting an iOS number.

## The audio engine is kept between recordings

2026-09-06.

It used to be rebuilt for every recording, deliberately, because a reused engine
went stale when the audio route changed and recording silently failed.

That turned out to cost more than it saved. Touching `inputNode` makes macOS
build a hidden aggregate device behind the scenes and tear it down after. The log
showed 200 recordings in 2000 lines, so that happened 200 times. Measured over 40
record cycles, `coreaudiod` sat at 11.3% CPU afterwards with the old code and
2.4% with the new.

The engine is now rebuilt only when the wanted microphone changes, the system
default changes, or `AVAudioEngineConfigurationChange` fires, and it is dropped
after 90 seconds idle so an idle app leaves nothing behind. That keeps the
original protection without the churn.

## Microphone priority was kept, not deleted

2026-09-06.

It was the loudest symptom when the app hung, so deleting it was on the table.
It was kept, for two reasons. The hang stack was on `engine.inputNode`, which
runs **before** the device binding, so the feature was not the hang site. And in
a probe the same `AudioUnitSetProperty` call returned `noErr` 200 times out of
200 on the current hardware.

Its real fault was frequency and placement: an unsupported spelling of the call,
on the main thread, on every single recording, even when the device was already
correct. It now runs off the main thread, under the 8 second deadline, only on a
fresh engine, only when a priority list is actually set, and only when the device
differs. A failure logs and records with the system microphone.

**Named fallback:** if `Could not select <mic>` lines come back in the log,
replace the ordered list with a plain single "preferred microphone" picker that
sets nothing until the device is actually present.

## Transcript cleaning uses a shape rule, not a list

2026-09-02.

Whisper writes notes about sounds it heard rather than words:
`[BLANK_AUDIO]`, `(people chattering)`, `(gentle music)`, `[INAUDIBLE]`,
`*clears throat*`, and musical note characters. These were being pasted into the
user's documents.

The first attempt matched a list of known phrases. That list can never be
complete, which is exactly how `(people chattering)` got through after
`[BLANK_AUDIO]` was fixed. So the rule is now structural: anything fully wrapped
in `[]`, `()`, `**` or musical notes is a sound description and is removed.

**The deliberate side effect:** `"Call it (the new one) tomorrow"` becomes
`"Call it tomorrow"`. A dictated aside in brackets is lost. That trade was chosen
knowingly, because someone rarely speaks a standalone parenthetical, and when
they do want brackets they usually say the punctuation out loud, which whisper
writes as words. The cost is asymmetric: a dropped aside can be said again, but a
note that gets through is fake text in someone's Slack message.

There is a setting to turn it off, "Remove sound descriptions such as (music)",
on by default.

When the cleaned result is empty, the whole transcription takes the existing
"No speech detected" path: nothing pasted, nothing typed, no history entry.

## Cleaning runs before word replacement

2026-09-02. Both live in `TranscriptFinishing.finish`.

Two reasons. The model's notes are not words anyone said, so a user's rule should
never have to work around one or accidentally rescue one. And removing a note
closes the gap it leaves, so a whole-word rule still matches across it. There is
a test for exactly that case.

Every path calls the same function, so the live preview, the pasted text and the
history entry can never disagree.

## The Sparkle EdDSA private key must never be lost

2026-09-02.

It signs the update feed, which is what stops someone serving a malicious update
to Nivi's users. The public half is in the Makefile and safe to commit
(`SPARKLE_PUBLIC_KEY`). The private half is in the login keychain, item
"Private key for signing Sparkle updates", and has been exported and backed up.

**Every copy of Nivi ever installed carries the matching public key. If the
private half is lost, no existing install can ever be updated again.** Every user
would have to be asked to download the app by hand. Losing the Mac loses the key.

It is unaffected by renaming the app or changing the bundle id, because it signs
the feed rather than the app.

## Releases tag before uploading

2026-09-02.

The first 0.1.0 release failed at the last step with "tag already exists". The
publish step ran before the commit, so `gh release create` was handed a tag that
did not exist yet and GitHub invented one pointing at whatever `main` was at the
time. That is the commit before the version bump, so the local tag pointed
elsewhere and could never be pushed.

Publishing is now two steps, because the two constraints pull in opposite
directions: the feed files must exist before the commit that includes them, and
the upload must happen after the tag exists.

```sh
make publish STEP=feed     # writes docs/appcast.xml and docs/index.html
make publish STEP=upload   # attaches the DMG to the GitHub Release
```

`gh release create` also passes `--verify-tag` now, so a missing tag fails loudly
instead of being invented.

**The tradeoff:** a failed upload now leaves a pushed commit and tag behind, so
re-running `make release` stops on "tag already exists". Finish with
`make publish VERSION=<v> STEP=upload`.

## Signing happens outside iCloud Drive

2026-09-06.

This repo lives in iCloud Drive. iCloud's file provider keeps stamping folders
with a `com.apple.FinderInfo` extended attribute, and `codesign` refuses to sign
anything carrying one:
`resource fork, Finder information, or similar detritus not allowed`. The stamp
comes back faster than `xattr -c` can clear it, so signing in place failed at
random and eventually stopped `make dev` from working at all.

The Makefile now assembles and signs the bundle in a scratch folder under
`TMPDIR` (`STAGE_DIR`) and copies the signed result into `build/`. Copying a
bundle after it is signed is harmless.

It reads like an unnecessary detour. Simplifying it back to signing in place will
break the build in a way that looks random and costs a session to re-diagnose.

## The Layout and Debug tabs are absent from release builds

2026-09-02.

They are developer tools. Someone who downloads Nivi should never meet them. They
are removed entirely rather than disabled, gated on `#if DEBUG` in
`Sources/Nivi/DeveloperMode.swift`. `make dev` builds debug, `make app` and
`make release` build release.

A release build also **ignores `ui-tuning.conf` entirely** and uses the shipped
defaults. That file is written once by the Layout sliders, so on a stranger's Mac
it would pin the layout to their first-run day forever and a later layout fix
would reach nobody.

Verbose logging is forced off at launch in a release build, because it writes a
line for every global keystroke and there would be no visible switch to stop it.

**Escape hatch**, for running the release build day to day and still wanting the
sliders: `defaults write com.dvir.nivi showDeveloperTabs -bool true`. Read once at
launch, so it needs a restart.

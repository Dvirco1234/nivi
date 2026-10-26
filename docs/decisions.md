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
commit the new submodule pointer, and re-test the encoder context path. Since
2026-09-24 two more steps: check each patch in `vendor/patches/` against the new
version and delete the ones upstream has fixed, and run
`bash Tools/whisper-stress/run.sh`, which fails if whisper fell back to the CPU.
See "whisper.cpp bugs are fixed with carried patches" below.

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

Revised 2026-09-14: the engine and the queue that owns it now live together in a
`MicrophoneSession`, and a start that times out throws the whole session away.
See "A timed-out start retires the whole microphone session" below. Reuse between
normal recordings is unchanged.

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

## The look: grey icon, a small panel with a moving glow, a notch-height bar

2026-08-26. All three went back and forth before settling, mostly by the owner
looking at a screenshot and saying what was wrong. Do not undo them by accident.

**The app icon** is a grey tile with a white letter and a soft round highlight
near the top. It replaced a blue tile with a yellow letter. The highlight is a
real radial gradient that eases off, so it reads as a glow rather than a disc
with an edge. The bars either side of the letter are a darker grey green, not
white: at 16 points a white letter and white bars merged into one blob. The SVGs
are the source of truth; `make icon` regenerates the PNGs and the `.icns`.

**The recording panel** is deliberately small, 296x56pt, with rounder corners
and a border at 6% white, half a point wide, so it only hints at an edge. A thin
band of colour travels around the border while recording, so the panel looks
alive during a pause instead of freezing whenever nobody speaks. Speaking only
nudges the brightness, so a quiet voice gets the same motion as a loud one. The
glow is clipped to the panel's own rounded shape; unclipped, its blur filled the
window's square corners and the panel looked lopsided.

**The notch bar** is exactly as tall as the camera notch, read from
`NSScreen.safeAreaInsets.top`, and pinned to the notch's left edge rather than
centred, because its two sides are different widths. It pretends to be part of
the black plastic around the camera, so it shows one white language glyph and no
colour logo, and the left side holds only that glyph while the right holds a 60
point wave. On a display without a notch, the menu bar height stands in.

## Reliability comes before accuracy work, while friends start using Nivi

2026-09-14. The owner's call.

[state-of-the-project.md](state-of-the-project.md) ranked the Hebrew fast-finish
accuracy baseline first. That ranking suited one user. Once other people install
the app, a crash or a dead microphone costs more than a slightly worse
transcript, and the install experience (notarisation) matters more than either.
So crashes, hangs and the release came first, and the baseline waits.

## The watchdog only quits on silence it has watched

2026-09-14. The rule is `StallWatch` in core, with tests.

The watchdog measured with `Date()`. A sleeping Mac freezes the process while the
wall clock keeps going, so the first tick after waking saw "946 seconds stuck"
and quit a healthy app. Both self-quits in the log were this; one landed one
second before a `DarkWake` in `pmset -g log`.

Two guards now have to agree before the app stops itself. Time is measured on
`ProcessInfo.processInfo.systemUptime`, which stops while the Mac sleeps. And
the watch must have taken enough readings to have seen the silence for itself,
so a process frozen for any other reason comes back with one late tick, which is
not enough. Neither guard can hide a real stall: in a real stall the app runs,
its timer fires and the awake clock moves.

## A timed-out start retires the whole microphone session

2026-09-14.

On 14 September one start blocked inside CoreAudio for 27 minutes. `withDeadline`
gave up after 8 seconds, but that frees the caller, not the queue: the stuck call
still owned the recorder's only serial queue, so every later recording waited
behind it and failed without running.

A blocked Mach call cannot be cancelled, so the fix is to stop sharing. The
engine and its queue are one `MicrophoneSession`. When a start times out, the
session is marked retired and a fresh one takes its place, so the next recording
gets a queue of its own. A teardown queued behind the stuck call closes whatever
it opened, whenever it returns. The stuck call checks the retired mark before it
opens the microphone, so a start that returns minutes late never records with
nobody listening.

Rejected: a longer deadline (it only moves the wait), and repairing the session
in place (the queue cannot be freed while the call holds it).

## whisper.cpp bugs are fixed with carried patches

2026-09-24.

Two whisper.cpp v1.7.2 bugs hurt Nivi: a crash in ggml's graph allocator that the
streaming modes hit, and a Metal build step that breaks in a path with spaces.
Moving the pin would bring a large, untested change into the core of the app to
fix two small things. So the fixes live in `vendor/patches/`, `make vendor`
applies them and says so, and running it twice is safe.

The cost is that the submodule always shows as modified in `git status`. That is
expected. If the list of patches grows past two or three, move the pin instead.
Each patch, its evidence and its upstream status are in
[../vendor/patches/README.md](../vendor/patches/README.md).

## The macOS SDK is pinned to the running system

2026-09-24, moved into one script 2026-09-25.

A Command Line Tools update on 16 September repointed the default `MacOSX.sdk` at
`MacOSX27.0.sdk`. The bundled Swift toolchain cannot use it, and every SwiftUI
view failed with `plugin for module 'SwiftUIMacros' not found`, with no change in
Nivi. `Tools/pinned-sdk.sh` picks the SDK that matches the running macOS, and the
Makefile and every script that calls `swiftc` itself use it. Set `SDKROOT` to
override.

## AppKit places the Preferences window buttons

2026-09-25. Replaces the tunable button position added on 2026-08-24.

Nivi used to move the close, minimise and zoom buttons into the sidebar panel
with constraints, at a position tunable from the Layout tab. They were drawn in
the right place, but AppKit decides where the mouse counts as "over the buttons"
from its own position for them, and clips clicks to the 32 point titlebar they
had been pushed out of. Hover worked only on a 2 point strip and the bottom
3 points of each button took no clicks.

Now an empty `unified` toolbar makes the titlebar taller and AppKit places the
buttons itself, where its hover and click areas match what is drawn: 19 to 33
points from the top. The cost is that the buttons sit about 2 points higher and
3 points further left than the old tuned position, and the Traffic lights
sliders are gone. Do not bring back manual placement: whatever is drawn will
disagree with what AppKit tracks.

## Transcripts never go into SwiftUI's selectable `Text`

2026-10-08.

Clicking into `Text(...).textSelection(.enabled)` hands the whole string to
AppKit's field editor, which lays it out as one line. Past roughly 10,000
characters Core Text gives up and the app dies with
`CFRelease() called with NULL`. Measured in a harness: 10,000 characters
survived, 33,000 crashed. It crashed three times on a 67,248 character file
transcript.

Anything that can be long goes through `LongSelectableText`, a read-only
`NSTextView`, which handled the full 67,248 characters. A collapsed history card
that is long is not selectable at all; clicking it expands it. Short text, such
as a single dictation, may still use SwiftUI's selectable text.

## File transcripts are stored in paragraphs

2026-10-08. `TranscriptParagraphs` in core, with tests.

whisper returns one endless line, and a file transcript is many of those glued
together. Paragraphs close at the first sentence end after 600 characters and are
never longer than 2,000; a stretch with no sentence end is cut at a space.
Paragraph breaks are a blank line, so Copy gives readable text and Save as gets
real paragraphs. Formatting twice changes nothing.

Dictations are not split. They are short, and a paragraph break typed into
someone's message would be a surprise.

## Save as uses macOS's own document writers

2026-10-08.

The formats are Text (`.txt`), Word (`.docx`), Rich Text (`.rtf`) and
OpenDocument (`.odt`). `NSAttributedString` writes the three document formats, so
there is no new library to vendor, sign and keep up to date. PDF was left out:
`NSAttributedString` cannot write it, and Word can make one.

The text file holds only the transcript, so it pastes cleanly anywhere. The
document formats add a title (the file name) and one detail line with the date
and the audio length. Every paragraph is marked right to left or left to right
from its own letters, because Word otherwise lines Hebrew up on the left; the
title block follows the direction of the whole document. The font is Arial,
because the system font is saved under a private name Word does not know, and
Arial is on every Mac and Windows machine and covers Hebrew.

## File transcripts live in History and are shown in two places

2026-10-08.

There is one history file and one store. A file transcript is an entry with
`source == .file`, so search, retention and delete work the same for it as for a
dictation. It is shown twice: in History, headed by its file name and a document
icon so it no longer looks like a dictation, and under **Transcribed files** on
the Transcribe a file tab, where people look for it. Both use the same card,
`HistoryEntryCard`.

A transcript the user stopped part way is not saved to History. The result panel
says so instead of claiming it was saved, which it used to.

## The release clean check ignores edits inside the submodule

2026-10-08.

`make release` refuses to run on a dirty tree. With patches applied, the
whisper.cpp submodule always has edits, so the release could never start.
`check-clean` now passes `--ignore-submodules=dirty`. A change to which
whisper.cpp commit the submodule points at still counts as dirty.

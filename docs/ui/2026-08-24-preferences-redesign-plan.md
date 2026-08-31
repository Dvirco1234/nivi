# Preferences redesign plan

Date: 2026-08-24
Repo: `/Users/dvir/personal/nivi`
Status: plan only. No Swift code changed by this document.

## What this is

The Preferences window works but looks unfinished. Every tab is a plain SwiftUI
`Form { Section { ... } }` with `.formStyle(.grouped)`, except Models and
Profiles which already hand-roll cards. There are no page titles, no
descriptions, and no visual grouping inside a tab.

This plan does four things:

1. Maps what Nivi already has, so we extend instead of rebuild.
2. Defines a small shared design system for Preferences.
3. Writes the exact title, description and section headings for all nine tabs.
4. Designs the two new features: Transcribe File and History.

The reference is Spokenly. The look we are copying:

- Large page title top left of the detail pane.
- One grey sentence under it.
- Named group headings sitting outside and above rounded cards.
- Rows with a leading grey SF Symbol, a label, an optional grey caption, and the
  control pushed to the far right.
- Thin dividers between rows inside a card.
- Blue accent, orange warning banner, red for destructive text.
- Version string at the bottom of the sidebar.

Nivi already matches Spokenly on the window chrome: inset rounded sidebar
panel, traffic lights inside it, no tab name in the titlebar, rounded window
corners.

---

## Table of contents

1. [Step 1: what already exists](#step-1-what-already-exists)
2. [Step 2: the Preferences design system](#step-2-the-preferences-design-system)
3. [Step 3: per-tab titles, descriptions and sections](#step-3-per-tab-titles-descriptions-and-sections)
4. [Step 4: the two new features](#step-4-the-two-new-features)
5. [Step 5: PR sequence](#step-5-pr-sequence)
6. [Step 6: risks and constraints](#step-6-risks-and-constraints)

---

## Step 1: what already exists

I read the code before proposing anything. This section is the reuse-first map.
Read it before writing a line of the new features.

### Files that matter

| File | What it holds |
| --- | --- |
| `Sources/Nivi/PreferencesWindow.swift` | The `NSWindow`, rounded corners, traffic-light repositioning. |
| `Sources/Nivi/Preferences/SettingsView.swift` | Sidebar, `PrefSection` enum, and the General / Hotkeys / Speech / Debug tab bodies. |
| `Sources/Nivi/Preferences/ModelsSection.swift` | Dictation Models tab. Already hand-rolls cards, not a `Form`. |
| `Sources/Nivi/Preferences/ProfilesSection.swift` | Profiles tab. Also already hand-rolls cards. |
| `Sources/Nivi/Preferences/LayoutTuningSection.swift` | Layout tab. Live sliders over `UITuning`. |
| `Sources/Nivi/Preferences/RecordingDisplayPicker.swift` | The Panel / Notch thumbnail picker. |
| `Sources/Nivi/Preferences/HotkeyRecorderView.swift` | Hotkey capture control. |
| `Sources/Nivi/Preferences/ModelTestSheet.swift` | "Test it" sheet for a model. |
| `Sources/Nivi/UITuning.swift` | Live-tunable layout numbers, backed by `ui-tuning.conf`. |
| `Sources/NiviCore/Settings.swift` | All user settings, `UserDefaults` backed. |
| `Sources/NiviCore/ModelCatalogStore.swift` | `ModelPaths.appSupportBase()` lives here. |
| `Sources/Nivi/DictationController.swift` | The whole dictation flow and state machine wiring. |
| `Sources/Nivi/AudioRecorder.swift` | Mic capture, converts to 16 kHz mono Float32. |
| `Sources/Nivi/RecognizerCache.swift` | LRU of loaded whisper contexts, keyed by model id. |
| `Sources/Nivi/ModelTester.swift` | Records a clip and transcribes it off the dictation state machine. Good precedent. |

### Where the app keeps its data

`ModelPaths.appSupportBase()` returns
`~/Library/Application Support/Nivi`. It already holds `models.json`,
`models/`, and `ui-tuning.conf`. New per-user data goes here too. Logs are
separate, at `~/Library/Logs/Nivi` (`Log.logDirectory`).

### Spokenly features: already there vs genuinely new

| Spokenly feature | Nivi today | Verdict |
| --- | --- | --- |
| Use Escape to cancel recording | `Settings.cancelBinding` defaults to `keyCombo(keyCode: 53)`, which is Escape. `HotkeyRecorderView` already edits it. `HotkeyRouter` already listens. | **Exists.** We only add an on/off toggle that swaps between the recorded key and "off". No new key handling. |
| Play sound effects | `Settings.playSounds` plus `SoundPlayer.playStart/playStop`, already called from `DictationController`. | **Exists.** Only the row needs a new look. |
| Copy dictated text to clipboard | `TextInserter.insert(...)` always writes the clipboard, and `Settings.copyOnly` turns off the paste. | **Exists.** Only relabelled. |
| Recording display (Panel / Notch thumbnails) | `RecordingDisplayPicker` renders two live-drawn thumbnails with a blue outline on the selected one. | **Exists, and it is already the Spokenly design.** Reuse as-is inside the new row. |
| Launch at login | `LoginItem` plus a toggle in General and a menu-bar item. | **Exists.** |
| Text Input Method (Paste vs type) | `TextInserter` has both paths: `insert(...)` posts Cmd-V, `typeUnicode(...)` types key events. `InsertionMode.inAppLive` already uses the typing path. | **Mostly exists.** New work is only a picker that chooses the path for batch mode. |
| Word Replacements | Nothing. | **New.** Pure text logic, belongs in `NiviCore`. |
| Appearance (System / Light / Dark) | Nothing. `NSApp.appearance` is never set. | **New.** Small. |
| Show in Dock | Nothing. `AppDelegate` hardcodes `NSApp.setActivationPolicy(.regular)`. | **New.** Small, with one real quirk (see risks). |
| Show in Status Bar | Nothing. `MenuBarController` always creates the status item. | **New.** Small, but needs a guard so both cannot be off at once. |
| Microphone Priority Settings | Nothing. `AudioRecorder` builds a fresh `AVAudioEngine` per recording and uses whatever the system default input is. | **New, and the most expensive item in this plan.** See risks. |
| Mute while recording | Nothing. | **New.** Changes system output volume, needs careful restore. |
| Trackpad feedback | Nothing. | **New.** `NSHapticFeedbackManager`, cheap. |
| Language picker (app UI language) | Nothing. The app has no localization files and no asset catalog, and cannot get one without Xcode. | **Recommend dropping.** A picker with one option is worse than no picker. The useful language choice already exists per profile in Profiles. |
| Transcribe File | Nothing. | **New.** See Step 4. |
| History | Nothing. | **New.** See Step 4. |
| Version string in sidebar | Nothing, but `Info.plist` has `CFBundleShortVersionString` 0.1.0 and `CFBundleVersion` 1. | **New, trivial.** Read both from the bundle. |

### One correction to the brief

The brief says `copyOnly` is never consulted in `inserter.insert(...)`. That is
not what the code does. `Sources/Nivi/TextInserter.swift:26` reads:

```
let willPaste = autoPaste && !copyOnly && PermissionManager.accessibilityGranted
```

So `copyOnly` is consulted, and `DictationController.swift:349` passes it in.
I found no bug there. Nothing in this plan tries to fix it. If there is a real
report behind that claim, it is about some other path and should be filed
separately.

### What already looks right and must not be thrown away

- `ModelsSection` and `ProfilesSection` already use `ScrollView` plus
  `VStack(spacing: UITuning.cardSpacing)` plus cards with
  `.background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: UITuning.cardCorner))`
  and a stroked overlay. The new design system should generalize exactly that,
  not invent a second card style beside it.
- `UITuning` already owns `contentPadding`, `cardSpacing`, `cardPadding` and
  `cardCorner`. Those are the card tokens. Do not create duplicates.

---

## Step 2: the Preferences design system

Goal: every tab is built from the same handful of parts, so a new tab costs
about twenty lines and looks right by default.

New file: `Sources/Nivi/Preferences/PrefKit.swift` for the components, and
`Sources/Nivi/Preferences/PrefTheme.swift` for the colour tokens. Both stay
in the app target, not `NiviCore`, because they import SwiftUI and AppKit.

### Decision: drop `Form` and `.formStyle(.grouped)`

Keep hand-rolled cards. Reasons, in order of weight:

1. The look we want puts the group heading **outside** the card. Grouped `Form`
   renders a section header as a small label glued to the top of its own inset
   box. There is no supported way to move it out.
2. Grouped `Form` owns the card fill, the corner radius, the row insets and the
   row separators. Overriding them means fighting the style on every row, and
   the result breaks on the next macOS release.
3. Two of the seven existing tabs (Models, Profiles) already hand-roll cards.
   Keeping `Form` for the rest guarantees the window never looks like one app.
4. Rows with a leading icon plus a title plus a caption plus a trailing control
   need explicit layout anyway. `Form` gives us nothing there.

Cost of hand-rolling, stated honestly: we lose `Form`'s automatic label
alignment, its keyboard focus ring behaviour, and its free light-mode
appearance. The first two we replace with fixed layout constants. The third is
handled by using semantic `NSColor` values instead of hardcoded white opacities
(see the theme below).

### Components

All signatures below are the intended shape, not final Swift.

```swift
/// The whole detail pane for one tab: title, description, scrolling content.
struct PrefPage<Content: View>: View {
    init(title: String,
         description: String,
         @ViewBuilder content: () -> Content)
}
```

Renders: `Text(title).font(.largeTitle.weight(.bold))`, then
`Text(description).font(.callout).foregroundStyle(.secondary)`, then a
`ScrollView` with `VStack(alignment: .leading, spacing: PrefTheme.groupSpacing)`
holding the content. Outer padding is `UITuning.contentPadding`. The title
block scrolls with the content, which is what Spokenly does.

```swift
/// One named group: a plain heading on the window background, then a card.
struct PrefGroup<Content: View>: View {
    init(_ heading: String? = nil,
         footer: String? = nil,
         @ViewBuilder content: () -> Content)
}
```

Renders the heading as `Text(heading).font(.subheadline.weight(.semibold))`
with `.foregroundStyle(.secondary)`, then the card, then the optional footer as
a caption below the card. The card is
`RoundedRectangle(cornerRadius: UITuning.cardCorner)` filled with
`PrefTheme.cardFill` and stroked with `PrefTheme.cardStroke`.

Dividers between rows: insert a hairline between children but not after the
last one. Two ways to do this.

- Preferred: `_VariadicView.Tree` with a small layout root that walks the
  children and puts a `Divider()` between them. This is an underscored API. It
  has been stable for years and is widely used, but it is not public. If it
  ever breaks, the fallback is mechanical.
- Fallback: the caller writes `PrefDivider()` between rows by hand. Ugly but
  cannot break.

Start with `_VariadicView.Tree`. Keep `PrefDivider` public so the fallback is a
find-and-replace, not a redesign.

```swift
/// One row: leading icon, title, optional caption, trailing control.
struct PrefRow<Trailing: View>: View {
    init(icon: String,                 // SF Symbol name
         _ title: String,
         caption: String? = nil,
         captionStyle: PrefCaptionStyle = .normal,   // .normal | .warning
         @ViewBuilder trailing: () -> Trailing)
}
```

Layout: icon in a fixed `PrefTheme.rowIconWidth` column, tinted
`.secondary`; a `VStack(alignment: .leading, spacing: 2)` with the title and
the caption; `Spacer()`; then the trailing view. Vertical padding
`PrefTheme.rowVerticalPadding`, horizontal padding `UITuning.cardPadding`.

Convenience wrappers over `PrefRow`, so a toggle row is one line:

```swift
struct PrefToggleRow: View {
    init(icon: String, _ title: String, caption: String? = nil, isOn: Binding<Bool>)
}

struct PrefPickerRow<Value: Hashable>: View {
    init(icon: String, _ title: String, caption: String? = nil,
         selection: Binding<Value>,
         options: [Value],
         label: @escaping (Value) -> String)
}

struct PrefStepperRow: View {
    init(icon: String, _ title: String, caption: String? = nil,
         value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         format: @escaping (Int) -> String)
}

/// Read-only "label on the left, value on the right".
struct PrefValueRow: View {
    init(icon: String, _ title: String, caption: String? = nil, value: String)
}

/// A row that opens a sub-page. Renders a ">" chevron on the right.
struct PrefDisclosureRow: View {
    init(icon: String, _ title: String, caption: String? = nil, value: String? = nil,
         action: @escaping () -> Void)
}

/// A row whose control is a button, including destructive ones.
struct PrefButtonRow: View {
    init(icon: String, _ title: String, caption: String? = nil,
         buttonTitle: String, role: ButtonRole? = nil, action: @escaping () -> Void)
}
```

Banner, for the orange pill at the top of a tab:

```swift
struct PrefBanner: View {
    enum Style { case info, warning, danger }
    init(_ style: Style, icon: String, title: String, message: String,
         actionTitle: String? = nil, action: (() -> Void)? = nil)
}
```

Empty states, used by History and Transcribe File:

```swift
struct PrefEmptyState: View {
    init(icon: String, title: String, message: String)
}
```

### Sub-pages

Word Replacements is a sub-page reached from a `PrefDisclosureRow`. Wrap the
detail pane in a `NavigationStack` inside `SettingsView.detail`, and make
`PrefDisclosureRow` render as a `NavigationLink` when given a destination.
Reset the stack whenever the sidebar selection changes, so switching tabs never
leaves you inside a sub-page of a tab you left.

### Colour tokens: `PrefTheme`, not `UITuning`

`UITuning` is a `CGFloat`-only, file-backed, live-tunable system for layout
numbers. Colours are not tuned by eye per install, and they are not `CGFloat`.
Putting them there would mean widening the file format for no gain. So:

- **Numbers go in `UITuning`.** Extend the existing `shipped` table. Do not
  create a parallel spacing system.
- **Colours go in `PrefTheme`.** A plain `enum` of `static let` values.

New `UITuning.shipped` entries to add (names and starting values):

| Key | Value | Note |
| --- | --- | --- |
| `groupSpacing` | 22 | gap between one group and the next |
| `groupHeadingGap` | 7 | gap between a group heading and its card |
| `pageTitleGap` | 4 | gap between the page title and its description |
| `pageHeaderBottom` | 22 | gap below the description before the first group |
| `rowVerticalPadding` | 10 | padding above and below a row's content |
| `rowIconWidth` | 22 | width of the leading icon column |
| `rowMinHeight` | 34 | minimum row height, keeps single-line rows even |

They then show up automatically in the Layout tab sliders and in
`ui-tuning.conf`, because both are generated from `shipped`. That is the whole
point of respecting the existing system.

`PrefTheme` contents:

```swift
enum PrefTheme {
    // Surfaces. Semantic NSColors so light mode is not broken by the new
    // Appearance picker.
    static let cardFill    = Color(nsColor: .controlBackgroundColor).opacity(0.55)
    static let cardStroke  = Color(nsColor: .separatorColor)
    static let rowDivider  = Color(nsColor: .separatorColor).opacity(0.7)

    // Meaning.
    static let accent      = Color.accentColor      // selected sidebar row, on toggles
    static let warning     = Color.orange           // banner, hotkey conflicts
    static let danger      = Color.red              // destructive captions and buttons
    static let iconTint    = Color.secondary
    static let online      = Color.green            // active microphone dot

    // Numbers, read through so call sites never touch UITuning directly.
    static var groupSpacing: CGFloat      { UITuning.value("groupSpacing") }
    static var groupHeadingGap: CGFloat   { UITuning.value("groupHeadingGap") }
    static var rowVerticalPadding: CGFloat { UITuning.value("rowVerticalPadding") }
    static var rowIconWidth: CGFloat      { UITuning.value("rowIconWidth") }
    static var rowMinHeight: CGFloat      { UITuning.value("rowMinHeight") }
}
```

One important change while doing this: `ModelsSection` and `ProfilesSection`
currently use `.white.opacity(0.04)` and `.white.opacity(0.08)` directly. Move
them onto `PrefTheme.cardFill` and `PrefTheme.cardStroke` in the same PR, or
the app will have two card styles that drift apart. Hardcoded white opacities
also look wrong in light mode, which matters once Appearance ships.

### Sidebar changes

- Add the version string at the bottom, above the window edge:
  `v0.1.0 (1)`, read from `CFBundleShortVersionString` and `CFBundleVersion`.
  Style: `.caption`, `.secondary`, centred, padded `10`.
- Add the two new tabs to `PrefSection`, in this order: General, Dictation
  Models, Profiles, Hotkeys, Speech, **Transcribe File**, **History**, Layout,
  Debug. Icons: `doc.badge.arrow.up` for Transcribe File, `clock.arrow.circlepath`
  for History.

---

## Step 3: per-tab titles, descriptions and sections

Every string below is final user-facing copy. Use it verbatim.

### General

- Title: **General**
- Description: **Set up how Nivi behaves and where your dictated text goes.**

**Interface**

| Icon | Row | Control |
| --- | --- | --- |
| `circle.lefthalf.filled` | Appearance | Picker: System, Light, Dark |
| `dock.rectangle` | Show in Dock | Toggle |
| `menubar.arrow.up.rectangle` | Show in the menu bar | Toggle |
| `power` | Start Nivi when I log in | Toggle (existing `LoginItem`) |

Footer under the card: *Nivi needs at least one of the Dock icon and the
menu bar icon, so you can always reach it.*

**Recording display**

One row, no icon column, using the existing `RecordingDisplayPicker`:
title **Recording display**, caption **Choose how the dictation window looks
while you speak.**

Footer: *Panel floats near the bottom of the screen. Notch hugs the top, and
merges with the MacBook notch where there is one.*

**Behaviour**

| Icon | Row | Control |
| --- | --- | --- |
| `rectangle.on.rectangle` | Show the recording window | Toggle (`showOverlay`) |
| `escape` | Press Esc to cancel a recording | Toggle (turns `cancelBinding` on or off) |
| `timer` | Stop recording after | Stepper, minutes (`maxRecordingSeconds`) |

**Audio and feedback**

| Icon | Row | Control |
| --- | --- | --- |
| `speaker.wave.2` | Play a sound when recording starts and stops | Toggle (`playSounds`) |
| `speaker.slash` | Mute other audio while recording | Toggle |
| `hand.tap` | Vibrate the trackpad when recording starts | Toggle |

Footer: *Trackpad feedback only works on trackpads that support Force Touch.*

**Text handling**

| Icon | Row | Control |
| --- | --- | --- |
| `arrow.down.doc` | How text is inserted | Picker: Paste (Cmd-V), Type it out |
| `doc.on.clipboard` | Copy to the clipboard only, never paste | Toggle (`copyOnly`) |
| `eye.slash` | Keep dictated text out of clipboard history | Toggle (`excludeFromClipboardHistory`) |
| `text.badge.checkmark` | Word replacements | Disclosure row, shows "3 rules" |

Footer: *Pasting is faster. Typing it out is slower but does not touch your
clipboard, and works in apps that block paste.*

**Microphone priority**

A reorderable list, not a card of rows. Heading **Microphone priority**,
caption under the list: *Nivi tries these microphones in order and uses the
first one that is plugged in. Drag to reorder.* Each entry shows the device
name, a green dot when it is the one in use, and a greyed-out mic-slash icon
when it is not connected.

### Dictation Models

- Title: **Dictation models**
- Description: **Download the speech models Nivi runs on your Mac. Nothing is sent anywhere.**

Keep the existing card list. Wrap it in `PrefPage`. The "Add model" button
moves into a group heading row on the right of the heading **Installed and
available**.

Groups:

- **Installed and available** (the existing model cards, with the Add button in
  the heading row)
- **Storage** with rows: *Where models are saved* (`PrefValueRow` showing the
  path, plus a Reveal in Finder button row) and *Space used by models*.

### Profiles

- Title: **Profiles**
- Description: **A profile ties one hotkey to one model and one language. Make one per language you dictate in.**

Groups:

- **Your profiles** (the existing profile cards, Add button in the heading row)
- **Cancel** with one row: the cancel hotkey recorder, caption *This key stops a
  recording in any app.*

Empty state, when no model is installed: `PrefEmptyState` with
title **No models yet**, message **Install a model in Dictation models first,
then come back here.**

### Hotkeys

- Title: **Hotkeys**
- Description: **The keys that start, stop and cancel a recording.**

Groups:

- **Cancel** with the existing `HotkeyRecorderView` row.
  Footer: *Works in any app while a recording is running.*
- **Dictation hotkeys** with a `PrefDisclosureRow` per profile showing the
  profile name and its key, which opens the Profiles tab.
  Footer: *Each profile has its own key. Edit them in Profiles.*

### Speech

- Title: **Speech**
- Description: **How Nivi loads models and how fast the live preview updates.**

Groups:

- **Audio** with one read-only row: *Sample rate*, value **16 kHz**.
  Footer: *Nivi always records at 16 kHz mono, which is what the speech
  models expect.*
- **Memory** with rows *Models kept in memory* (stepper 1 to 4) and
  *Release the model after* (stepper 0 to 30 minutes, 0 shows "Never").
  Footer: *Keeping more models loaded lets you switch instantly, but uses more
  RAM. Releasing frees about 1.6 GB; the model reloads in about a second on
  your next dictation.*
- **Live preview** with rows *Minimum gap between updates* (ms) and
  *Live preview window* (seconds).
  Footer: *Live modes re-transcribe only the last few seconds each pass, so the
  preview keeps up however long you speak. A shorter window is faster. A longer
  one gives the model more context to correct itself.*

### Transcribe File

- Title: **Transcribe a file**
- Description: **Drop an audio or video file here and Nivi turns it into text, all on this Mac.**

See Step 4 for the layout. Groups:

- (no heading) the drop zone
- **Settings for this job** with rows *Model*, *Language*, and
  *Split long files into chunks of* (minutes)
- **Result** which only appears once a job has finished

### History

- Title: **History**
- Description: **Everything you have dictated, kept on this Mac only.**

Groups:

- (no heading) the filter and search bar
- (no heading) the list of entries
- **History settings** with rows *Keep history* (toggle),
  *Delete entries older than* (picker: 7 days, 30 days, 90 days, 1 year,
  Keep forever), and *Delete all history* (destructive button row).

Footer under History settings: *History is a plain text file on this Mac. It is
never uploaded. Audio is never saved, only the text.*

Empty state: title **Nothing here yet**, message **Dictate something, or
transcribe a file, and it will show up here.**

### Layout

- Title: **Layout**
- Description: **Developer sliders for the window's spacing. Changes save to ui-tuning.conf.**

Groups:

- **Spacing** with the existing sliders, one per `UITuning.shipped` entry.
- **Values** with the existing Copy values and Reset buttons as
  `PrefButtonRow`s.

### Debug

- Title: **Debug**
- Description: **Extra detail for tracking down problems. Leave these off day to day.**

Groups:

- **Show extra detail** with rows *Show how long transcription took*,
  *Show how long the recording was*, *Write verbose logs*.
- **Logs** with rows *Open the log folder* (button) and *Log folder*
  (`PrefValueRow` with the path).

### Banner rules

Banners use `PrefBanner` and sit above the first group.

- Top of **General**, warning, only when neither Dock nor menu bar is shown:
  title **Nivi is hidden**, message **Turn on the Dock icon or the menu bar
  icon so you can open Preferences again.**
- Top of **Profiles**, warning, when Accessibility is not granted:
  title **Nivi cannot paste yet**, message **Give Nivi Accessibility
  access so it can paste into other apps.** Action: **Open Settings**.
- Top of **Hotkeys**, warning, when Input Monitoring is not granted:
  title **Esc to cancel is not working**, message **Give Nivi Input
  Monitoring access so it can see the Escape key in other apps.**
  Action: **Open Settings**.
- Top of **History**, info, when history is turned off:
  title **History is off**, message **Nothing new is being saved.**

---

## Step 4: the two new features

### 4A. Transcribe File

#### What the tab looks like

Top: a large dashed drop zone, about 200 points tall, full width, corner radius
`UITuning.cardCorner`, dashed stroke in `PrefTheme.cardStroke` that turns
`PrefTheme.accent` while a file is dragged over it. Inside, centred: a
`doc.badge.arrow.up` icon, the text **Drop a file here**, a smaller line
**or click to choose one**, and a row of small grey format chips.

Chips: `MP3  WAV  M4A  AAC  AIFF  CAF  FLAC  MP4  MOV  M4V`.

Under the zone: the settings group (model, language, chunk size), then the
progress area while a job runs, then the result group.

#### Which formats really work

Nivi feeds whisper.cpp 16 kHz mono `Float32` samples. Everything below uses
`AVFoundation`, which is already linked by `AudioRecorder.swift`. No new
dependency.

Use **`AVAssetReader`** for every file, including audio-only ones. It opens
whatever the system's Core Media decoders handle, and unlike `AVAudioFile` it
also opens video containers and pulls just the audio track out.

Works:

- `.wav`, `.aiff`, `.aifc`, `.caf` (uncompressed and common compressed forms)
- `.mp3`
- `.m4a`, `.aac`, `.m4b` (AAC and Apple Lossless)
- `.flac` (macOS 11 and later)
- `.mp4`, `.mov`, `.m4v` (audio track extracted)

Does not work, and we should say so rather than fail silently:

- `.ogg`, `.opus`, `.webm`, `.wma`, `.amr`. Core Media does not decode these.
- Files with DRM, for example songs bought before 2009 or Apple Music files.
- A video file that has no audio track at all.
- Some `.mkv` files. The container is not supported even when the codec inside
  is.

Handling: before starting, check that the asset has at least one audio track
and that it is readable. If not, show a `PrefBanner` in danger style with
title **Nivi cannot read this file** and a message naming the reason:
**No audio track in this file** or **This file format is not supported. Try
converting it to MP3 or WAV first.**

#### Decode and resample

`AVAssetReader` can do the resampling for us. Point an
`AVAssetReaderAudioMixOutput` at the audio tracks with these settings:

```
AVFormatIDKey:            kAudioFormatLinearPCM
AVSampleRateKey:          16000
AVNumberOfChannelsKey:    1
AVLinearPCMBitDepthKey:   32
AVLinearPCMIsFloatKey:    true
AVLinearPCMIsNonInterleaved: false
AVLinearPCMIsBigEndian:   false
```

Then loop `copyNextSampleBuffer()`, pull the `CMBlockBuffer` bytes, and append
`Float` values. That gives exactly the format `WhisperCppRecognizer.transcribe`
already takes. No `AVAudioConverter` needed, no second resampling path to keep
in sync with `AudioRecorder`.

Memory cost, stated plainly: 16 kHz mono `Float32` is 64 KB per second, so
3.84 MB per minute. A one-hour file is about 230 MB held in a Swift array.
That is fine on an Apple Silicon Mac but not free. If we ever want to support
multi-hour files, the fix is to decode chunk by chunk instead of decoding the
whole file first. Design the service so the decode loop already yields chunks,
and the whole-file array is just the simple first implementation.

#### Chunking, progress and cancellation

whisper.cpp handles long audio internally, but a single `whisper_full` call on
an hour of audio gives us no progress and no way to stop. So split the work.

- Split the samples into chunks of `chunkMinutes` (default 5, range 1 to 15).
- Pick each cut point at the quietest 200 ms window inside a search band around
  the nominal boundary, so we cut in a pause instead of mid-word. This is pure
  arithmetic over a `[Float]` array, so it lives in `NiviCore` as
  `AudioChunkPlanner` and gets real tests.
- Transcribe chunks one after another through the existing `RecognizerCache`.
  Join the results with a space.
- Progress is `chunksDone / chunkCount`, shown as a `ProgressView` plus a line
  like **Chunk 3 of 12** and a rough time-left estimate from the average of the
  chunks done so far.
- Cancellation is checked between chunks and inside the decode loop. A `Cancel`
  button next to the progress bar. Cancelling keeps whatever text was produced
  so far and marks it as partial.

Honest note on quality: cutting into chunks costs a little accuracy at each
seam, because the model loses context across the cut. Cutting on silence keeps
that small. A single whole-file pass would be slightly better but gives no
progress and no cancel, which is the wrong trade for a file that takes minutes.

Honest note on speed: expect minutes, not seconds. On Apple Silicon with
`large-v3-turbo` this runs several times faster than real time, so a one-hour
recording is a coffee break, not an instant. Say so in the UI while it runs.

#### Not blocking dictation, not stealing the microphone

This is the rule the design must not break.

- `FileTranscriptionService` is a separate `@MainActor ObservableObject`. It
  never touches `AudioRecorder`, never touches `DictationStateMachine`, and
  never calls anything on `DictationController`. Same shape as `ModelTester`,
  which already proves the pattern works.
- No microphone is involved at all, so there is nothing to steal.
- The one shared resource is `RecognizerCache`, which is an `actor` and
  therefore serializes. A long chunk in flight will delay a dictation's final
  pass by up to one chunk. Fix it the same way `ModelTester` does: give the
  service an `isDictationBusy: () -> Bool` closure, wired in
  `DictationController.wireMenu()`, and check it **between chunks**. If
  dictation is recording, wait and retry every 250 ms before starting the next
  chunk. Dictation always wins.
- With `recognizerCacheCapacity` at its default of 2, using the same model for
  both costs nothing. Using a different model for the file loads a second one,
  which is the user's choice and is what the setting is for.

#### Where the result goes

A **Result** group appears when a job finishes:

- A selectable, scrollable text area with the transcript. Read-only for now.
- Row of actions: **Copy**, **Save as text file...** (`NSSavePanel`, defaults to
  the source file name with a `.txt` extension), **Clear**.
- A metadata line: source file name, audio length, how long it took, model used.
- If the job was cancelled: a caption in `PrefTheme.warning`, **Stopped early.
  This is only part of the file.**

The result is also written to History with `source: .file`, so it is not lost
if the user switches tabs. Do not auto-paste it anywhere. This tab is not
dictation.

#### New types

In `NiviCore` (Foundation only, so the core test runner can compile it):

- `enum TranscribableFormat` with the supported extension list and
  `static func isSupported(fileExtension:) -> Bool`. Pure table, easy to test.
- `enum AudioChunkPlanner` with
  `static func cutPoints(sampleCount:sampleRate:chunkSeconds:) -> [Int]` and a
  silence-aware variant that takes the samples. Testable.
- `enum DurationFormatting` with `func short(_ seconds: Double) -> String`
  producing "10 seconds", "1 min 12 s", "1 h 04 m". Used by History too.

In the app target:

- `Sources/Nivi/FileTranscription/AudioFileDecoder.swift`
- `Sources/Nivi/FileTranscription/FileTranscriptionService.swift`
- `Sources/Nivi/Preferences/TranscribeFileSection.swift`

### 4B. History

#### Storage format and location

File: `~/Library/Application Support/Nivi/history.jsonl`
(`ModelPaths.appSupportBase().appendingPathComponent("history.jsonl")`).

Format: JSON Lines. One JSON object per line, appended.

Why JSON Lines and not one big JSON array: appending a record is a single
`write` at the end of the file, so saving a dictation never rewrites the whole
history and never blocks the insert path. A crash mid-write loses at most the
last line, and a half-written last line is skipped on read instead of making
the whole file unreadable. A single JSON array would need a full re-encode on
every dictation.

Why not SQLite: we are storing a few thousand short strings. A database would
be more code, more failure modes, and a schema migration story, for no gain at
this size.

File permissions: create with `0600` so only the user can read it. The
directory already exists because models live there.

#### What a record holds

```swift
public struct HistoryRecord: Codable, Equatable, Identifiable {
    public var id: String            // UUID string
    public var createdAt: Date       // encoded as epoch seconds
    public var text: String
    public var durationMs: Int       // length of the audio, not of the transcription
    public var source: HistorySource // .dictation, .file, .modelTest
    public var modelID: String
    public var language: String
    public var profileID: String?    // nil for file jobs
    public var sourceName: String?   // file name for .file, front app name for .dictation
}

public enum HistorySource: String, Codable, CaseIterable {
    case dictation, file, modelTest
}
```

No audio. No waveform. No screenshot.

#### Size cost, honestly

A typical dictation is 150 to 300 characters. With the JSON keys around it, a
record is roughly 400 to 600 bytes. Heavy use at 100 dictations a day for 30
days is about 3,000 records, so under 2 MB. Thirty days of text history costs
nothing, and there is no reason to be clever about it.

Storing audio would change that completely. 16 kHz mono `Float32` is 3.84 MB
per minute, and even as 16-bit PCM it is 1.92 MB per minute. A month of daily
use would be gigabytes. **Do not store audio, and do not offer an option to.**
If someone later wants audio for re-transcription, that is a separate feature
with its own retention rules, not a checkbox here.

#### Retention

- Setting `historyRetentionDays`, default **30**.
- Picker options: 7 days, 30 days, 90 days, 1 year, Keep forever. "Keep
  forever" is stored as `0`.
- Pruning runs at app launch and after each append. It is cheap: read the
  file, drop expired records, and only rewrite if something was actually
  dropped. In the common case nothing is dropped and no write happens.
- The decision of what to drop is a pure function in `NiviCore`:

```swift
public enum HistoryRetention {
    /// Returns the records to keep. `retentionDays == 0` keeps everything.
    public static func keeping(_ records: [HistoryRecord],
                               retentionDays: Int,
                               now: Date) -> [HistoryRecord]
}
```

This is exactly the kind of logic that belongs in `NiviCore` and gets tests
in `Tools/core-tests/main.swift`.

#### Search, filter and sort

All in memory. A few thousand records is nothing.

- Filter chips: **All**, **Dictation**, **Files**. Drop Spokenly's "Journal",
  Nivi has no such thing. Add **Model tests** only if we decide to record
  those at all; default is to record them with `source: .modelTest` and hide
  them behind the All chip.
- Search box, matching `text` and `sourceName` with
  `localizedStandardContains`, which ignores case and diacritics. Hebrew
  niqqud is handled by that too.
- Sort menu: **Newest first** (default) and **Oldest first**.

The filter and sort logic is another pure function for `NiviCore`:

```swift
public struct HistoryQuery: Equatable {
    public var searchText: String
    public var sources: Set<HistorySource>?   // nil means all
    public var newestFirst: Bool
}

public enum HistoryFiltering {
    public static func apply(_ query: HistoryQuery, to records: [HistoryRecord]) -> [HistoryRecord]
}
```

#### The list

Each entry is a card, like `ModelCard` and `ProfileCard` already are:

- The transcribed text, up to 4 lines, then truncated. Click to expand.
- A row of small grey chips underneath: source (**Dictation** or the file name),
  relative time (**3 sec ago**, from `RelativeDateTimeFormatter`), and audio
  length (**10 seconds**, from `DurationFormatting.short`).
- On hover: a **Copy** button and a **Delete** button.

Use `LazyVStack` inside the `ScrollView` so a long history does not build
thousands of views at once.

Select mode: a **Select** button in the toolbar row turns on checkboxes and
swaps the toolbar for **Delete selected** and **Done**. Keep this simple, no
multi-select drag.

Delete all: a destructive `PrefButtonRow` in the History settings group, behind
a confirmation alert with the exact count, for example **Delete all 412 saved
transcriptions? This cannot be undone.**

#### Writing records

One call site for dictation, in `DictationController.stopAndTranscribe()`,
right after the text is known and before insertion. One call site for file
jobs, in `FileTranscriptionService`. One optional call site in `ModelTester`.

Writing must never delay the paste. Do the append on a background queue and
ignore failures beyond a `Log.error`. A failed history write must never break a
dictation.

#### Privacy

This is an offline, privacy-first app. The rules:

- History is a local file. Nothing is uploaded, ever. There is no network code
  in this feature.
- There is an off switch: `historyEnabled`, shown as **Keep history** at the top
  of the History settings group. When off, nothing is written. Default is on,
  because the user asked for 30-day retention by default.
- Turning it off does not delete what is already there. The Delete all button
  does that, and the copy under the toggle says so:
  *Turning this off stops saving new entries. It does not delete the ones you
  already have.*
- Every entry can be deleted on its own.

#### Interaction with `excludeFromClipboardHistory`

`Settings.excludeFromClipboardHistory` defaults to `true`. It marks the
clipboard item as transient so third-party clipboard managers (Raycast, Maccy,
Paste) skip it. Someone who leaves it on is telling us they do not want
dictated text sitting in a searchable list.

Nivi's own history is exactly such a list. That is a real tension and we
should be honest about it in the UI rather than silently resolving it.

Decision: do **not** auto-disable history based on that flag. That would be
surprising action at a distance. Instead, when
`excludeFromClipboardHistory` is on and `historyEnabled` is on, show this
caption under the **Keep history** row, in `PrefTheme.warning`:

*You keep dictated text out of your clipboard manager. Nivi's own history
still saves it here, on this Mac only.*

No behaviour change, just the truth on screen.

As noted in Step 1, `copyOnly` is consulted correctly in
`TextInserter.insert(...)`. There is no interaction to work around, and this
plan does not touch it.

#### New files

In `NiviCore`:
`HistoryRecord.swift`, `HistoryRetention.swift`, `HistoryFiltering.swift`,
`DurationFormatting.swift`. All Foundation only.

In the app target:
`Sources/Nivi/History/HistoryStore.swift` (the file reader, appender and
pruner, plus `@Published var records`) and
`Sources/Nivi/Preferences/HistorySection.swift`.

---

## Step 5: PR sequence

Seven PRs. All the data model and settings churn is in PR 1, and that contract
is frozen after it merges. PRs 2 to 7 add UI and behaviour and do not touch the
stored formats again.

Branch names follow the house rule, for example
`dvir/prefs-1-design-system`.

### PR 1: Preferences design system and the frozen data contract

**Changes**

- New `Sources/Nivi/Preferences/PrefTheme.swift` and
  `Sources/Nivi/Preferences/PrefKit.swift` with `PrefPage`, `PrefGroup`,
  `PrefRow`, `PrefToggleRow`, `PrefPickerRow`, `PrefStepperRow`,
  `PrefValueRow`, `PrefDisclosureRow`, `PrefButtonRow`, `PrefBanner`,
  `PrefEmptyState`, `PrefDivider`.
- Seven new keys in `UITuning.shipped`, listed in Step 2.
- `ModelsSection` and `ProfilesSection` card colours moved onto
  `PrefTheme.cardFill` and `PrefTheme.cardStroke`. No layout change.
- **All** new `Settings` keys added at once, with defaults registered:
  `appearance` (String: system/light/dark), `showInDock` (true),
  `showInStatusBar` (true), `escapeToCancelEnabled` (true),
  `muteWhileRecording` (false), `trackpadFeedback` (false),
  `textInputMethod` (String: paste/type), `microphonePriority` (JSON string),
  `wordReplacementsJSON` (String), `historyEnabled` (true),
  `historyRetentionDays` (30), `fileChunkMinutes` (5).
- **All** new `NiviCore` types added at once, Foundation only:
  `HistoryRecord`, `HistorySource`, `HistoryRetention`, `HistoryQuery`,
  `HistoryFiltering`, `DurationFormatting`, `WordReplacement` and its apply
  function, `TranscribableFormat`, `AudioChunkPlanner`.
- Tests for every one of those in `Tools/core-tests/main.swift`.
- General tab rewritten on the new components, as the first real use and the
  proof the system works. Only the rows that already exist. No new behaviour.

**Deliberately not in this PR**

- No other tab is converted.
- None of the new settings do anything yet. They are storage only.
- No History file is written. No Transcribe File tab exists.

**Verify**

- `bash Tools/run-core-tests.sh` passes, including the new checks.
- `make dev`, open Preferences, General looks like the target design: title,
  description, headings outside cards, dividers between rows.
- Every existing General toggle still writes the same `UserDefaults` key.
  Check with `defaults read com.dvir.nivi`.
- The Layout tab shows the seven new sliders, and `ui-tuning.conf` gains them
  after deleting the file and reopening Preferences.

### PR 2: Convert the remaining tabs and finish the shell

**Changes**

- Dictation Models, Profiles, Hotkeys, Speech, Layout and Debug rewritten on
  `PrefPage` and `PrefGroup`, using the exact strings from Step 3.
- Version string added at the bottom of the sidebar.
- `PrefBanner` wired for the Accessibility and Input Monitoring warnings.
- `NavigationStack` added around the detail pane, and the stack reset on
  sidebar selection change.
- `.formStyle(.grouped)` and `Form` removed from the Preferences tree entirely.

**Deliberately not in this PR**

- No new settings behaviour.
- No new tabs.

**Verify**

- `make dev`, click every tab. No tab still looks like a grouped `Form`.
- Every control still changes the same setting it did before.
- Revoke Accessibility in System Settings, reopen Preferences, and the orange
  banner appears on Profiles. Grant it again and the banner goes.
- Resize the window down to the 760 by 520 minimum. Nothing clips.

### PR 3: New General behaviour

**Changes**

- Appearance picker sets `NSApp.appearance`, applied at launch and on change.
- Show in Dock switches `NSApp.setActivationPolicy` between `.regular` and
  `.accessory`, applied at launch and on change, with the reopen fix described
  in Step 6.
- Show in the menu bar creates or removes the status item in
  `MenuBarController`.
- Guard so the last of the two cannot be turned off, plus the warning banner.
- Escape-to-cancel toggle wired to `HotkeyRouter`.
- Mute while recording, and trackpad feedback, wired into
  `DictationController.startRecording()` and `stopAndTranscribe()`.
- Text Input Method picker: batch mode now routes through `typeUnicode` when
  set to Type it out.
- Word Replacements sub-page, applying `WordReplacement` rules to the final
  text before insertion.

**Deliberately not in this PR**

- No microphone priority. That is its own PR.
- No history recording of what was replaced.

**Verify**

- Turn off Show in Dock. The Dock icon goes. Click the menu bar item, then
  Preferences, and the window still comes forward and takes focus.
- Turn off both Dock and menu bar. It refuses, and the banner explains why.
- Set Appearance to Light. The Preferences window and the recording panel both
  follow.
- Turn off Escape to cancel, start a recording, press Escape. Nothing happens.
  Turn it back on and it cancels.
- Add a replacement rule, dictate the trigger word, and the replacement lands
  in the target app.
- Set Text Input Method to Type it out and dictate into an app that blocks
  paste. The text arrives.

### PR 4: Microphone priority

**Changes**

- Enumerate input devices with `AVCaptureDevice.DiscoverySession` for
  `.microphone` plus `.external`.
- New `MicrophonePriorityStore` persisting an ordered list of device unique ids
  into the `microphonePriority` setting.
- `AudioRecorder.start()` picks the first connected device from that list and
  binds the engine's input node to it via
  `kAudioOutputUnitProperty_CurrentDevice` on the input node's audio unit.
  Falls back to the system default if the list is empty or nothing matches.
- Drag-to-reorder list in General, with the green dot and the disconnected
  state.
- Log the chosen device at recording start, next to the existing
  `Log.info("Recording input: ...")` line.

**Deliberately not in this PR**

- No hot-swap mid-recording. A device that disappears while recording keeps
  the existing behaviour.

**Verify**

- With AirPods and the built-in mic both available, put the built-in mic first
  and dictate. The log line names the built-in mic and the audio is from it.
- Disconnect the first device and dictate. It falls to the second one.
- Empty the list and dictate. It uses the system default, exactly as today.

### PR 5: History

**Changes**

- `HistoryStore` in the app target: read, append, prune, delete one, delete all.
- Prune at launch and after each append, using `HistoryRetention`.
- Write points in `DictationController.stopAndTranscribe()` and, optionally,
  `ModelTester`.
- The History tab: banner, filter chips, search, sort, list, select mode,
  settings group.

**Deliberately not in this PR**

- No audio saved.
- No export of the whole history.
- Nothing written from Transcribe File yet, because that tab does not exist.

**Verify**

- `bash Tools/run-core-tests.sh` still passes.
- Dictate three times, open History, see three entries newest first with
  correct durations and relative times.
- Search for a word, and only the matching entries stay.
- Delete one entry. Reopen the app. It is still gone.
- Set retention to 7 days, hand-edit `history.jsonl` to add an old record,
  restart, and it is pruned.
- Turn history off, dictate, and nothing new appears.
- `ls -l ~/Library/Application\ Support/Nivi/history.jsonl` shows `-rw-------`.

### PR 6: Transcribe File

**Changes**

- `AudioFileDecoder` using `AVAssetReader`, producing 16 kHz mono `Float32`.
- `FileTranscriptionService`, chunked, cancellable, reporting progress, sharing
  `RecognizerCache`, yielding to dictation between chunks.
- `isDictationBusy` wired in `DictationController.wireMenu()`, same as
  `ModelTester`.
- The Transcribe File tab: drop zone, file chooser, settings group, progress,
  result group with Copy and Save as text file.
- Finished jobs written to History with `source: .file`.

**Deliberately not in this PR**

- No `.srt` or timestamped export. `transcribeSegments` exists, so this is a
  cheap follow-up, but it is not needed for the first version.
- No batch queue. One file at a time.
- No streaming decode. The whole file is decoded first, which is fine up to
  about an hour.

**Verify**

- Drop a 30 second `.m4a`. It transcribes and the text appears.
- Drop a `.mp4` with an audio track. It transcribes.
- Drop a `.ogg`. A clear red banner says the format is not supported.
- Drop a video with no audio track. A clear banner says so.
- Start a 20 minute file, then press the dictation hotkey mid-job. Dictation
  starts, records and pastes normally. The file job continues afterwards.
- Cancel a running job. Partial text stays and is marked as partial.
- The finished job appears in History with a **Files** chip.

### PR 7: Polish pass

**Changes**

- Light mode review of every tab, now that the Appearance picker exists.
- Empty states, loading states and error states everywhere they are missing.
- Keyboard navigation: Tab order through rows, Escape closes sub-pages.
- VoiceOver labels on the icon-only controls, the drop zone and the microphone
  priority list.
- Final spacing pass using the Layout sliders, then the tuned numbers folded
  back into `UITuning.shipped` and `ui-tuning.conf` deleted.

**Deliberately not in this PR**

- No new features.

**Verify**

- Switch Appearance between Light and Dark on every tab. Nothing is unreadable.
- Navigate the whole window with the keyboard only.
- Turn on VoiceOver and check the drop zone and the mic list announce
  themselves.

---

## Step 6: risks and constraints

### Build and signing, non-negotiable

- **No Xcode is installed.** There is no Interface Builder, no asset catalog,
  no storyboard, and no `xcassets` compilation. All icons must be SF Symbols
  drawn at runtime, or PNGs copied by the `assemble_app` block in the
  `Makefile`. If a PR needs a new image, it must also add a `cp` line to that
  block, or the image will simply not be in the bundle.
- **`swift build` does not refresh the app bundle.** The `Makefile` says this
  in a comment for a reason: a bare `swift build` updates
  `.build/debug/Nivi` but leaves `build/Nivi.app` holding the old binary,
  so the app you launch silently runs stale code. **`make dev` is the only
  correct build path.** It rebuilds, reassembles the bundle, signs it,
  reinstalls to `/Applications`, and relaunches.
- **The app must always be signed with the stable "Nivi Self-Signed"
  identity.** macOS keys the Accessibility, Input Monitoring and Microphone
  grants to the signing identity. Ad-hoc signing (`-`) mints a new identity on
  every build and silently revokes all three. The symptom is not an error, it
  is auto-paste degrading to clipboard-only and Escape-to-cancel going dead.
  The `Makefile` already turns a missing certificate into a hard error. **Never
  pass `ALLOW_ADHOC=1`.** If the identity is missing, run `make cert`.
  `make perms` prints the current state.

### The in-flight opaque-window fix

`git status` shows uncommitted changes in **both**
`Sources/Nivi/PreferencesWindow.swift` and
`Sources/Nivi/Preferences/SettingsView.swift`. That is the separate fix
making the Preferences window opaque again after it went see-through.

Those are the two files PR 1 and PR 2 touch most. Consequences:

- **PR 1 must be branched from the commit that lands that fix, not started
  beside it.** Doing both at once guarantees a painful conflict in exactly the
  code that decides whether the window has a background.
- Do not copy the current `WindowMaterial` and `.background(...)` code into the
  new `PrefPage`. Whatever background the window ends up with belongs to
  `SettingsView`, not to the page scaffold. `PrefPage` must draw no background
  of its own and must not assume one exists.
- If the fix changes the window from a clear `NSWindow` with a masked layer to
  a normal opaque one, `PreferencesWindowChrome.cornerRadius` may go away. Do
  not build the design system on top of it.

### `NiviCore` must stay Foundation only

`Tools/run-core-tests.sh` compiles `Sources/NiviCore/*.swift` together with
`Tools/core-tests/main.swift` as a **single module**, which is why the test
file has no `import NiviCore`. Two rules follow:

- Any new file in `Sources/NiviCore/` is picked up automatically by the
  glob. Good. But it must import **only Foundation**. One `import AVFoundation`
  or `import SwiftUI` in that directory and the whole core test run stops
  compiling.
- So the split is: `TranscribableFormat` is a table of extension strings, not
  `UTType`. `AudioChunkPlanner` works on `[Float]` and `Int`, not on
  `AVAudioPCMBuffer`. `DurationFormatting` returns a `String` from a `Double`,
  and any `RelativeDateTimeFormatter` use stays in the view layer.

Also: `Tests/NiviCoreTests` exists alongside the script. Add new tests to
`Tools/core-tests/main.swift`, which is what actually runs, and mirror them
into `Tests/` only if the XCTest target is still being kept in sync.

### `_VariadicView.Tree` is an underscored API

`PrefGroup`'s divider insertion is the one place using non-public SwiftUI. It
has been stable across many macOS releases and is used widely, but Apple owes
us nothing. Keep `PrefDivider` public so the fallback is mechanical: drop the
variadic root and have callers put `PrefDivider()` between rows by hand.

### `.accessory` activation policy hides windows

Switching `NSApp.setActivationPolicy(.accessory)` for "Show in Dock: off" has a
known macOS quirk: a window opened afterwards can fail to come forward or take
keyboard focus. The fix, which `PreferencesWindow.show()` already half does, is
to call `NSApp.activate(ignoringOtherApps: true)` **and**
`window.makeKeyAndOrderFront(nil)` on every open, and to re-apply the policy on
`applicationDidBecomeActive`. Test this properly, because a Preferences window
you cannot bring forward while the Dock icon is hidden is a trap the user
cannot escape from. The "at least one of Dock or menu bar" guard exists exactly
to stop that.

### Mute while recording changes system state

Turning down the system output volume means we own restoring it. If the app
crashes or is force-quit mid-recording, the user's speakers stay muted with no
explanation. Mitigate by saving the previous volume into `UserDefaults` before
muting, and restoring it both at recording end and at the next app launch if
the flag is still set. Say this in the caption so it is not a surprise.

### Microphone priority is the most expensive item

Binding `AVAudioEngine`'s input node to a specific device needs
`kAudioOutputUnitProperty_CurrentDevice` set on the input node's underlying
audio unit, before the engine starts. It works, and it is the standard
approach, but it is low-level Core Audio in a file (`AudioRecorder.swift`) that
is currently simple and reliable. The comment there explains that a fresh
engine is built per recording precisely because reusing one went stale on route
changes. Do not undo that.

If this turns out to fight the existing per-recording engine, the honest
fallback is a simpler feature: a single "Preferred microphone" picker instead
of a priority list, falling back to the system default. Ship that rather than
destabilise recording.

### Long files hold real memory

A one-hour file decoded to 16 kHz mono `Float32` is about 230 MB in a Swift
array, on top of a 1.6 GB model. That is fine on a 16 GB Mac and tight on an
8 GB one. Cap the first version at a warning above about 90 minutes, and make
the decoder chunk-shaped from day one so streaming decode is a later change and
not a rewrite.

### Things this plan deliberately leaves out

- App UI language picker. No localization exists and none can be added without
  an asset catalog. One option in a picker is worse than no picker.
- Storing audio in History.
- Editing a history entry's text.
- Exporting history.
- `.srt` and timestamped output from Transcribe File.
- Any fix to `copyOnly`, which appears to be working correctly already.

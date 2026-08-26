# Installing Nivi

Nivi needs macOS 14 or newer, on an Apple Silicon Mac (M1 and later).

## 1. Download and drag

1. Download `Nivi-<version>.dmg`.
2. Double-click it. A window opens with the Nivi icon and a shortcut to your
   Applications folder.
3. Drag Nivi onto Applications.
4. Eject the disk image.

## 2. The first launch, and the scary message

The first time you open Nivi, macOS blocks it and shows something like:

> **"Nivi" cannot be opened because Apple cannot check it for malicious software.**

or, on some versions:

> **"Nivi" is damaged and can't be opened. You should move it to the Trash.**

**The app is not damaged.** macOS says this about every app that has not been
sent to Apple for checking. Apple charges $99 a year for a developer account,
and Nivi does not have one yet, so the app is signed by its author instead of
by Apple. macOS cannot tell the difference between "not checked by Apple" and
"broken", so it uses alarming words for both.

Here is how to open it. You only do this once.

1. Click **Done** or **OK** on the warning. Do not move it to the Trash.
2. Open **System Settings**.
3. Go to **Privacy & Security**.
4. Scroll down to the **Security** section. There is a line saying
   *"Nivi" was blocked to protect your Mac*, with an **Open Anyway** button
   next to it.
5. Click **Open Anyway**, and confirm with your password or Touch ID.
6. Nivi opens. From now on it opens normally, like any other app.

If you do not see the "Open Anyway" line, try opening Nivi once more first.
The line only appears right after macOS has blocked something.

### The other way, if you prefer the Terminal

Right-clicking the app and choosing **Open** used to work and no longer does on
recent macOS. This does:

```
xattr -dr com.apple.quarantine /Applications/Nivi.app
```

That removes the "downloaded from the internet" mark. Only run it on a file you
trust.

## 3. Permissions

Nivi asks for three things the first time it needs them. Each one opens a
System Settings page where you switch Nivi on.

| What it asks for | Why |
|---|---|
| **Microphone** | To hear you. Audio never leaves your Mac. |
| **Accessibility** | To paste the text into whatever app you are in, and to notice your hotkey. |
| **Input Monitoring** | To notice Esc when you want to cancel a recording. |

Accessibility and Input Monitoring look like the same thing but are two separate
switches. If your hotkey works but Esc does nothing, Input Monitoring is the one
that is off.

## 4. If you used Dictato before

Nivi is the same app under a new name. The first time you open it, it brings
your old settings across by itself: your profiles, your hotkeys, your chosen
models, your word replacements and your history. The speech models you already
downloaded are reused, so nothing is downloaded again.

Two things do not come across:

- **The three permissions in step 3.** macOS ties them to the app's signature,
  and to macOS this is a different app, so you grant them again. In System
  Settings you will see both **Dictato** and **Nivi** in the lists. Switch Nivi
  on. The Dictato rows can be removed with the minus button.
- **Opening at login.** If Dictato started at login, turn that on for Nivi in
  **Preferences > General**, and remove Dictato from
  **System Settings > General > Login Items**.

Once Nivi works the way you expect, drag **Dictato** from your Applications
folder to the Trash. Keeping both around only means two icons, two sets of
permissions, and dictating with whichever one you happened to open.

## 5. Updates

Nivi checks once a day whether a newer version exists, and tells you when
there is one. It never installs anything without asking. You can turn the
automatic check off, or check right now, in **Preferences > General > Updates**.

## What changes once the app is notarized

"Notarized" means Apple has scanned the app and vouched for it. When that
happens:

- Step 2 above disappears entirely. Double-click and the app opens.
- No "cannot be checked" or "damaged" message, no trip to System Settings.
- Updates install with no warning either.

Nothing else changes. The app is the same app, and the permissions in step 3 are
still asked for the same way. If you already installed the self-signed version,
the notarized update replaces it in place and you do not have to redo anything.
